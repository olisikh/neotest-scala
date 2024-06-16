local lib = require("neotest.lib")

local M = {}

--- Strip quotes from the (captured) test position.
---@param position neotest.Position
---@return string
function M.get_position_name(position)
    if position.type == "test" then
        local value = string.gsub(position.name, '"', "")
        return value
    end
    return position.name
end

---Get a package name from the top of the file.
---@return string|nil
function M.get_package_name(file)
    local success, lines = pcall(lib.files.read_lines, file)
    if not success then
        return nil
    end
    local line = lines[1]
    if vim.startswith(line, "package") then
        return vim.split(line, " ")[2] .. "."
    end
    return ""
end

---@param project string
---@param runner string
---@param test_path string|nil
---@param extra_args table|string
---@return string[]
function M.build_command_with_test_path(project, runner, test_path, extra_args)
    if runner == "bloop" then
        local full_test_path
        if not test_path then
            full_test_path = {}
        else
            full_test_path = { "--", test_path }
        end
        return vim.tbl_flatten({ "bloop", "test", extra_args, project, full_test_path })
    end

    if not test_path then
        return vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    end

    return vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly -- " .. '"' .. test_path .. '"' })
end

--- Strip ANSI characters from the string, leaving the rest of the string intact.
---@param s string
---@return string
function M.strip_ansi_chars(s)
    local v = s:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
    return v
end

--- Strip sbt info logging prefix from string.
---@param s string
---@return string
function M.strip_sbt_log_prefix(s)
    local v = s:gsub("^%[info%] ", ""):gsub("^%[error%] ", ""):gsub("^%[debug%]", ""):gsub("^%[warn%] ", "")
    return v
end

function M.strip_bloop_error_prefix(s)
    local v = s:gsub("^%[E%] ", "")
    return v
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
local function string_trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---Normalize spaces in a string
---@param s string
local function string_despace(s)
    return (s:gsub("%s+", " "))
end

local function parse_project_info(text)
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
            table.insert(result[curr_section], string_despace(string_trim(content)))
        end
    end

    return result
end

---Get the first build target name by listing build targets that Metals has found
---@param root_path string project path where build.sbt is
---@param target_path string path to the file or folder that is being tested
---@param timeout integer? timeout for the request
---@return table | nil project info
function M.resolve_project(root_path, target_path, timeout)
    local metals = M.find_metals()
    local project = nil
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
                -- just like the source path looks like in project_info
                local target_src_path = target_path:gsub("%*$", "")

                for _, name in ipairs(response.result) do
                    local project_info = M.get_project_info(root_path, name, timeout)
                    if project_info and project_info["Sources"] then
                        for _, src_path in ipairs(project_info["Sources"]) do
                            -- remove the * at the end of the source path to compare with target file path
                            src_path = src_path:gsub("%*$", "")

                            if vim.startswith(target_src_path, src_path) then
                                project = project_info
                                break
                            end
                        end
                    end
                end
            else
                project = response.result[1]
            end
        end
    end

    return project
end

---Get project report, contains information about the project, it's classpath in particular
---@param path string project path (root folder)
---@param project string project name
---@param timeout integer? timeout for the request
---@return table report about the project
function M.get_project_info(path, project, timeout)
    local metals = M.find_metals()
    local project_info = {}

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
            project_info = parse_project_info(response.result.value)
        end
    end

    return project_info
end

---Take build target name and turn it into a module name
function M.get_project_name(project_info)
    if project_info and project_info["Target"] then
        -- TODO: this is probably unreliable? the build target is usually root-test but the project name is root
        return (project_info["Target"][1]:gsub("-test$", ""))
    end
end

---Search for a test library dependency in a test build target
---@param project_info table project info
---@return string name of the test library being used in the project
function M.get_framework(project_info)
    local framework = nil

    if project_info and project_info["Scala Classpath"] then
        local classpath = project_info["Scala Classpath"]

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
