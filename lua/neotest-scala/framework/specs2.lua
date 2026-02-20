local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    local test_namespace = utils.build_test_namespace(tree)

    if not test_namespace then
        return utils.build_command(root_path, project, tree, name, extra_args)
    end

    return utils.build_command(root_path, project, tree, name, extra_args)
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_test(junit_test, position)
    if position.extra and position.extra.textspec_path then
        return M.match_textspec_test(junit_test, position)
    end
    return M.match_mutable_spec_test(junit_test, position)
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_textspec_test(junit_test, position)
    local textspec_path = position.extra.textspec_path
    local junit_name = junit_test.name or ""
    return textspec_path:find(junit_name, 1, true) ~= nil
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_mutable_spec_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local test_id = position.id:gsub(" ", ".")

    local test_prefix = package_name .. junit_test.namespace
    local test_postfix = junit_test.name:gsub("should::", ""):gsub("must::", ""):gsub("::", "."):gsub(" ", ".")

    return vim.startswith(test_id, test_prefix) and vim.endswith(test_id, test_postfix)
end

---@return neotest-scala.Framework
return M
