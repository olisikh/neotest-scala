local utils = require("neotest-scala.utils")

---@class neotest-scala.Framework
local M = {}

local function find_parent_file_node(tree)
    local parent = tree:parent()
    if parent ~= nil and parent:data().type ~= "file" then
        return find_parent_file_node(parent)
    else
        return parent
    end
end

local function resolve_test_name(file_node)
    assert(
        file_node:data().type == "file",
        "[neotest-scala]: Tree must be of type 'file', but got: " .. file_node:data().type
    )

    local test_suites = {}
    for _, child in file_node:iter_nodes() do
        if child:data().type == "namespace" then
            table.insert(test_suites, child:data().name)
        end
    end

    if test_suites then
        local package = utils.get_package_name(file_node:data().path)
        if #test_suites == 1 then
            -- run individual spec
            return package .. test_suites[1]
        else
            -- otherwise run tests for whole package
            return package .. "*"
        end
    end
end

local function build_test_namespace(tree)
    local type = tree:data().type

    if type == "file" then
        return resolve_test_name(tree)
    elseif type == "dir" then
        return "*"
    else
        return resolve_test_name(find_parent_file_node(tree))
    end
end

--- Builds a command for running tests for the framework.
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(project, tree, name, extra_args)
    local test_namespace = build_test_namespace(tree)

    local command = nil

    if not test_namespace then
        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    else
        local test_path = ""
        if tree:data().type == "test" then
            test_path = ' -- ex "' .. name .. '"'
        end

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
