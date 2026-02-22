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
---@param style "funsuite" | "freespec"
---@param path string
---@param content string
---@param opts table
---@return neotest.Tree | nil
function M.discover_positions(style, path, content, opts)
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
---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    -- For individual tests, build the full test path (needed for FreeSpec)
    -- Check if tree is a proper tree object (has :data() method) or a plain table
    local tree_type = nil
    if type(tree.data) == "function" then
        tree_type = tree:data().type
    elseif type(tree.data) == "table" then
        tree_type = tree.data.type
    end

    if tree_type == "test" then
        local full_test_name = build_freespec_test_path(tree, name)
        return build.command(root_path, project, tree, full_test_name, extra_args)
    end

    return build.command(root_path, project, tree, name, extra_args)
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

---Extract the highest line number for the given file from stacktrace
---ScalaTest stacktraces have multiple file references (class def, test method, etc.)
---We want the highest line number which corresponds to the actual test assertion
---@param stacktrace string
---@param file_name string
---@return number|nil
local function extract_line_number(stacktrace, file_name)
    local max_line_num = nil
    local pattern = "%(" .. file_name .. ":(%d+)%)"

    for line_num_str in string.gmatch(stacktrace, pattern) do
        local line_num = tonumber(line_num_str)
        if not max_line_num or line_num > max_line_num then
            max_line_num = line_num
        end
    end

    return max_line_num and (max_line_num - 1) or nil
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
            error.line = extract_line_number(junit_test.error_stacktrace, file_name)
        end
    elseif junit_test.error_stacktrace then
        local lines = vim.split(junit_test.error_stacktrace, "\n")
        error.message = lines[1]

        error.line = extract_line_number(junit_test.error_stacktrace, file_name)
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

--- Parse bloop stdout output for test results
---@param output string The raw stdout from bloop test
---@param tree neotest.Tree The test tree for matching
---@return table<string, neotest.Result> Test results indexed by position.id
function M.parse_stdout_results(output, tree)
    local results = {}

    output = utils.string_remove_ansi(output)

    local positions = {}
    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            positions[data.id] = data
        end
    end

    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local function find_line_in_trace(start_idx, file_pattern)
        for j = start_idx, math.min(start_idx + 15, #lines) do
            local trace_line = lines[j] or ""
            local line_num = trace_line:match("%(([^:]+)%.scala:(%d+)%)")
            if line_num and trace_line:find(file_pattern, 1, true) then
                return tonumber(line_num)
            end
        end
        return nil
    end

    local function get_indent(s)
        return #s:match("^(%s*)")
    end

    for i, line in ipairs(lines) do
        local indent, fail_name = line:match("^(%s*)%- (.+) %*%*%* FAILED %*%*%*$")
        if fail_name then
            local matched_pos_id = nil
            local matched_file = nil
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and fail_name:find(pos_name:gsub("['\"]", ""), 1, true) then
                    results[pos_id] = { status = TEST_FAILED, errors = {} }
                    matched_pos_id = pos_id
                    matched_file = utils.get_file_name(pos.path)
                    break
                end
            end

            if matched_pos_id then
                local fail_indent = get_indent(indent)
                local next_line = lines[i + 1] or ""
                local next_indent = get_indent(next_line)

                if next_indent > fail_indent then
                    local err_msg, file, line_num = next_line:match("^%s+(.+) %(([^:]+%.scala):(%d+)%)$")
                    if err_msg and line_num then
                        local result = results[matched_pos_id]
                        if result and result.errors then
                            table.insert(result.errors, { message = err_msg, line = tonumber(line_num) })
                        end
                    else
                        local exc_msg = next_line:match("^%s+(.+)$")
                        if exc_msg and #exc_msg > 0 and exc_msg ~= "..." then
                            local result = results[matched_pos_id]
                            if result and result.errors then
                                local trace_line = find_line_in_trace(i + 2, matched_file or "")
                                table.insert(result.errors, { message = exc_msg, line = trace_line })
                            end
                        end
                    end
                end
            end
        end

        local pass_name = line:match("^%s*%- (.+)$")
        if pass_name and not line:find("%*%*%* FAILED %*%*%*") then
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and pass_name:find(pos_name:gsub("['\"]", ""), 1, true) then
                    if not results[pos_id] then
                        results[pos_id] = { status = TEST_PASSED }
                    end
                end
            end
        end
    end

    for pos_id in pairs(positions) do
        if not results[pos_id] then
            results[pos_id] = { status = TEST_PASSED }
        end
    end

    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    for i, line in ipairs(lines) do
        -- Fail: "  - test name *** FAILED ***" (any indentation level)
        local indent, fail_name = line:match("^(%s*)%- (.+) %*%*%* FAILED %*%*%*$")
        if fail_name then
            local matched_pos_id = nil
            local matched_file = nil
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and fail_name:find(pos_name:gsub("['\"]", ""), 1, true) then
                    results[pos_id] = { status = TEST_FAILED, errors = {} }
                    matched_pos_id = pos_id
                    matched_file = utils.get_file_name(pos.path)
                    break
                end
            end

            if matched_pos_id then
                local fail_indent = get_indent(indent)
                local next_line = lines[i + 1] or ""
                local next_indent = get_indent(next_line)

                if next_indent > fail_indent then
                    -- Assertion with location: "    1 did not equal 2 (File.scala:12)"
                    local err_msg, file, line_num = next_line:match("^%s+(.+) %(([^:]+%.scala):(%d+)%)$")
                    if err_msg and line_num then
                        local result = results[matched_pos_id]
                        if result and result.errors then
                            table.insert(result.errors, { message = err_msg, line = tonumber(line_num) - 1 })
                        end
                    else
                        -- Exception message: "    some.package.ExceptionType: message"
                        local exc_msg = next_line:match("^%s+(.+)$")
                        if exc_msg and #exc_msg > 0 then
                            local result = results[matched_pos_id]
                            if result and result.errors then
                                local trace_line = find_line_in_trace(i + 2, matched_file or "")
                                table.insert(result.errors, {
                                    message = exc_msg,
                                    line = trace_line and (trace_line - 1) or nil,
                                })
                            end
                        end
                    end
                end
            end
        end

        -- Pass: "- test name" (no FAILED marker, any indentation)
        local pass_name = line:match("^%s*%- (.+)$")
        if pass_name and not line:find("%*%*%* FAILED %*%*%*") then
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and pass_name:find(pos_name:gsub("['\"]", ""), 1, true) then
                    if not results[pos_id] then
                        results[pos_id] = { status = TEST_PASSED }
                    end
                end
            end
        end
    end

    local global_failure = nil
    if output:match("Failed to compile") then
        global_failure = "Compilation failed"
    elseif output:match("Test suite aborted") or output:match("Failed to initialize") then
        global_failure = "Test suite aborted"
    elseif output:match("SuiteSelector") then
        global_failure = "Suite initialization failed"
    end

    for pos_id in pairs(positions) do
        if not results[pos_id] then
            if global_failure then
                results[pos_id] = { status = TEST_FAILED, errors = { { message = global_failure } } }
            else
                results[pos_id] = { status = TEST_PASSED }
            end
        end
    end

    return results
end

---@return neotest-scala.Framework
return M
