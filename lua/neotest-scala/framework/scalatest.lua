local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

-- Builds a test path from the current position in the tree.
---@param tree neotest.Tree
---@return string|nil
local function build_test_namespace(tree, name)
    local parent_tree = tree:parent()
    local type = tree:data().type
    if parent_tree and parent_tree:data().type == "namespace" then
        local package = utils.get_package_name(parent_tree:data().path)
        local parent_name = parent_tree:data().name
        return package .. parent_name
    end
    if parent_tree and parent_tree:data().type == "test" then
        return nil
    end
    if type == "namespace" then
        local package = utils.get_package_name(tree:data().path)
        if not package then
            return nil
        end
        return package .. name
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

--- Builds a command for running tests for the framework.
---@param runner string
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(runner, project, tree, name, extra_args)
    local test_namespace = build_test_namespace(tree, name)

    if runner == "bloop" then
        local full_test_path
        if not test_namespace then
            full_test_path = {}
        elseif tree:data().type ~= "test" then
            full_test_path = { "-o", test_namespace }
        else
            full_test_path = { "-o", test_namespace, "--", "-z", name }
        end
        return vim.tbl_flatten({ "bloop", "test", extra_args, project, full_test_path })
    elseif not test_namespace then
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
    local junit_test_id = junit_test.namespace .. "." .. junit_test.name:gsub(" ", ".")
    local test_id = position.id:gsub(" ", ".")
    return junit_test_id == test_id
end

---@return neotest-scala.Framework
return M
