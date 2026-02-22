local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "zio-test" }

---Detect if this is a ZIO Test spec file
---@param content string
---@return string|nil
function M.detect_style(content)
    if content:match("extends%s+ZIOSpecDefault") or content:match("zio%.test") then
        return "spec"
    end
    return nil
end

---Discover test positions in ZIO Test spec
---@param style string
---@param path string
---@param content string
---@param opts table
---@return neotest.Tree|nil
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
        function: (identifier) @func_name (#any-of? @func_name "test" "suite" "suiteAll")
        arguments: (arguments (string) @test.name))
      )) @test.definition
    ]]
    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = utils.build_position_id,
    })
end

---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    return build.command(root_path, project, tree, name, extra_args)
end

function M.build_test_result(junit_test, position)
    local result = nil
    local error = {}

    local file_name = utils.get_file_name(position.path)

    if junit_test.error_message then
        -- Try to extract line number from error message
        -- Pattern 1: ZIO format with ANSI codes: [36mat /path/File.scala:27 [0m
        local line_num = string.match(junit_test.error_message, "at /.*/" .. file_name .. ":(%d+)")
        -- Pattern 2: Standard stacktrace format: (File.scala:33)
        if not line_num then
            line_num = string.match(junit_test.error_message, "%(" .. file_name .. ":(%d+)%)")
        end

        if line_num then
            error.line = tonumber(line_num) - 1
        end

        error.message = junit_test.error_message
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

function M.match_test(junit_test, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = (package_name .. junit_test.namespace .. "." .. junit_test.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")
    return junit_test_id == test_id
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

    for pos_id in pairs(positions) do
        results[pos_id] = { status = TEST_PASSED }
    end

    local current_failed_id = nil
    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    for i, line in ipairs(lines) do
        local fail_name = line:match("^%s*%- (.+)$")
        if fail_name then
            current_failed_id = nil
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and fail_name:find(pos_name, 1, true) then
                    results[pos_id] = { status = TEST_FAILED, errors = {} }
                    current_failed_id = pos_id
                    break
                end
            end
        end

        local assert_msg = line:match("^%s*✗ (.+)$")
        if assert_msg and current_failed_id then
            local result = results[current_failed_id]
            if result and result.errors then
                table.insert(result.errors, { message = assert_msg })
            end
        end

        local _, line_num = line:match("at ([^:]+):(%d+)")
        if line_num and current_failed_id then
            local result = results[current_failed_id]
            if result and result.errors and #result.errors > 0 and not result.errors[1].line then
                result.errors[1].line = tonumber(line_num)
            end
        end
    end

    return results
end

---@return neotest-scala.Framework
return M
