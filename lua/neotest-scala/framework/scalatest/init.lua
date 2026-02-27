local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")

---@class neotest-scala.Framework
local M = { name = "scalatest" }

---@class neotest-scala.ScalaTestDiscoverOpts
---@field path string
---@field content string

---@class neotest-scala.ScalaTestBuildCommandOpts
---@field root_path string
---@field project string
---@field tree neotest.Tree
---@field name string|nil
---@field extra_args nil|string|string[]
---@field build_tool? "bloop"|"sbt"

---@param content string
---@return boolean
local function has_scalatest_marker(content)
    return content:match("org%.scalatest") ~= nil
end

---@param content string
---@param suite_patterns string[]
---@return boolean
local function matches_suite_style(content, suite_patterns)
    for _, suite_pattern in ipairs(suite_patterns) do
        if content:match("extends%s+.-" .. suite_pattern .. "%f[%W]") then
            return true
        end
    end

    return false
end

---@param content string
---@return "funsuite"|"freespec"|"flatspec"|"propspec"|"wordspec"|"funspec"|"featurespec"|nil
local function detect_style(content)
    if
        matches_suite_style(content, {
            "AnyFunSuite",
            "AsyncFunSuite",
            "FixtureAnyFunSuite",
            "fixture%.AnyFunSuite",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*FunSuite%f[%W]"))
    then
        return "funsuite"
    elseif
        matches_suite_style(content, {
            "AnyFreeSpec",
            "AsyncFreeSpec",
            "FixtureAnyFreeSpec",
            "fixture%.AnyFreeSpec",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*FreeSpec%f[%W]"))
    then
        return "freespec"
    elseif
        matches_suite_style(content, {
            "AnyFlatSpec",
            "AsyncFlatSpec",
            "FixtureAnyFlatSpec",
            "fixture%.AnyFlatSpec",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*FlatSpec%f[%W]"))
    then
        return "flatspec"
    elseif
        matches_suite_style(content, {
            "AnyPropSpec",
            "FixtureAnyPropSpec",
            "fixture%.AnyPropSpec",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*PropSpec%f[%W]"))
    then
        return "propspec"
    elseif
        matches_suite_style(content, {
            "AnyWordSpec",
            "AsyncWordSpec",
            "FixtureAnyWordSpec",
            "fixture%.AnyWordSpec",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*WordSpec%f[%W]"))
    then
        return "wordspec"
    elseif
        matches_suite_style(content, {
            "AnyFunSpec",
            "AsyncFunSpec",
            "FixtureAnyFunSpec",
            "fixture%.AnyFunSpec",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*FunSpec%f[%W]"))
    then
        return "funspec"
    elseif
        matches_suite_style(content, {
            "AnyFeatureSpec",
            "AsyncFeatureSpec",
            "FixtureAnyFeatureSpec",
            "fixture%.AnyFeatureSpec",
        }) or (has_scalatest_marker(content) and content:match("extends%s+.-[%w%.]*FeatureSpec%f[%W]"))
    then
        return "featurespec"
    end

    return nil
end

---Discover test positions for ScalaTest
---@param opts neotest-scala.ScalaTestDiscoverOpts
---@return neotest.Tree | nil
function M.discover_positions(opts)
    local style = detect_style(opts.content)
    if not style then
        return nil
    end

    local path = opts.path
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
    elseif style == "propspec" then
        query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ((call_expression
        function: (call_expression
        function: (identifier) @func_name (#eq? @func_name "property")
        arguments: (arguments (string) @test.name))
      )) @test.definition
    ]]
    elseif style == "freespec" then
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
    elseif style == "wordspec" then
        -- WordSpec: "A thing" should { "do X" in { ... } }
        query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (infix_expression
        left: (string) @test.name
        operator: (_) @spec_in (#eq? @spec_in "in")
        right: (_)
      ) @test.definition
    ]]
    elseif style == "funspec" then
        -- FunSpec: describe("name") { it("test") { ... } }
        query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ((call_expression
        function: (call_expression
          function: (identifier) @func_name (#any-of? @func_name "describe" "context")
          arguments: (arguments (string) @test.name))
      )) @test.definition

      ((call_expression
        function: (call_expression
          function: (identifier) @func_name (#eq? @func_name "it")
          arguments: (arguments (string) @test.name))
      )) @test.definition
    ]]
    elseif style == "featurespec" then
        -- FeatureSpec: Feature("x") { Scenario("y") { ... } }
        query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ((call_expression
        function: (call_expression
          function: (identifier) @func_name (#eq? @func_name "Feature")
          arguments: (arguments (string) @test.name))
      )) @test.definition

      ((call_expression
        function: (call_expression
          function: (identifier) @func_name (#eq? @func_name "Scenario")
          arguments: (arguments (string) @test.name))
      )) @test.definition
    ]]
    else
        -- FlatSpec:
        -- "A Stack" should "pop values" in { }
        -- it should "throw..." in { }
        query = [[
            (object_definition
                name: (identifier) @namespace.name
            ) @namespace.definition

            (class_definition
                name: (identifier) @namespace.name
            ) @namespace.definition

            (infix_expression
                left: (infix_expression
                    left: (string)
                    operator: (_) @spec_init (#any-of? @spec_init "should" "must" "can")
                    right: (string) @test.name)
                operator: (_) @spec_in (#eq? @spec_in "in")
                right: (_)
            ) @test.definition

            (infix_expression
                left: (infix_expression
                    left: (identifier) @it_name (#eq? @it_name "it")
                    operator: (_) @spec_init (#any-of? @spec_init "should" "must" "can")
                    right: (string) @test.name)
                operator: (_) @spec_in (#eq? @spec_in "in")
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
---@param opts neotest-scala.ScalaTestBuildCommandOpts
---@return string[]
function M.build_command(opts)
    local root_path = opts.root_path
    local project = opts.project
    local tree = opts.tree
    local name = opts.name
    local extra_args = opts.extra_args
    local build_tool = opts.build_tool
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

---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return boolean
local function match_test(junit_test, position)
    if not (position and position.id and junit_test and junit_test.name and junit_test.namespace) then
        return true
    end

    local package_name = utils.get_package_name(position.path)
    local position_id = position.id

    -- JUnit test names have leading/trailing spaces that need to be trimmed
    local junit_name = vim.trim(junit_test.name)
    local junit_name_variants = { junit_name }

    local flat_should = junit_name:match("^.-%s+[Ss]hould%s+(.+)$")
    local flat_must = junit_name:match("^.-%s+[Mm]ust%s+(.+)$")
    local flat_can = junit_name:match("^.-%s+[Cc]an%s+(.+)$")
    local feature_scenario = junit_name:gsub("[Ff]eature:%s*", ""):gsub("[Ss]cenario:%s*", "")
    feature_scenario = vim.trim(feature_scenario)

    if flat_should then
        table.insert(junit_name_variants, flat_should)
    end
    if flat_must then
        table.insert(junit_name_variants, flat_must)
    end
    if flat_can then
        table.insert(junit_name_variants, flat_can)
    end
    if feature_scenario ~= "" and feature_scenario ~= junit_name then
        table.insert(junit_name_variants, feature_scenario)
    end

    -- Normalize: remove dashes and spaces for comparison
    local normalized_position = position_id:gsub("-", "."):gsub(" ", "")

    local escaped_package = package_name:gsub("%.", "%%.")
    local position_no_package = normalized_position:gsub("^" .. escaped_package, "")

    for _, variant in ipairs(junit_name_variants) do
        -- Try 1: Standard matching with package prefix (for regular tests)
        local junit_with_package = (package_name .. junit_test.namespace .. "." .. variant):gsub("-", "."):gsub(" ", "")
        if junit_with_package == normalized_position then
            return true
        end

        -- Try 2: Without package prefix (for FreeSpec where JUnit namespace is just class name)
        local junit_test_id = (junit_test.namespace .. "." .. variant):gsub("-", "."):gsub(" ", "")
        if junit_test_id == normalized_position then
            return true
        end

        -- Try 3: For FreeSpec, check if JUnit test ID matches the END of position (after removing package)
        -- FreeSpec JUnit: namespace="FreeSpec", name="Hello, ScalaTest!" -> "FreeSpec.Hello,ScalaTest!"
        -- Position: "com.example.FreeSpec.FreeSpec.Hello,ScalaTest!" -> "FreeSpec.FreeSpec.Hello,ScalaTest!"
        if position_no_package:find(junit_test_id .. "$") then
            return true
        end

        -- Try 4: Remove all dots and compare (fallback for edge cases)
        local junit_no_dots = junit_test_id:gsub("%.", ""):gsub(":", "")
        local position_no_dots = position_no_package:gsub("%.", ""):gsub(":", "")
        if junit_no_dots == position_no_dots then
            return true
        end
    end

    return false
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

---Build test result with diagnostic message for failed tests
---@param junit_test neotest-scala.JUnitTest
---@param position neotest.Position
---@return neotest.Result|nil
function M.build_test_result(junit_test, position)
    if not match_test(junit_test, position) then
        return nil
    end

    local result = {}
    local error = {}

    local file_name = utils.get_file_name(position.path)

    if junit_test.error_message then
        error.message = strip_first_line_location(junit_test.error_message)

        if junit_test.error_stacktrace then
            error.line = utils.extract_line_number(junit_test.error_stacktrace, file_name)
        end
    elseif junit_test.error_stacktrace then
        error.message = junit_test.error_stacktrace:match("^[^\r\n]+") or junit_test.error_stacktrace
        error.message = strip_first_line_location(error.message)
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

---@param value string
---@return string
local function normalize_for_match(value)
    return value:gsub('"', ""):gsub("-", "."):gsub("%s+", "")
end

---@param tree neotest.Tree
---@return table<string, { id: string, name: string, normalized_name: string, normalized_id: string, file_name: string }[]>
local function collect_test_positions(tree)
    local positions_by_name = {}

    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            local position_name = utils.get_position_name(data) or data.name
            local normalized_name = normalize_for_match(position_name)
            local position = {
                id = data.id,
                name = position_name,
                normalized_name = normalized_name,
                normalized_id = normalize_for_match(data.id),
                file_name = utils.get_file_name(data.path),
            }

            positions_by_name[normalized_name] = positions_by_name[normalized_name] or {}
            table.insert(positions_by_name[normalized_name], position)
        end
    end

    return positions_by_name
end

---@param positions_by_name table<string, { id: string, name: string, normalized_name: string, normalized_id: string, file_name: string }[]>
---@param test_name string
---@return { id: string, name: string, normalized_name: string, normalized_id: string, file_name: string }[]
local function find_matching_positions(positions_by_name, test_name)
    local variants = { test_name }
    local lowered = test_name:lower()
    if lowered:match("^should%s+") then
        table.insert(variants, (test_name:gsub("^[Ss]hould%s+", "")))
    elseif lowered:match("^must%s+") then
        table.insert(variants, (test_name:gsub("^[Mm]ust%s+", "")))
    elseif lowered:match("^can%s+") then
        table.insert(variants, (test_name:gsub("^[Cc]an%s+", "")))
    end

    for _, variant in ipairs(variants) do
        local normalized_test_name = normalize_for_match(variant)
        local exact = positions_by_name[normalized_test_name]
        if exact and #exact > 0 then
            return exact
        end

        local matches = {}
        for _, positions in pairs(positions_by_name) do
            for _, pos in ipairs(positions) do
                if pos.normalized_id:find(normalized_test_name, 1, true) then
                    table.insert(matches, pos)
                end
            end
        end

        if #matches > 0 then
            return matches
        end
    end

    return {}
end

---@param detail string
---@return string|nil, number|nil
local function extract_scala_frame(detail)
    local frame_path, frame_line = detail:match("%(([^:]+%.scala):(%d+)%)")
    if frame_path and frame_line then
        return utils.get_file_name(frame_path), tonumber(frame_line)
    end

    local plain_path, plain_line = detail:match("at%s+([^:]+%.scala):(%d+)%s*$")
    if plain_path and plain_line then
        return utils.get_file_name(plain_path), tonumber(plain_line)
    end

    return nil, nil
end

---@param details string[]
---@param preferred_file_name string|nil
---@return number|nil
local function pick_first_matching_line(details, preferred_file_name)
    local fallback_line = nil

    for _, detail in ipairs(details) do
        local frame_file_name, frame_line = extract_scala_frame(detail)
        if frame_line then
            local zero_indexed = frame_line - 1

            if frame_file_name and preferred_file_name and frame_file_name == preferred_file_name then
                return zero_indexed
            end

            if not fallback_line then
                fallback_line = zero_indexed
            end
        end
    end

    return fallback_line
end

--- Parse bloop stdout output for ScalaTest results
---@param output string
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function M.parse_stdout_results(output, tree)
    local results = {}
    local fallback_messages = {}
    local failed_file_names = {}
    local current_failed_positions = nil
    local current_failure_indent = nil
    local current_failure_details = nil

    output = utils.string_remove_ansi(output)
    local positions_by_name = collect_test_positions(tree)

    local function finalize_current_failure()
        if not current_failed_positions or not current_failure_details then
            return
        end

        for _, failed_id in ipairs(current_failed_positions) do
            local err = results[failed_id] and results[failed_id].errors and results[failed_id].errors[1]
            if err then
                err.line = pick_first_matching_line(current_failure_details, failed_file_names[failed_id])
            end
        end
    end

    for line in output:gmatch("[^\r\n]+") do
        local fail_indent, fail_name = line:match("^(%s*)%-%s*(.-)%s+%*%*%* FAILED %*%*%*%s*$")
        local pass_name = line:match("^%s*%-%s*(.-)%s*$")

        if fail_name then
            finalize_current_failure()

            local failed_positions = find_matching_positions(positions_by_name, fail_name)
            local failed_ids = {}

            for _, pos in ipairs(failed_positions) do
                results[pos.id] = {
                    status = TEST_FAILED,
                    errors = { { message = "", line = nil } },
                }
                fallback_messages[pos.id] = fail_name
                failed_file_names[pos.id] = pos.file_name
                table.insert(failed_ids, pos.id)
            end

            current_failed_positions = failed_ids
            current_failure_indent = #fail_indent
            current_failure_details = {}
        else
            if pass_name and not line:match("%*%*%* FAILED %*%*%*") then
                local passed_positions = find_matching_positions(positions_by_name, pass_name)
                for _, pos in ipairs(passed_positions) do
                    if not results[pos.id] then
                        results[pos.id] = { status = TEST_PASSED }
                    end
                end
            end

            local is_summary_line = line:match("^Execution took")
                or line:match("^%d+ tests?,")
                or line:match("^Run completed")

            if is_summary_line then
                finalize_current_failure()
                current_failed_positions = nil
                current_failure_indent = nil
                current_failure_details = nil
            elseif current_failed_positions and #current_failed_positions > 0 and current_failure_indent then
                local line_indent = #(line:match("^(%s*)") or "")

                if line_indent <= current_failure_indent then
                    finalize_current_failure()
                    current_failed_positions = nil
                    current_failure_indent = nil
                    current_failure_details = nil
                else
                    local detail = utils.string_trim(line)
                    if detail ~= "" and not detail:match("^%-%s+") then
                        table.insert(current_failure_details, detail)

                        for _, failed_id in ipairs(current_failed_positions) do
                            local err = results[failed_id].errors[1]

                            if err.message == "" then
                                err.message = detail
                            else
                                err.message = err.message .. "\n" .. detail
                            end
                        end
                    end
                end
            end
        end
    end

    finalize_current_failure()

    for id, result in pairs(results) do
        if result.errors and result.errors[1] then
            if result.errors[1].message == "" then
                result.errors[1].message = fallback_messages[id] or "ScalaTest failure"
            end

            result.errors[1].message = strip_first_line_location(result.errors[1].message)
        end
    end

    return results
end

---@return neotest-scala.Framework
return M
