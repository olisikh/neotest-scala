local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "utest" }

---@class neotest-scala.UTestDiscoverOpts
---@field path string
---@field content string

---@class neotest-scala.UTestBuildCommandOpts
---@field root_path string
---@field project string
---@field tree neotest.Tree
---@field name string|nil
---@field extra_args nil|string|string[]
---@field build_tool? "bloop"|"sbt"

---@param content string
---@return boolean
local function is_suite_style(content)
    if content:match("extends%s+TestSuite") or content:match("utest") then
        return true
    end
    return false
end

---Discover test positions for utest
---@param opts neotest-scala.UTestDiscoverOpts
---@return neotest.Tree | nil
function M.discover_positions(opts)
    if not is_suite_style(opts.content) then
        return nil
    end

    local path = opts.path
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
        arguments: (arguments
          [
            (string)
            (interpolated_string_expression)
          ] @test.name))
      )) @test.definition
    ]]
    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = utils.build_position_id,
    })
end

local function build_test_path(tree, name)
    if name and utils.is_interpolated_string(name) then
        return nil
    end

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
            return package .. "{" .. table.concat(test_suites, ",") .. "}"
        end
    end
    if type == "dir" then
        local packages = {}
        local visited = {}
        for _, child in tree:iter_nodes() do
            if child:data().type == "namespace" then
                local package = utils.get_package_name(child:data().path)
                if package and not visited[package] then
                    table.insert(packages, package:sub(1, -2))
                    visited[package] = true
                end
            end
        end
        if packages then
            return "{" .. table.concat(packages, ",") .. "}"
        end
    end
    return nil
end

---@param tree neotest.Tree
---@return string|nil
local function build_namespace_path_for_test(tree)
    local namespace_tree = utils.find_node(tree, "namespace", false)
    if not namespace_tree then
        return nil
    end

    local namespace_data = namespace_tree:data()
    local package = utils.get_package_name(namespace_data.path)
    if not package then
        return nil
    end

    return package .. namespace_data.name
end

---@param opts neotest-scala.UTestBuildCommandOpts
---@return string[]
function M.build_command(opts)
    local root_path = opts.root_path
    local project = opts.project
    local tree = opts.tree
    local name = opts.name
    local extra_args = opts.extra_args
    local build_tool = opts.build_tool
    local test_path = build_test_path(tree, name)

    if not test_path and tree:data().type == "test" then
        test_path = build_namespace_path_for_test(tree)
    end

    return build.command_with_path({
        root_path = root_path,
        project = project,
        test_path = test_path,
        extra_args = extra_args,
        tool_override = build_tool,
    })
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
        all_tests = {},
    }

    for _, n in node:iter_nodes() do
        table.insert(namespace.tests, n)
    end

    for _, n in ns_node:iter_nodes() do
        table.insert(namespace.all_tests, n)
    end

    return namespace
end

---@param namespace table|nil
---@return neotest.Position[]
local function get_ordered_namespace_tests(namespace)
    if not namespace then
        return {}
    end

    if namespace._ordered_utest_tests then
        return namespace._ordered_utest_tests
    end

    local ordered_tests = {}
    local source_tests = namespace.all_tests or namespace.tests or {}
    for _, n in ipairs(source_tests) do
        local position = n and n.data and n:data() or n
        if position and position.type == "test" then
            table.insert(ordered_tests, position)
        end
    end

    table.sort(ordered_tests, function(left, right)
        local left_start = left.range and left.range[1] or math.huge
        local right_start = right.range and right.range[1] or math.huge

        if left_start ~= right_start then
            return left_start < right_start
        end

        local left_col = left.range and left.range[2] or 0
        local right_col = right.range and right.range[2] or 0
        if left_col ~= right_col then
            return left_col < right_col
        end

        return (left.id or "") < (right.id or "")
    end)

    namespace._ordered_utest_tests = ordered_tests
    return ordered_tests
end

---@param namespace table|nil
---@param junit_test neotest-scala.JUnitTest
---@return string|nil
local function get_numeric_junit_target_id(namespace, junit_test)
    if not namespace or not junit_test or not junit_test.name then
        return nil
    end

    local numeric_index = tonumber(junit_test.name)
    if not numeric_index then
        return nil
    end

    local ordered_tests = get_ordered_namespace_tests(namespace)
    local target_position = ordered_tests[numeric_index + 1]
    if not target_position then
        return nil
    end

    return target_position.id
end

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return boolean
local function match_test(junit_test, position)
    if not (position and position.id and junit_test and junit_test.name and junit_test.namespace) then
        return true
    end

    local package_name = utils.get_package_name(position.path) or ""
    local junit_test_id = (package_name .. junit_test.namespace .. "." .. junit_test.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")
    return utils.matches_with_interpolation(junit_test_id, test_id)
end

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return neotest.Result|nil
function M.build_test_result(junit_test, position)
    if not match_test(junit_test, position) then
        return nil
    end

    local error_message = junit_test.error_message or junit_test.error_stacktrace
    if error_message then
        local error = { message = error_message }
        local file_name = utils.get_file_name(position.path)

        error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)

        return {
            errors = { error },
            status = TEST_FAILED,
        }
    end

    return {
        status = TEST_PASSED,
    }
end

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return neotest.Result
local function build_test_result_unchecked(junit_test, position)
    local error_message = junit_test.error_message or junit_test.error_stacktrace
    if error_message then
        local error = { message = error_message }
        local file_name = utils.get_file_name(position.path)

        error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)

        return {
            errors = { error },
            status = TEST_FAILED,
        }
    end

    return {
        status = TEST_PASSED,
    }
end

---@param opts { position: neotest.Position, test_node: neotest.Tree, junit_results: neotest-scala.JUnitTest[] }
---@return neotest.Result|nil
function M.build_position_result(opts)
    local position = opts.position
    local test_node = opts.test_node
    local junit_results = opts.junit_results
    local namespace = opts.namespace

    for index, junit_test in ipairs(junit_results) do
        if utils.is_junit_result_claimed(namespace, index) then
            goto continue
        end

        local numeric_target_id = get_numeric_junit_target_id(namespace, junit_test)
        if numeric_target_id then
            if numeric_target_id == position.id then
                utils.claim_junit_result(namespace, index)
                return build_test_result_unchecked(junit_test, position)
            end
            goto continue
        end

        local result = M.build_test_result(junit_test, position)
        if result then
            utils.claim_junit_result(namespace, index)
            return result
        end

        ::continue::
    end

    local test_status = utils.has_nested_tests(test_node) and TEST_PASSED or TEST_FAILED
    return { status = test_status }
end

--- Parse bloop stdout output for test results
---@param output string The raw stdout from bloop test
---@param tree neotest.Tree The test tree for matching
---@return table<string, neotest.Result> Test results indexed by position.id
function M.parse_stdout_results(output, tree)
    local results = {}

    -- Strip ANSI codes first
    output = utils.string_remove_ansi(output)

    -- Build position lookup for matching
    local positions = {}
    local positions_by_namespace = {}
    local function add_namespace_position(namespace_key, position)
        if not namespace_key then
            return
        end
        positions_by_namespace[namespace_key] = positions_by_namespace[namespace_key] or {}
        table.insert(positions_by_namespace[namespace_key], position)
    end

    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            positions[data.id] = data

            local namespace_node = utils.find_node(node, "namespace", false)
            if namespace_node then
                local namespace_data = namespace_node:data()
                local namespace_id = namespace_data.id
                add_namespace_position(namespace_id, data)

                local package_name = utils.get_package_name(namespace_data.path)
                if package_name then
                    add_namespace_position(package_name .. namespace_id, data)
                end
            end
        end
    end

    for _, namespace_positions in pairs(positions_by_namespace) do
        table.sort(namespace_positions, function(left, right)
            local left_start = left.range and left.range[1] or math.huge
            local right_start = right.range and right.range[1] or math.huge

            if left_start ~= right_start then
                return left_start < right_start
            end

            local left_col = left.range and left.range[2] or 0
            local right_col = right.range and right.range[2] or 0
            if left_col ~= right_col then
                return left_col < right_col
            end

            return (left.id or "") < (right.id or "")
        end)
    end

    local current_failure_ids = {}

    ---@param pos_id string
    ---@param default_message string
    ---@return neotest.Result|nil, neotest.Error|nil
    local function ensure_failure_error(pos_id, default_message)
        local result = results[pos_id]
        if not result then
            return nil, nil
        end

        result.errors = result.errors or {}
        if #result.errors == 0 then
            table.insert(result.errors, { message = default_message })
        end

        return result, result.errors[1]
    end

    ---@param test_path string
    ---@return string[]
    local function find_matching_position_ids(test_path)
        local matches = {}

        for pos_id, pos in pairs(positions) do
            local pos_name = utils.get_position_name(pos) or pos.name
            local pos_matches = pos_name and test_path:find(pos_name, 1, true)
            local interpolated_match = pos_name
                and utils.matches_with_interpolation(test_path, pos_name, {
                    anchor_start = false,
                    anchor_end = true,
                })
            if pos_matches or interpolated_match then
                table.insert(matches, pos_id)
            end
        end

        if #matches > 0 then
            return matches
        end

        local namespace_id, numeric_index_str = test_path:match("^(.*)%.(%d+)$")
        local numeric_index = tonumber(numeric_index_str or "")
        if namespace_id and numeric_index ~= nil then
            local namespace_positions = positions_by_namespace[namespace_id]
            local target = namespace_positions and namespace_positions[numeric_index + 1] or nil
            if target then
                return { target.id }
            end
        end

        return {}
    end

    for line in output:gmatch("[^\r\n]+") do
        -- Result: "+ path time" or "X path time"
        -- Path is like "com.example.UtestTestSuite.test name"
        local status_char, test_path = line:match("^([%+X])%s+(.+)%s+%d+ms")
        if test_path then
            local is_pass = status_char == "+"
            local matched_ids = find_matching_position_ids(test_path)
            current_failure_ids = {}

            for _, pos_id in ipairs(matched_ids) do
                if is_pass then
                    results[pos_id] = { status = TEST_PASSED }
                else
                    results[pos_id] = { status = TEST_FAILED, errors = {} }
                    table.insert(current_failure_ids, pos_id)
                end
            end
        end

        -- Stack frame: "Class.method(File.scala:line)"
        local file, line_num = line:match("%(([^:]+%.scala):(%d+)%)")
        if file and line_num and #current_failure_ids > 0 then
            local zero_indexed_line = tonumber(line_num) - 1
            for _, pos_id in ipairs(current_failure_ids) do
                local _, err = ensure_failure_error(pos_id, "Test failed")
                if err then
                    err.line = zero_indexed_line
                end
            end
        end

        -- Exception/Error: "java.lang.Exception: message" or "java.lang.AssertionError: message"
        local throwable_type, throwable_message = line:match("^%s*([%w%._$]+):%s*(.*)$")
        if
            throwable_type
            and #current_failure_ids > 0
            and (throwable_type:match("Exception$") or throwable_type:match("Error$"))
        then
            local message = throwable_type .. (throwable_message ~= "" and ": " .. throwable_message or "")
            for _, pos_id in ipairs(current_failure_ids) do
                local _, err = ensure_failure_error(pos_id, message)
                if err then
                    err.message = message
                end
            end
        end
    end

    local global_failure = nil
    if output:match("Failed to compile") then
        global_failure = "Compilation failed"
    elseif output:match("Test suite aborted") or output:match("Failed to initialize") then
        global_failure = "Test suite aborted"
    elseif output:match("SuiteSelector") or output:match("initializationError") then
        global_failure = "Suite initialization failed"
    elseif output:match("No test suites were run") then
        global_failure = "No tests were run"
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
