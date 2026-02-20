local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

--- Builds a command for running tests for the framework.
---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    return utils.build_command(root_path, project, tree, name, extra_args)
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = package_name .. junit_test.namespace .. "." .. junit_test.name:gsub(" ", ".")
    local test_id = position.id:gsub(" ", ".")

    return junit_test_id == test_id
end

---Build test result with diagnostic message for failed tests
---@param junit_test table<string, string>
---@param position neotest.Position
---@return table
function M.build_test_result(junit_test, position)
    local result = {}
    local error = {}

    local file_name = utils.get_file_name(position.path)

    if junit_test.error_message then
        error.message = junit_test.error_message

        if junit_test.error_stacktrace then
            local line_num = string.match(junit_test.error_stacktrace, "%(" .. file_name .. ":(%d+)%)")
            if line_num then
                error.line = tonumber(line_num) - 1
            end
        end
    elseif junit_test.error_stacktrace then
        local lines = vim.split(junit_test.error_stacktrace, "\n")
        error.message = lines[1]

        local line_num = string.match(junit_test.error_stacktrace, "%(" .. file_name .. ":(%d+)%)")
        if line_num then
            error.line = tonumber(line_num) - 1
        end
    end

    if error.message then
        result = {
            status = TEST_FAILED,
            errors = { error },
        }
    else
        result = {
            status = TEST_PASSED,
        }
    end

    return result
end

---@return neotest-scala.Framework
return M
