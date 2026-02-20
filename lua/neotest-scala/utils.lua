local lib = require("neotest.lib")
local Path = require("plenary.path")

local M = {}

-- Configuration with defaults
local config = {
    build_tool = "auto", -- "auto", "bloop", or "sbt"
    compile_on_save = false,
    cache_build_info = true,
}

--- Flatten a table (replacement for deprecated vim.tbl_flatten)
---@param tbl table
---@return table
local function flatten(tbl)
    local result = {}
    for _, v in ipairs(tbl) do
        if type(v) == "table" then
            for _, item in ipairs(v) do
                table.insert(result, item)
            end
        else
            table.insert(result, v)
        end
    end
    return result
end

-- Cache for build target info
local build_target_cache = {}
local cache_timestamp = {}

--- Update configuration
---@param opts table
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

--- Get current configuration
---@return table
function M.get_config()
    return config
end

--- Check if Bloop is available in the project
---@param root_path string Project root path
---@return boolean
function M.is_bloop_available(root_path)
    local bloop_dir = root_path .. "/.bloop"
    local stat = vim.loop.fs_stat(bloop_dir)
    if not (stat ~= nil and stat.type == "directory") then
        return false
    end
    -- Also check if bloop binary is actually executable
    return vim.fn.executable("bloop") == 1
end

--- Determine which build tool to use
---@param root_path string Project root path
---@return string "bloop" or "sbt"
function M.get_build_tool(root_path)
    if config.build_tool == "bloop" then
        return "bloop"
    elseif config.build_tool == "sbt" then
        return "sbt"
    else
        -- Auto-detect: use bloop if available, fallback to sbt
        if M.is_bloop_available(root_path) then
            return "bloop"
        end
        return "sbt"
    end
end

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

--- Build command using sbt
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
local function build_sbt_command(project, tree, name, extra_args)
    local test_namespace = M.build_test_namespace(tree)
    local command = nil

    if not test_namespace then
        command = flatten({ "sbt", extra_args, project .. "/test" })
    else
        local test_path = ""
        if tree:data().type == "test" then
            test_path = ' -- -t "' .. name .. '"'
        end
        command = flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
    end

    return command
end

--- Build command using bloop (much faster)
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
local function build_bloop_command(project, tree, name, extra_args)
    local test_namespace = M.build_test_namespace(tree)
    local command = nil

    -- Bloop project name is typically the same as sbt project name
    local bloop_project = project .. "-test"

    if not test_namespace or test_namespace == "*" then
        -- Run all tests in project
        command = flatten({ "bloop", "test", bloop_project, extra_args })
    else
        -- Run specific test class
        local args = { "bloop", "test", bloop_project, "--only", test_namespace }
        
        -- For single test, use --test-filter (bloop >= 1.5.0)
        if tree:data().type == "test" then
            table.insert(args, "-o")
            table.insert(args, name)
        end
        
        command = flatten({ args, extra_args })
    end

    return command
end

--- Builds a command for running tests for the framework.
---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    local build_tool = M.get_build_tool(root_path)
    
    if build_tool == "bloop" then
        return build_bloop_command(project, tree, name, extra_args)
    else
        return build_sbt_command(project, tree, name, extra_args)
    end
end

--- Build sbt command with test path (legacy)
---@param project string
---@param test_path string|nil
---@param extra_args table|string
---@return string[]
local function build_sbt_command_with_test_path(project, test_path, extra_args)
    if not test_path then
        return flatten({ "sbt", extra_args, project .. "/test" })
    end
    return flatten({ "sbt", extra_args, project .. "/testOnly -- " .. '"' .. test_path .. '"' })
end

--- Build bloop command with test path
---@param project string
---@param test_path string|nil
---@param extra_args table|string
---@return string[]
local function build_bloop_command_with_test_path(project, test_path, extra_args)
    local bloop_project = project .. "-test"
    
    if not test_path then
        return flatten({ "bloop", "test", bloop_project, extra_args })
    end
    return flatten({ "bloop", "test", bloop_project, "--only", test_path, extra_args })
end

---@param root_path string Project root path
---@param project string
---@param test_path string|nil
---@param extra_args table|string
---@return string[]
function M.build_command_with_test_path(root_path, project, test_path, extra_args)
    local build_tool = M.get_build_tool(root_path)
    
    if build_tool == "bloop" then
        return build_bloop_command_with_test_path(project, test_path, extra_args)
    else
        return build_sbt_command_with_test_path(project, test_path, extra_args)
    end
end

--- Compile the project using bloop (background)
---@param root_path string Project root path
---@param project string Project name
---@param callback function|nil Optional callback when done
function M.compile_project(root_path, project, callback)
    local build_tool = M.get_build_tool(root_path)
    
    if build_tool ~= "bloop" then
        -- sbt compilation is slower, skip background compile
        return
    end
    
    local bloop_project = project .. "-test"
    local cmd = { "bloop", "compile", bloop_project }
    
    vim.notify("[neotest-scala] Compiling " .. bloop_project .. "...", vim.log.levels.INFO)
    
    vim.loop.spawn("bloop", {
        args = { "compile", bloop_project },
        cwd = root_path,
    }, function(code, _)
        vim.schedule(function()
            if code == 0 then
                vim.notify("[neotest-scala] Compilation successful", vim.log.levels.INFO)
            else
                vim.notify("[neotest-scala] Compilation failed", vim.log.levels.WARN)
            end
            if callback then
                callback(code)
            end
        end)
    end)
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
    return (s:gsub('^s*"', ""):gsub('"$', ""))
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

--- Get cache key for build target info
---@param root_path string
---@param target_path string
---@return string
local function get_cache_key(root_path, target_path)
    return root_path .. ":" .. target_path
end

--- Invalidate build target cache
---@param root_path string|nil Optional: invalidate only for this root
function M.invalidate_cache(root_path)
    if root_path then
        for key, _ in pairs(build_target_cache) do
            if vim.startswith(key, root_path) then
                build_target_cache[key] = nil
                cache_timestamp[key] = nil
            end
        end
    else
        build_target_cache = {}
        cache_timestamp = {}
    end
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
    -- Check cache first
    if config.cache_build_info then
        local cache_key = get_cache_key(root_path, target_path)
        local cached = build_target_cache[cache_key]
        local timestamp = cache_timestamp[cache_key]
        
        -- Cache is valid for 60 seconds
        if cached and timestamp and (os.time() - timestamp) < 60 then
            return cached
        end
    end
    
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

    -- Cache the result
    if config.cache_build_info and result then
        local cache_key = get_cache_key(root_path, target_path)
        build_target_cache[cache_key] = result
        cache_timestamp[cache_key] = os.time()
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
        
        if classpath then
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
    end

    return framework or "scalatest"
end

--- Setup autocommands for background compilation on save
---@param root_path string Project root path
function M.setup_compile_on_save(root_path)
    if not config.compile_on_save then
        return
    end
    
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.scala",
        callback = function(event)
            local buf_path = event.match
            local buf_root = lib.files.match_root_pattern("build.sbt")(buf_path)
            
            if buf_root == root_path then
                local build_target_info = M.get_build_target_info(root_path, buf_path)
                if build_target_info then
                    local project_name = M.get_project_name(build_target_info)
                    if project_name then
                        M.compile_project(root_path, project_name)
                    end
                end
            end
        end,
        group = vim.api.nvim_create_augroup("neotest-scala-compile", { clear = true }),
    })
end

return M
