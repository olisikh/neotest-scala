local lib = require("neotest.lib")

local M = {}

-- Configuration
local config = {
    build_tool = "auto",
    compile_on_save = false,
}

-- Flatten a table
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

--- Update configuration
---@param opts table
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
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
    return vim.fn.executable("bloop") == 1
end

--- Determine which build tool to use
---@param root_path string Project root path
---@return string "bloop" or "sbt"
function M.get_tool(root_path)
    if config.build_tool == "bloop" then
        return "bloop"
    elseif config.build_tool == "sbt" then
        return "sbt"
    else
        if M.is_bloop_available(root_path) then
            return "bloop"
        end
        return "sbt"
    end
end

--- Resolve which build tool to use, optionally honoring a per-run override.
---@param root_path string Project root path
---@param tool_override string|nil
---@return string "bloop" or "sbt"
function M.resolve_tool(root_path, tool_override)
    if tool_override == "bloop" or tool_override == "sbt" then
        return tool_override
    end

    return M.get_tool(root_path)
end

--- Merge two argument values (nil|string|string[]), preserving caller-friendly behavior.
--- Rules:
--- - nil + X => X
--- - X + nil => X
--- - table + table => concatenated table
--- - string + string => { left, right }
--- - string + table => { left, ...table }
--- - table + string => { ...table, right }
---@param left nil|string|string[]
---@param right nil|string|string[]
---@return nil|string|string[]
function M.merge_args(left, right)
    local left_is_table = type(left) == "table"
    local right_is_table = type(right) == "table"

    if left_is_table and #left == 0 then
        left = nil
        left_is_table = false
    end

    if right_is_table and #right == 0 then
        right = nil
        right_is_table = false
    end

    if left == nil then
        return right
    end

    if right == nil then
        return left
    end

    if left_is_table and right_is_table then
        local result = vim.deepcopy(left)
        return vim.list_extend(result, vim.deepcopy(right))
    end

    if left_is_table then
        local result = vim.deepcopy(left)
        table.insert(result, right)
        return result
    end

    if right_is_table then
        local result = { left }
        return vim.list_extend(result, vim.deepcopy(right))
    end

    return { left, right }
end

--- Build test namespace from tree
---@param tree neotest.Tree
---@return string
local function build_test_namespace(tree)
    local utils = require("neotest-scala.utils")
    local data = tree:data()
    local type = data.type
    local path = data.path

    if type == "dir" then
        return "*"
    end

    local package = utils.get_package_name(path)
    local ns_node = nil

    if type == "file" then
        ns_node = utils.find_node(tree, "namespace", true)
    elseif type == "namespace" then
        ns_node = tree
    else
        ns_node = utils.find_node(tree, "namespace", false)
    end

    if ns_node then
        local ns_data = ns_node:data()
        return package .. ns_data.name
    else
        return package .. "*"
    end
end

--- Build command using sbt
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
local function build_sbt_command(project, tree, name, extra_args)
    local test_namespace = build_test_namespace(tree)

    if not test_namespace then
        return flatten({ "sbt", extra_args, project .. "/test" })
    end

    local test_path = ""
    local tree_data = tree:data()
    if tree_data.type == "test" then
        test_path = ' -- -t "' .. name .. '"'
    end

    return flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
end

--- Build command using bloop
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
local function build_bloop_command(project, tree, name, extra_args)
    local test_namespace = build_test_namespace(tree)
    local bloop_project = project .. "-test"

    if not test_namespace or test_namespace == "*" then
        return flatten({ "bloop", "test", bloop_project, extra_args })
    end

    local args = { "bloop", "test", bloop_project, "--only", test_namespace }

    local bloop_tree_data = tree:data()
    if bloop_tree_data.type == "test" then
        table.insert(args, "-o")
        table.insert(args, name)
    end

    return flatten({ args, extra_args })
end

--- Builds a command for running tests
---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@param tool_override string|nil
---@return string[]
function M.command(root_path, project, tree, name, extra_args, tool_override)
    local build_tool = M.resolve_tool(root_path, tool_override)

    if build_tool == "bloop" then
        return build_bloop_command(project, tree, name, extra_args)
    else
        return build_sbt_command(project, tree, name, extra_args)
    end
end

--- Build command with explicit test path (used by munit/utest)
---@param root_path string Project root path
---@param project string
---@param test_path string|nil
---@param extra_args table|string
---@param tool_override string|nil
---@return string[]
function M.command_with_path(root_path, project, test_path, extra_args, tool_override)
    local build_tool = M.resolve_tool(root_path, tool_override)
    local bloop_project = project .. "-test"

    if build_tool == "bloop" then
        if not test_path then
            return flatten({ "bloop", "test", bloop_project, extra_args })
        end

        return flatten({ "bloop", "test", bloop_project, "--only", test_path, extra_args })
    else
        if not test_path then
            return flatten({ "sbt", extra_args, project .. "/test" })
        end
        return flatten({ "sbt", extra_args, project .. "/testOnly -- " .. '"' .. test_path .. '"' })
    end
end

--- Compile the project using bloop (background)
---@param root_path string Project root path
---@param project string Project name
---@param callback function|nil Optional callback when done
function M.compile(root_path, project, callback)
    local build_tool = M.get_tool(root_path)

    if build_tool ~= "bloop" then
        return
    end

    local bloop_project = project .. "-test"

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

--- Setup autocommands for background compilation on save
---@param root_path string Project root path
---@param get_build_info function Function to get build target info
function M.setup_compile_on_save(root_path, get_build_info)
    if not config.compile_on_save then
        return
    end

    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.scala",
        callback = function(event)
            local buf_path = event.match
            local buf_root = lib.files.match_root_pattern("build.sbt")(buf_path)

            if buf_root == root_path then
                local build_target_info = get_build_info(root_path, buf_path)
                if build_target_info then
                    local metals = require("neotest-scala.metals")
                    local project_name = metals.get_project_name(build_target_info)
                    if project_name then
                        M.compile(root_path, project_name)
                    end
                end
            end
        end,
        group = vim.api.nvim_create_augroup("neotest-scala-compile", { clear = true }),
    })
end

return M
