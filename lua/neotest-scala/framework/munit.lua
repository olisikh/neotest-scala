local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

-- Builds a test path from the current position in the tree.
---@param tree neotest.Tree
---@param name string
---@return string|nil
local function build_test_path(tree, name)
    local parent_tree = tree:parent()
    local type = tree:data().type
    if parent_tree and parent_tree:data().type == "namespace" then
        local package = utils.get_package_name(parent_tree:data().path)
        local parent_name = parent_tree:data().name
        return package .. parent_name .. "." .. name
    end
    if parent_tree and parent_tree:data().type == "test" then
        local parent_pos = parent_tree:data()
        return build_test_path(parent_tree, utils.get_position_name(parent_pos)) .. "." .. name
    end
    if type == "namespace" then
        local package = utils.get_package_name(tree:data().path)
        if not package then
            return nil
        end
        return package .. name .. ".*"
    end
    if type == "file" then
        local test_suites = {}
        for _, child in tree:iter_nodes() do
            if child:data().type == "namespace" then
                table.insert(test_suites, child:data().name)
            end
        end
        if test_suites then
            local package = utils.get_package_name(tree:data().path)
            return package .. "*"
        end
    end
    if type == "dir" then
        return "*"
    end
    return nil
end

function M.build_test_result(junit_test, position)
    local result = nil
    local error = {}

    local file_name = utils.get_file_name(position.path)
    local raw_message = junit_test.error_stacktrace or junit_test.error_message

    if raw_message then
        error.message = raw_message:gsub("/.*/" .. file_name .. ":%d+ ", "") -- prettify message

        local line_num = string.match(raw_message, "%(" .. file_name .. ":(%d+)%)") -- figure out line number
        if line_num then
            error.line = tonumber(line_num) - 1
        end
    end

    if vim.tbl_isempty(error) then
        result = { status = TEST_PASSED }
    else
        result = { status = TEST_FAILED, errors = { error } }
    end

    return result
end

--- Builds a command for running tests for the framework.
---@param runner string
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(runner, project, tree, name, extra_args)
    local test_path = build_test_path(tree, name)
    return utils.build_command_with_test_path(project, runner, test_path, extra_args)
end

---@return neotest-scala.Framework
return M
