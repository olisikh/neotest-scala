local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "munit" }

---@class neotest-scala.MUnitDiscoverOpts
---@field style "funsuite"
---@field path string
---@field content string

---@class neotest-scala.MUnitBuildCommandOpts
---@field root_path string
---@field project string
---@field tree neotest.Tree
---@field name string|nil
---@field extra_args nil|string|string[]
---@field build_tool? "bloop"|"sbt"

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
---@param opts neotest-scala.MUnitDiscoverOpts
---@return neotest.Tree | nil
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
    local message = junit_test.error_stacktrace or junit_test.error_message

    if message then
        error.message = message:gsub("/.*/" .. file_name .. ":%d+ ", "")
        error.line = utils.extract_line_number(message, file_name)
    end

    if vim.tbl_isempty(error) then
        result = { status = TEST_PASSED }
    else
        result = { status = TEST_FAILED, errors = { error } }
    end

    return result
end

---@param opts neotest-scala.MUnitBuildCommandOpts
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

    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local function find_line_in_trace(start_idx, file_pattern)
        -- TODO: arbitrary +15 looks hacky
        for j = start_idx, math.min(start_idx + 15, #lines) do
            local trace_line = lines[j] or ""
            local line_num = trace_line:match("%(([^:]+)%.scala:(%d+)%)")

            if line_num and trace_line:find(file_pattern, 1, true) then
                return tonumber(line_num)
            end
        end
        return nil
    end

    for i, line in ipairs(lines) do
        local pass_name = line:match("^%s*%+%s*(.+)%s+%d+%.%d+s$")
        if pass_name then
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and pass_name:find(pos_name, 1, true) then
                    results[pos_id] = { status = TEST_PASSED }
                end
            end
        end

        local fail_line = line:match("^==> X (.+)$")
        if fail_line then
            local test_path = fail_line:match("^(.+)  %d+%.%d+s")
            if test_path then
                for pos_id, pos in pairs(positions) do
                    local pos_name = utils.get_position_name(pos) or pos.name
                    local matched_file = utils.get_file_name(pos.path)
                    if pos_name and test_path:find(pos_name, 1, true) then
                        local line_num, msg = fail_line:match("munit%.FailException: [^:]+:(%d+) (.+)$")
                        if line_num and msg then
                            results[pos_id] = {
                                status = TEST_FAILED,
                                errors = { { message = msg, line = tonumber(line_num) - 1 } },
                            }
                        else
                            local exc = fail_line:match("%s+([%w%.$]+: .+)$")
                            if exc then
                                local trace_line = find_line_in_trace(i + 1, matched_file or "")
                                results[pos_id] = {
                                    status = TEST_FAILED,
                                    errors = { { message = exc, line = trace_line } },
                                }
                            else
                                results[pos_id] = { status = TEST_FAILED, errors = {} }
                            end
                        end
                        break
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
    elseif output:match("initializationError") then
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
