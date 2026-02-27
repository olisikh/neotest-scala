local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "zio-test" }

---@class neotest-scala.ZioTestDiscoverOpts
---@field path string
---@field content string

---@class neotest-scala.ZioTestBuildCommandOpts
---@field root_path string
---@field project string
---@field tree neotest.Tree
---@field name string|nil
---@field extra_args nil|string|string[]
---@field build_tool? "bloop"|"sbt"

---@param content string
---@return boolean
local function is_spec_style(content)
    if content:match("extends%s+ZIOSpecDefault") or content:match("zio%.test") then
        return true
    end
    return false
end

---Discover test positions in ZIO Test spec
---@param opts neotest-scala.ZioTestDiscoverOpts
---@return neotest.Tree|nil
function M.discover_positions(opts)
    if not is_spec_style(opts.content) then
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
        function: (identifier) @func_name (#any-of? @func_name "test" "suite" "suiteAll")
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

---@param opts { tree: neotest.Tree, position: neotest.Position }
---@return string|nil
function M.build_dap_test_selector(opts)
    local position = opts.position
    if not position then
        return nil
    end

    local test_name = utils.get_position_name(position)
    if not test_name or test_name == "" then
        return nil
    end

    return test_name
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

---@param message string
---@return string
local function strip_test_header_line(message)
    local first_line, rest = message:match("^([^\r\n]*)\r?\n(.*)$")
    if first_line and rest and first_line:match("^%s*%-%s+.+$") then
        return rest
    end

    return message
end

---@param message string
---@return string
local function trim_line_indentation(message)
    local first_line = message:match("^([^\r\n]*)") or ""
    local base_indent = #(first_line:match("^( *)") or "")

    if base_indent == 0 then
        return message
    end

    local lines = {}

    local function remove_base_indent(line)
        local leading_spaces = #(line:match("^( *)") or "")
        local remove_count = math.min(leading_spaces, base_indent)
        return line:sub(remove_count + 1)
    end

    for line in (message .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, remove_base_indent(line))
    end

    return table.concat(lines, "\n")
end

---@param message string
---@return string
local function strip_first_line_location(message)
    local first_line, rest = message:match("^([^\r\n]*)\r?\n(.*)$")
    if not first_line then
        return (message:gsub("%s*%([^:%)]+%.scala:%d+%)%s*$", ""))
    end

    local cleaned_first_line = first_line:gsub("%s*%([^:%)]+%.scala:%d+%)%s*$", "")
    return cleaned_first_line .. "\n" .. rest
end

---@param message string
---@return string
local function sanitize_error_message(message)
    return strip_first_line_location(trim_line_indentation(strip_test_header_line(message)))
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

        error.message = sanitize_error_message(junit_test.error_message)
    elseif junit_test.error_stacktrace then
        error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)
        error.message = sanitize_error_message(junit_test.error_stacktrace)
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

    -- Build position lookup for matching
    local positions = {}
    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            positions[data.id] = data
        end
    end

    ---@param test_name string
    ---@return string[]
    local function find_matching_position_ids(test_name)
        local matched_ids = {}
        for pos_id, pos in pairs(positions) do
            local pos_name = utils.get_position_name(pos) or pos.name
            local normalized_name = pos_name and pos_name:gsub("['\"]", "")
            local pos_matches = normalized_name and test_name:find(normalized_name, 1, true)
            local interpolated_match = normalized_name
                and utils.matches_with_interpolation(test_name, normalized_name, {
                    anchor_start = false,
                    anchor_end = true,
                })
            if pos_matches or interpolated_match then
                table.insert(matched_ids, pos_id)
            end
        end
        return matched_ids
    end

    ---@param pos_id string
    ---@param default_message string
    ---@return neotest.Result
    local function ensure_failed_result(pos_id, default_message)
        local result = results[pos_id]
        if not result or result.status ~= TEST_FAILED then
            result = { status = TEST_FAILED, errors = {} }
            results[pos_id] = result
        elseif not result.errors then
            result.errors = {}
        end

        if #result.errors == 0 then
            table.insert(result.errors, { message = default_message, line = nil })
        end

        return result
    end

    local current_failed_ids = nil

    -- Detect compilation or bootstrapping failures
    local global_failure = nil
    if output:match("Failed to compile") then
        global_failure = "Compilation failed"
    elseif output:match("Test suite aborted") or output:match("Failed to initialize") then
        global_failure = "Test suite aborted"
    elseif output:match("SuiteSelector") or output:match("initializationError") then
        global_failure = "Suite initialization failed"
    end

    for line in output:gmatch("[^\r\n]+") do
        local pass_name = line:match("^%s*%+%s*(.+)$")
        if pass_name then
            local matched_ids = find_matching_position_ids(pass_name)
            for _, pos_id in ipairs(matched_ids) do
                results[pos_id] = { status = TEST_PASSED }
            end
            current_failed_ids = nil
        end

        local fail_name = line:match("^%s*%-%s*(.+)$")
        if fail_name then
            local matched_ids = find_matching_position_ids(fail_name)
            for _, pos_id in ipairs(matched_ids) do
                ensure_failed_result(pos_id, "Test failed")
            end
            current_failed_ids = #matched_ids > 0 and matched_ids or nil
        end

        local assertion_message = line:match("^%s*✗%s*(.+)$")
        if assertion_message and current_failed_ids then
            for _, pos_id in ipairs(current_failed_ids) do
                local result = ensure_failed_result(pos_id, assertion_message)
                result.errors[1].message = assertion_message
            end
        end

        local throwable_type, throwable_message = line:match("^%s*([%w%._$]+):%s*(.*)$")
        if
            throwable_type
            and current_failed_ids
            and (throwable_type:match("Exception$") or throwable_type:match("Error$"))
        then
            local message = throwable_type .. (throwable_message ~= "" and ": " .. throwable_message or "")
            for _, pos_id in ipairs(current_failed_ids) do
                local result = ensure_failed_result(pos_id, message)
                result.errors[1].message = message
            end
        end

        local _, line_num_str = line:match("at ([^:]+%.scala):(%d+)%s*$")
        if not line_num_str then
            _, line_num_str = line:match("%(([^:]+%.scala):(%d+)%)")
        end

        if line_num_str and current_failed_ids then
            local line_num = tonumber(line_num_str) - 1
            for _, pos_id in ipairs(current_failed_ids) do
                local result = ensure_failed_result(pos_id, "Test failed")
                result.errors[1].line = line_num
            end
        end
    end

    local default_status = TEST_PASSED
    local default_error = nil
    if global_failure then
        default_status = TEST_FAILED
        default_error = { message = global_failure }
    end

    for pos_id in pairs(positions) do
        if not results[pos_id] then
            if default_error then
                results[pos_id] = { status = default_status, errors = { default_error } }
            else
                results[pos_id] = { status = default_status }
            end
        end
    end

    return results
end

---@return neotest-scala.Framework
return M
