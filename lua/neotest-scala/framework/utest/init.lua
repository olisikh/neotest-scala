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
    }

    for _, n in node:iter_nodes() do
        table.insert(namespace.tests, n)
    end

    return namespace
end

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return boolean
local function match_test(junit_test, position)
    if not (position and position.id and junit_test and junit_test.name and junit_test.namespace) then
        return true
    end

    local package_name = utils.get_package_name(position.path)
    local junit_test_id = (package_name .. junit_test.namespace .. "." .. junit_test.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")
    return junit_test_id == test_id
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

---@param opts { position: neotest.Position, test_node: neotest.Tree, junit_results: neotest-scala.JUnitTest[] }
---@return neotest.Result|nil
function M.build_position_result(opts)
    local position = opts.position
    local test_node = opts.test_node
    local junit_results = opts.junit_results

    for _, junit_test in ipairs(junit_results) do
        local result = M.build_test_result(junit_test, position)
        if result then
            return result
        end
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
    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            positions[data.id] = data
        end
    end

    local current_failure_id = nil

    for line in output:gmatch("[^\r\n]+") do
        -- Result: "+ path time" or "X path time"
        -- Path is like "com.example.UtestTestSuite.test name"
        local status_char, test_path = line:match("^([%+X])%s+(.+)%s+%d+ms")
        if test_path then
            local is_pass = status_char == "+"
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and test_path:find(pos_name, 1, true) then
                    if is_pass then
                        results[pos_id] = { status = TEST_PASSED }
                    else
                        results[pos_id] = { status = TEST_FAILED, errors = {} }
                        current_failure_id = pos_id
                    end
                end
            end
        end

        -- Stack frame: "Class.method(File.scala:line)"
        local file, line_num = line:match("%(([^:]+%.scala):(%d+)%)")
        if file and line_num and current_failure_id then
            local result = results[current_failure_id]
            if result and result.errors and #result.errors == 0 then
                table.insert(result.errors, { line = tonumber(line_num) - 1, message = "Test failed" })
            end
        end

        -- Exception: "java.lang.Exception: message"
        local exc, msg = line:match("(%S+Exception):%s*(.*)")
        if exc and current_failure_id then
            local result = results[current_failure_id]
            if result and result.errors and #result.errors > 0 then
                result.errors[1].message = exc .. (msg ~= "" and ": " .. msg or "")
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
