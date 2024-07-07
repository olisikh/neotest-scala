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
    local test_namespace = utils.build_test_namespace(tree)

    if not test_namespace then
        return vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    end

    local test_path = ""
    if tree:data().type == "test" then
        test_path = ' -- -z "' .. name .. '"'
    end
    return vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
end

-- Get test results from the test output.
---@param junit_test table<string, string>
---@param position neotest.Position
---@return string|nil
function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = package_name .. junit_test.namespace .. "." .. junit_test.name:gsub(" ", ".")
    local test_id = position.id:gsub(" ", ".")

    return junit_test_id == test_id
end

---@return neotest-scala.Framework
return M
