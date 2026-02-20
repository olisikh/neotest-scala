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
    local junit_test_id = (package_name .. junit_test.namespace .. "." .. junit_test.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")

    return junit_test_id == test_id
end

---Extract the highest line number for the given file from stacktrace
---ScalaTest stacktraces have multiple file references (class def, test method, etc.)
---We want the highest line number which corresponds to the actual test assertion
---@param stacktrace string
---@param file_name string
---@return number|nil
local function extract_line_number(stacktrace, file_name)
    local max_line_num = nil
    local pattern = "%(" .. file_name .. ":(%d+)%)"

    for line_num_str in string.gmatch(stacktrace, pattern) do
        local line_num = tonumber(line_num_str)
        if not max_line_num or line_num > max_line_num then
            max_line_num = line_num
        end
    end

    return max_line_num and (max_line_num - 1) or nil
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
            error.line = extract_line_number(junit_test.error_stacktrace, file_name)
        end
    elseif junit_test.error_stacktrace then
        local lines = vim.split(junit_test.error_stacktrace, "\n")
        error.message = lines[1]

        error.line = extract_line_number(junit_test.error_stacktrace, file_name)
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
