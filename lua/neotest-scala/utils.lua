local lib = require("neotest.lib")
local Path = require("plenary.path")

local M = {}

--- Strip quotes from the (captured) test position.
---@param position neotest.Position
---@return string
function M.get_position_name(position)
    if position.type == "test" then
        return (position.name:gsub('"', ""))
    end
    return position.name
end

--- Strip quotes from the (captured) test position.
---@param test neotest.Tree
---@return boolean
function M.has_nested_tests(test)
    return #test:children() > 0
end

---Find namespace type parent node if available
---@param tree neotest.Tree node tree containing tests information
---@param type string node type file / dir / namespace / test
---@param down boolean direction of the search, search children or parents
---@return neotest.Tree|nil namespace parent node or nil if not found
function M.find_node(tree, type, down)
    if tree:data().type == type then
        return tree
    elseif not down then
        local p = tree:parent()
        if p then
            return M.find_node(p, type, down)
        else
            return nil
        end
    else
        for _, child in tree:iter_nodes() do
            if child:data().type == type then
                return child
            end
        end
    end
end

---Get a package name from the top of the file.
---@return string|nil
function M.get_package_name(path)
    local success, lines = pcall(lib.files.read_lines, path)
    if not success then
        return nil
    end
    local line = lines[1]
    if vim.startswith(line, "package") then
        return vim.split(line, " ")[2] .. "."
    end
    return ""
end

function M.get_file_name(path)
    local parts = vim.split(path, Path.path.sep)
    return parts[#parts]
end

function M.build_test_namespace(tree)
    local type = tree:data().type
    local path = tree:data().path

    if type == "dir" then
        -- run all tests, but we could technically figure out the package?
        return "*"
    end

    local package = M.get_package_name(path)

    local ns_node = nil
    if type == "file" then
        ns_node = M.find_node(tree, "namespace", true)
    elseif type == "namespace" then
        ns_node = tree
    else
        ns_node = M.find_node(tree, "namespace", false)
    end

    if ns_node then
        return package .. ns_node:data().name -- run individual spec
    else
        return package .. "*" -- otherwise run tests for whole package
    end
end

--- Builds a command for running tests for the framework.
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(project, tree, name, extra_args)
    local test_namespace = M.build_test_namespace(tree)

    local command = nil

    if not test_namespace then
        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    else
        local test_path = ""
        if tree:data().type == "test" then
            test_path = ' -- -t "' .. name .. '"'
        end

        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
    end

    return command
end

---@param project string
---@param test_path string|nil
---@param extra_args table|string
---@return string[]
function M.build_command_with_test_path(project, test_path, extra_args)
    if not test_path then
        return vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    end

    return vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly -- " .. '"' .. test_path .. '"' })
end

---Returns Metals LSP client if Metals is active on current buffer
---@param bufnr integer? bunfr to look for metals client
---@return vim.lsp.Client?
function M.find_metals(bufnr)
    local clients = vim.lsp.get_clients({ name = "metals", bufnr = bufnr })
    if #clients > 0 then
        return clients[1]
    end
    return nil
end

---Trim the string
---@param s string
function M.string_trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---Normalize spaces in a string
---@param s string
function M.string_despace(s)
    return (s:gsub("%s+", " "))
end

---Remove quotes from string
---@param s string
function M.string_remove_dquotes(s)
    return (s:gsub('^%s*"', ""):gsub('"$', ""))
end

---Remove ANSI characters from string
function M.string_remove_ansi(s)
    return (s:gsub("%[%d*;?%d*m", ""))
end

function M.inspect(tbl)
    vim.print(vim.inspect(tbl))
end

function M.string_unescape_xml(s)
    local xml_escapes = {
        ["&quot;"] = '"',
        ["&apos;"] = "'",
        ["&amp;"] = "&",
        ["&lt;"] = "<",
        ["&gt;"] = ">",
    }

    for esc, char in pairs(xml_escapes) do
        s = string.gsub(s, esc, char)
    end

    return s
end

---NOTE: If the format in which metals returns decoded file output changes - this function might start failing
local function parse_build_target_info(text)
    local result = {}
    local curr_section = nil

    for line in text:gmatch("[^\r\n]+") do
        local indent, content = line:match("^(%s*)(.*)")
        local indent_lvl = #indent

        if indent_lvl == 0 and content ~= "" then
            -- new section
            curr_section = content
            result[curr_section] = {}
        elseif indent_lvl > 0 and content ~= "" and curr_section then
            -- item under the current section, store into result array
            table.insert(result[curr_section], M.string_despace(M.string_trim(content)))
        end
    end

    return result
end

---Get project report, contains information about the project, it's classpath in particular
---@param metals vim.lsp.Client metals client
---@param path string project path (root folder)
---@param project string project name
---@param timeout integer? timeout for the request
---@return table | nil report about the project
local function fetch_build_target_info(metals, path, project, timeout)
    local build_target_info = nil

    if metals then
        local metals_uri = string.format("metalsDecode:file://%s/%s.metals-buildtarget", path, project)

        local params = {
            command = "metals.file-decode",
            arguments = { metals_uri },
        }
        local response = metals.request_sync("workspace/executeCommand", params, timeout or 10000, 0)
        if not response or response.err then
            vim.print("[neotest-scala]: Failed to get build target info, please try again")
        else
            build_target_info = parse_build_target_info(response.result.value)
        end
    end

    return build_target_info
end

---Get the build target info by listing build targets that Metals has found and finding he one that matches
---@param root_path string project path where build.sbt is
---@param target_path string path to the file or folder that is being tested
---@param timeout integer? timeout for the request
---@return table | nil build target info
function M.get_build_target_info(root_path, target_path, timeout)
    local metals = M.find_metals()
    local result = nil
    timeout = timeout or 10000

    if metals then
        local body = { command = "metals.list-build-targets" }
        local response = metals.request_sync("workspace/executeCommand", body, timeout, 0)

        if not response or #response.result == 0 then
            vim.print("[neotest-scala]: Metals returned no project name, please try again.")
        elseif response.err then
            vim.print("[neotest-scala]: Request to metals failed: " .. response.err.message)
        else
            if #response.result > 1 then
                -- remove the test file name, replacing it with a star,
                -- just like the source path looks like in build_target_info
                local target_src_path = target_path:gsub("%*$", "")

                for _, name in ipairs(response.result) do
                    local build_target_info = fetch_build_target_info(metals, root_path, name, timeout)
                    if build_target_info and build_target_info["Sources"] then
                        for _, src_path in ipairs(build_target_info["Sources"]) do
                            -- remove the * at the end of the source path to compare with target file path
                            src_path = src_path:gsub("%*$", "")

                            if vim.startswith(target_src_path, src_path) then
                                result = build_target_info
                                break
                            end
                        end
                    end
                end
            else
                result = response.result[1]
            end
        end
    end

    return result
end

---Take build target name and turn it into a module name
function M.get_project_name(build_target_info)
    if build_target_info and build_target_info["Target"] then
        -- TODO: this is probably unreliable? the build target is usually root-test but the project name is root
        return (build_target_info["Target"][1]:gsub("-test$", ""))
    end
end

---Search for a test library dependency in a test build target
---@param build_target_info table build target info
---@return string name of the test library being used in the project
function M.get_framework(build_target_info)
    local framework = nil

    if build_target_info then
        local classpath = build_target_info["Scala Classpath"] or build_target_info["Classpath"]

        for _, jar in ipairs(classpath) do
            framework = jar:match("(specs2)-core_.*-.*%.jar")
                or jar:match("(munit)_.*-.*%.jar")
                or jar:match("(scalatest)_.*-.*%.jar")
                or jar:match("(utest)_.*-.*%.jar")
                or jar:match("(zio%-test)_.*-.*%.jar")

            if framework then
                break
            end
        end
    end

    return framework or "scalatest"
end

return M
