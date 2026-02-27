local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "munit" }

---@class neotest-scala.MUnitDiscoverOpts
---@field path string
---@field content string

---@class neotest-scala.MUnitBuildCommandOpts
---@field root_path string
---@field project string
---@field tree neotest.Tree
---@field name string|nil
---@field extra_args nil|string|string[]
---@field build_tool? "bloop"|"sbt"

---@param content string
---@return boolean
local function is_funsuite_style(content)
    local supported_suite_patterns = {
        "FunSuite",
        "munit%.FunSuite",
        "CatsEffectSuite",
        "munit%.CatsEffectSuite",
        "ScalaCheckSuite",
        "munit%.ScalaCheckSuite",
        "DisciplineSuite",
        "munit%.DisciplineSuite",
        "ZSuite",
        "munit%.ZSuite",
        "ZIOSuite",
        "munit%.ZIOSuite",
    }

    for _, suite_pattern in ipairs(supported_suite_patterns) do
        if content:match("extends%s+.-" .. suite_pattern .. "%f[%W]") then
            return true
        end
    end

    return false
end

---Discover test positions for munit
---@param opts neotest-scala.MUnitDiscoverOpts
---@return neotest.Tree | nil
function M.discover_positions(opts)
    if not is_funsuite_style(opts.content) then
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
        function: (identifier) @func_name (#any-of? @func_name "test" "property" "testZ")
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
        if #test_suites > 0 then
            local package = utils.get_package_name(tree:data().path)
            if not package then
                return nil
            end
            if #test_suites == 1 then
                return package .. test_suites[1]
            end
            return package .. "*"
        end
    end
    if type == "dir" then
        return "*"
    end
    return nil
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
    return utils.matches_with_interpolation(junit_test_id, test_id)
end

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return neotest.Result|nil
function M.build_test_result(junit_test, position)
    if not match_test(junit_test, position) then
        return nil
    end

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

    local function extract_line_number_from_detail(detail, matched_file)
        local trace_file, trace_line = detail:match("%(([^:]+%.scala):(%d+)%)")
        if trace_file and trace_line then
            if not matched_file or utils.get_file_name(trace_file) == matched_file then
                return tonumber(trace_line) - 1
            end
        end

        local plain_file, plain_line = detail:match("at%s+([^:]+%.scala):(%d+)%s*$")
        if plain_file and plain_line then
            if not matched_file or utils.get_file_name(plain_file) == matched_file then
                return tonumber(plain_line) - 1
            end
        end

        return nil
    end

    local function is_test_result_line(line)
        return line:match("^%s*%+%s+.+%s+%d+%.%d+s$")
            or line:match("^%s*%+%s+.+%s+%d+ms$")
            or line:match("^==>%s+X%s+.+$")
    end

    local function parse_test_path(line)
        local fail_line = line:match("^==>%s+X%s+(.+)$")
        if not fail_line then
            return nil
        end

        local test_path = fail_line:match("^(.+)%s+%d+%.%d+s$")
        if not test_path then
            test_path = fail_line:match("^(.+)%s+%d+ms$")
        end

        return test_path or fail_line
    end

    local function find_matching_positions(test_path)
        local matched = {}
        for pos_id, pos in pairs(positions) do
            local pos_name = utils.get_position_name(pos) or pos.name
            local pos_matches = pos_name and test_path:find(pos_name, 1, true)
            local interpolated_match = pos_name
                and utils.matches_with_interpolation(test_path, pos_name, {
                    anchor_start = false,
                    anchor_end = true,
                })
            if pos_matches or interpolated_match then
                table.insert(matched, { id = pos_id, file = utils.get_file_name(pos.path) })
            end
        end
        return matched
    end

    local index = 1
    while index <= #lines do
        local line = lines[index]
        local pass_name = line:match("^%s*%+%s*(.+)%s+%d+%.%d+s$") or line:match("^%s*%+%s*(.+)%s+%d+ms$")
        if pass_name then
            local matched = find_matching_positions(pass_name)
            for _, pos in ipairs(matched) do
                results[pos.id] = { status = TEST_PASSED }
            end
            index = index + 1
            goto continue
        end

        local test_path = parse_test_path(line)
        if test_path then
            local matched = find_matching_positions(test_path)
            local fail_line_num, fail_msg = line:match("munit%.FailException: [^:]+:(%d+) (.+)$")
            local fallback_message = line:match("^==>%s+X%s+.+%s+([%w%.$]+: .+)$")

            local detail_messages = {}
            local detail_line = nil
            local lookahead = index + 1
            while lookahead <= #lines do
                local detail = lines[lookahead]
                if is_test_result_line(detail) then
                    break
                end

                local trimmed_detail = utils.string_trim(detail)
                if trimmed_detail ~= "" then
                    table.insert(detail_messages, trimmed_detail)
                    if not detail_line then
                        local parsed_line = nil
                        for _, pos in ipairs(matched) do
                            parsed_line = extract_line_number_from_detail(trimmed_detail, pos.file)
                            if parsed_line ~= nil then
                                break
                            end
                        end
                        detail_line = parsed_line
                    end
                end

                lookahead = lookahead + 1
            end

            for _, pos in ipairs(matched) do
                if fail_line_num and fail_msg then
                    results[pos.id] = {
                        status = TEST_FAILED,
                        errors = { { message = fail_msg, line = tonumber(fail_line_num) - 1 } },
                    }
                else
                    local message = table.concat(detail_messages, "\n")
                    if message == "" then
                        message = fallback_message or "munit failure"
                    end
                    results[pos.id] = {
                        status = TEST_FAILED,
                        errors = { { message = message, line = detail_line } },
                    }
                end
            end

            index = lookahead
            goto continue
        end

        index = index + 1
        ::continue::
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
