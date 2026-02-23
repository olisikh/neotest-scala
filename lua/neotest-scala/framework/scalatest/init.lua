local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "scalatest" }

---Detect ScalaTest style from file content
---@param content string
---@return "funsuite" | "freespec" | nil
function M.detect_style(content)
    if content:match("extends%s+AnyFunSuite") or content:match("extends%s+.*FunSuite") then
        return "funsuite"
    elseif content:match("extends%s+AnyFreeSpec") or content:match("extends%s+.*FreeSpec") then
        return "freespec"
    end
    return nil
end

---Discover test positions for ScalaTest
---@param opts table
---@return neotest.Tree | nil
function M.discover_positions(opts)
    local style = opts.style
    path = opts.path
    local query
    if style == "funsuite" then
        query = [[
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
    else
        -- FreeSpec: "name" - { } and "name" in { }
        query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (infix_expression
        left: (string) @test.name
        operator: (_) @spec_init (#any-of? @spec_init "-" "in")
        right: (_)
      ) @test.definition
    ]]
    end

    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = utils.build_position_id,
    })
end

---Build the full test path for FreeSpec-style tests by traversing up the tree
---and collecting parent namespace names (contexts marked with "-" operator)
---@param tree neotest.Tree
---@param name string The test name
---@return string The full test path with parent contexts
local function build_freespec_test_path(tree, name)
    -- If tree doesn't have :parent() method (e.g., in tests), return name unchanged
    if type(tree.parent) ~= "function" then
        return name
    end

    local parts = { name }
    local current = tree:parent()

    -- Traverse up the tree collecting parent test/namespace names
    while current do
        local data = current:data()
        -- Only include parents that are tests (FreeSpec contexts are captured as tests)
        if data.type == "test" then
            local parent_name = utils.get_position_name(data)
            if parent_name and parent_name ~= "" then
                table.insert(parts, 1, parent_name)
            end
        end
        current = current:parent()
    end

    return table.concat(parts, " ")
end

--- Builds a command for running tests for the framework.
---@param opts table
---@return string[]
function M.build_command(opts)
    local root_path = opts.root_path
    project = opts.project
    tree = opts.tree
    name = opts.name
    extra_args = opts.extra_args
    build_tool = opts.build_tool
    local tree_type = nil
    if type(tree.data) == "function" then
        tree_type = tree:data().type
    elseif type(tree.data) == "table" then
        tree_type = tree.data.type
    end

    local junit_args = {}
    if build.resolve_tool(root_path, build_tool) == "bloop" then
        junit_args = {
            "--args",
            "-u",
            "--args",
            root_path .. "/" .. project .. "/target/test-reports",
        }
    end

    local merged_args = build.merge_args(junit_args, extra_args)

    if tree_type == "test" then
        local full_test_name = build_freespec_test_path(tree, name)
        return build.command({
            root_path = root_path,
            project = project,
            tree = tree,
            name = full_test_name,
            extra_args = merged_args,
            tool_override = build_tool,
        })
    end

    return build.command({
        root_path = root_path,
        project = project,
        tree = tree,
        name = name,
        extra_args = merged_args,
        tool_override = build_tool,
    })
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    -- JUnit test names have leading/trailing spaces that need to be trimmed
    local junit_name = vim.trim(junit_test.name)
    local position_id = position.id

    -- Normalize: remove dashes and spaces for comparison
    local normalized_position = position_id:gsub("-", "."):gsub(" ", "")

    -- Try 1: Standard matching with package prefix (for regular tests)
    local junit_with_package = (package_name .. junit_test.namespace .. "." .. junit_name):gsub("-", "."):gsub(" ", "")
    if junit_with_package == normalized_position then
        return true
    end

    -- Try 2: Without package prefix (for FreeSpec where JUnit namespace is just class name)
    local junit_test_id = (junit_test.namespace .. "." .. junit_name):gsub("-", "."):gsub(" ", "")
    if junit_test_id == normalized_position then
        return true
    end

    -- Try 3: For FreeSpec, check if JUnit test ID matches the END of position (after removing package)
    -- FreeSpec JUnit: namespace="FreeSpec", name="Hello, ScalaTest!" -> "FreeSpec.Hello,ScalaTest!"
    -- Position: "com.example.FreeSpec.FreeSpec.Hello,ScalaTest!" -> "FreeSpec.FreeSpec.Hello,ScalaTest!"
    local escaped_package = package_name:gsub("%.", "%%.")
    local position_no_package = normalized_position:gsub("^" .. escaped_package, "")
    if position_no_package:find(junit_test_id .. "$") then
        return true
    end

    -- Try 4: Remove all dots and compare (fallback for edge cases)
    local junit_no_dots = junit_test_id:gsub("%.", "")
    local position_no_dots = position_no_package:gsub("%.", "")
    return junit_no_dots == position_no_dots
end

---Build test result with diagnostic message for failed tests
---@param junit_test table<string, string>
---@param position neotest.Position
---@return table
function M.build_test_result(junit_test, position)
    local result = {}
    local error = {}

    local file_name = utils.get_file_name(position.path)

    if junit_test.error_message then
        error.message = junit_test.error_message

        if junit_test.error_stacktrace then
            error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)
        end
    elseif junit_test.error_stacktrace then
        error.message = junit_test.error_stacktrace:match("^[^\r\n]+") or junit_test.error_stacktrace
        error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)
    end

    if error.message then
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

function M.build_namespace(ns_node, report_prefix, node)
    local data = ns_node:data()
    local path = data.path
    local id = data.id
    local package_name = utils.get_package_name(path)

    local namespace = {
        path = path,
        namespace = id,
        report_path = report_prefix .. "TEST-" .. package_name .. id .. ".xml",
        tests = {},
    }

    for _, n in node:iter_nodes() do
        table.insert(namespace.tests, n)
    end

    return namespace
end

---@return neotest-scala.Framework
return M
