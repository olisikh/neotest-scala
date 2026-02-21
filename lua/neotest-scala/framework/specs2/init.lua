local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

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
    return build.command(root_path, project, tree, name, extra_args)
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local test_id = position.id:gsub(" ", ".")

    local test_prefix = package_name .. junit_test.namespace
    local test_postfix = junit_test.name:gsub("should::", ""):gsub("must::", ""):gsub("::", "."):gsub(" ", ".")

    return vim.startswith(test_id, test_prefix) and vim.endswith(test_id, test_postfix)
end

---@return neotest-scala.Framework
return M
