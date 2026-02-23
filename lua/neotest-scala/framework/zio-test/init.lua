local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "zio-test" }

---@class neotest-scala.ZioTestDiscoverOpts
---@field style "spec"
---@field path string
---@field content string

---@class neotest-scala.ZioTestBuildCommandOpts
---@field root_path string
---@field project string
---@field tree neotest.Tree
---@field name string|nil
---@field extra_args nil|string|string[]
---@field build_tool? "bloop"|"sbt"

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
---@param opts neotest-scala.ZioTestDiscoverOpts
---@return neotest.Tree|nil
function M.discover_positions(opts)
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

---@param opts neotest-scala.ZioTestBuildCommandOpts
---@return string[]
function M.build_command(opts)
    return build.command({
        root_path = opts.root_path,
        project = opts.project,
        tree = opts.tree,
        name = opts.name,
        extra_args = opts.extra_args,
        tool_override = opts.build_tool,
    })
end

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return table
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
        error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)
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

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return boolean
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

    -- Build position lookup by file name
    local positions_by_file = {}
    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            local file_name = utils.get_file_name(data.path)
            if not positions_by_file[file_name] then
                positions_by_file[file_name] = {}
            end
            table.insert(positions_by_file[file_name], {
                id = data.id,
                range = data.range,
            })
        end
    end

    -- Find the most specific (narrowest) position containing a JVM line number
    local function find_position_for_line(file_name, jvm_line_num)
        local positions = positions_by_file[file_name]
        if not positions then
            return nil
        end

        local line_0idx = jvm_line_num - 1
        local best_match = nil
        local best_span = math.huge

        for _, pos in ipairs(positions) do
            if pos.range then
                if pos.range[1] <= line_0idx and line_0idx <= pos.range[3] then
                    local span = pos.range[3] - pos.range[1]
                    if span < best_span then
                        best_match = pos
                        best_span = span
                    end
                end
            end
        end
        return best_match
    end

    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local failed_ids = {}

    -- Detect compilation or bootstrapping failures
    local global_failure = nil
    if output:match("Failed to compile") then
        global_failure = "Compilation failed"
    elseif output:match("Test suite aborted") or output:match("Failed to initialize") then
        global_failure = "Test suite aborted"
    elseif output:match("SuiteSelector") or output:match("initializationError") then
        global_failure = "Suite initialization failed"
    end

    for i, line in ipairs(lines) do
        -- Pattern 1: "at /full/path/File.scala:22" (assertion failures)
        local full_path, line_num_str = line:match("at ([^:]+%.scala):(%d+)%s*$")

        -- Pattern 2: "at pkg.Class(File.scala:33)" (stack traces)
        if not full_path then
            full_path, line_num_str = line:match("%(([^:]+%.scala):(%d+)%)")
        end

        if full_path and line_num_str then
            local file_name = utils.get_file_name(full_path)
            local line_num = tonumber(line_num_str)
            local pos = find_position_for_line(file_name, line_num)

            if pos and not failed_ids[pos.id] then
                -- Look backwards for error message
                local err_msg = "Test failed"
                for j = i - 1, math.max(1, i - 10), -1 do
                    local prev = lines[j]
                    -- Assertion message: "✗ message"
                    local msg = prev:match("^%s*✗ (.+)$")
                    if msg then
                        err_msg = msg
                        break
                    end
                    -- Exception message: "...Exception: message"
                    local exc = prev:match("Exception[^:]*:%s*(.+)$")
                    if exc then
                        err_msg = exc
                        break
                    end
                end

                results[pos.id] = {
                    status = TEST_FAILED,
                    errors = { { message = err_msg, line = line_num - 1 } }, -- 0-indexed for neotest
                }
                failed_ids[pos.id] = true
            end
        end
    end

    local default_status = TEST_PASSED
    local default_error = nil
    if global_failure then
        default_status = TEST_FAILED
        default_error = { message = global_failure }
    end

    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" and not results[data.id] then
            if default_error then
                results[data.id] = { status = default_status, errors = { default_error } }
            else
                results[data.id] = { status = default_status }
            end
        end
    end

    return results
end

---@return neotest-scala.Framework
return M
