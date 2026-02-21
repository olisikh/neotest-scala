local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = {}

---Detect munit style from file content
---@param content string
---@return "funsuite" | nil
function M.detect_style(content)
    if content:match("extends%s+FunSuite") or content:match("extends%s+munit%.FunSuite") then
        return "funsuite"
    end
    return nil
end

---Discover test positions for munit
---@param style "funsuite"
---@param path string
---@param content string
---@param opts table
---@return neotest.Tree | nil
function M.discover_positions(style, path, content, opts)
    local query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ((call_expression
        function: (call_expression
        function: (identifier) @func_name (#eq? @func_name "test")
        arguments: (arguments (string) @test.name))
      )) @test.definition
    ]]
    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = utils.build_position_id,
    })
end

local function build_test_path(tree, name)
    local parent_tree = tree:parent()
    local type = tree:data().type
    if parent_tree and parent_tree:data().type == "namespace" then
        local package = utils.get_package_name(parent_tree:data().path)
        local parent_name = parent_tree:data().name
        return package .. parent_name .. "." .. name
    end
    if parent_tree and parent_tree:data().type == "test" then
        local parent_pos = parent_tree:data()
        return build_test_path(parent_tree, utils.get_position_name(parent_pos)) .. "." .. name
    end
    if type == "namespace" then
        local package = utils.get_package_name(tree:data().path)
        if not package then
            return nil
        end
        return package .. name .. ".*"
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

function M.build_test_result(junit_test, position)
    local result = nil
    local error = {}

    local file_name = utils.get_file_name(position.path)
    local raw_message = junit_test.error_stacktrace or junit_test.error_message

    if raw_message then
        error.message = raw_message:gsub("/.*/" .. file_name .. ":%d+ ", "")

        local line_num = string.match(raw_message, "%(" .. file_name .. ":(%d+)%)")
        if line_num then
            error.line = tonumber(line_num) - 1
        end
    end

    if vim.tbl_isempty(error) then
        result = { status = TEST_PASSED }
    else
        result = { status = TEST_FAILED, errors = { error } }
    end

    return result
end

---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    local test_path = build_test_path(tree, name)
    return build.command_with_path(root_path, project, test_path, extra_args)
end

---@return neotest-scala.Framework
return M
