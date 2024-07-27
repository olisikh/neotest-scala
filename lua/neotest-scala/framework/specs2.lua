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

    local command = nil

    if not test_namespace then
        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    else
        local test_path = ""
        -- TODO: for some reason specs2 single test selection is not working properly when test contains brackets
        -- or when it is a grouping of other tests, so have to run entire spec
        -- if tree:data().type == "test" then
        --     test_path = ' -- ex "' .. name .. '"'
        -- end

        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
    end

    return command
end

-- Get test results from the test output.
---@param junit_test table<string, string>
---@param position neotest.Position
---@return string|nil
function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local test_id = position.id:gsub(" ", ".")

    local test_prefix = package_name .. junit_test.namespace
    local test_postfix = junit_test.name:gsub("should::", ""):gsub("must::", ""):gsub("::", "."):gsub(" ", ".")

    return vim.startswith(test_id, test_prefix) and vim.endswith(test_id, test_postfix)
end

---@return neotest-scala.Framework
return M
