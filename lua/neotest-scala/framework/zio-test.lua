local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

--- Builds a command for running tests for the framework.
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(project, tree, name, extra_args)
    return utils.build_command(project, tree, name, extra_args)
end

function M.build_test_result(junit_test, position)
    local result = nil
    local error = {}

    local file_name = utils.get_file_name(position.path)

    if junit_test.error_message then
        local msg = vim.split(junit_test.error_message, "\n")
        table.remove(msg, 1) -- it's just the name of the test, starts with - or x

        local last_line = table.remove(msg, #msg - 1) -- can be used to get a line number
        local line_num = string.match(vim.trim(last_line), "^at /.*/" .. file_name .. ":(%d+)$")
            or string.match(junit_test.error_message, "%(" .. file_name .. ":(%d+)%)")

        if line_num then
            error.line = tonumber(line_num) - 1 -- minus 1 because Lua indexes are 1-based
        else
            -- since there's no line num, then let's add it back
            table.insert(msg, last_line)
        end

        error.message = table.concat(msg, "\n")
    elseif junit_test.error_stacktrace then
        local line_num = string.match(junit_test.error_stacktrace, "%(" .. file_name .. ":(%d+)%)")
        if line_num then
            error.line = tonumber(line_num) - 1
        end

        error.message = junit_test.error_stacktrace
    end

    if not vim.tbl_isempty(error) then
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
