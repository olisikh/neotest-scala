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
            test_path = ' -- -t "' .. name .. '"'
        end

        command = vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly " .. test_namespace .. test_path })
    end

    return command
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
