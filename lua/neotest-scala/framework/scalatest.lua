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

---@return neotest-scala.Framework
return M
