local lib = require("neotest.lib")
local utils = require("neotest-scala.utils")
local build = require("neotest-scala.build")
local textspec = require("neotest-scala.framework.specs2.textspec")

---@class neotest-scala.Framework
local M = { name = "specs2" }

---@param content string
---@return "mutable" | "text" | nil
function M.detect_style(content)
    if content:match('s2"""') then
        return "text"
    elseif content:match("extends%s+Specification") then
        return "mutable"
    end
    return nil
end

---@param style "mutable" | "text"
---@param path string
---@param content string
---@param opts table
---@return neotest.Tree | nil
function M.discover_positions(style, path, content, opts)
    if style == "text" then
        local textspec = require("neotest-scala.framework.specs2.textspec")
        return textspec.discover_positions(path, content)
    end

    local query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (infix_expression
        left: (string) @test.name
        operator: (_) @spec_init (#any-of? @spec_init ">>" "in")
        right: (_)
      ) @test.definition
    ]]

    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = utils.build_position_id,
    })
end

---Build namespace for specs2 tests
---@param ns_node neotest.Tree
---@param report_prefix string
---@param node neotest.Tree
---@return table
function M.build_namespace(ns_node, report_prefix, node)
    if textspec.is_textspec_namespace(ns_node) then
        return textspec.build_namespace(ns_node, report_prefix)
    end

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

---@param root_path string Project root path
---@param project string
---@param tree neotest.Tree
---@param name string
---@param extra_args table|string
---@return string[]
function M.build_command(root_path, project, tree, name, extra_args)
    return build.command(root_path, project, tree, name, extra_args)
end

---@param junit_test table<string, string>
---@param position neotest.Position
---@return boolean
function M.match_test(junit_test, position)
    if position.extra and position.extra.textspec_path then
        return textspec.match_test(junit_test, position)
    end

    local package_name = utils.get_package_name(position.path)
    local test_id = position.id:gsub(" ", ".")
    local test_prefix = package_name .. junit_test.namespace
    local test_postfix = junit_test.name:gsub("should::", ""):gsub("must::", ""):gsub("::", "."):gsub(" ", ".")
    return vim.startswith(test_id, test_prefix) and vim.endswith(test_id, test_postfix)
end

--- Parse bloop stdout output for test results
---@param output string The raw stdout from bloop test
---@param tree neotest.Tree The test tree for matching
---@return table<string, neotest.Result> Test results indexed by position.id
function M.parse_stdout_results(output, tree)
    local results = {}
    local utils = require("neotest-scala.utils")

    output = utils.string_remove_ansi(output)

    -- Build position lookup for matching
    local positions = {}
    for _, node in tree:iter_nodes() do
        local data = node:data()
        if data.type == "test" then
            positions[data.id] = data
        end
    end

    local pending_failure_name = nil

    for line in output:gmatch("[^\r\n]+") do
        -- Pass: "+ name"
        local pass_name = line:match("^%s*%+%s*(.+)$")
        if pass_name then
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and pass_name:find(pos_name:gsub("['\"]", ""), 1, true) then
                    results[pos_id] = { status = TEST_PASSED }
                end
            end
        end

        -- Fail: "x name"
        local fail_name = line:match("^%s*x%s*(.+)$")
        if fail_name then
            pending_failure_name = fail_name
            for pos_id, pos in pairs(positions) do
                local pos_name = utils.get_position_name(pos) or pos.name
                if pos_name and fail_name:find(pos_name:gsub("['\"]", ""), 1, true) then
                    results[pos_id] = { status = TEST_FAILED, errors = {} }
                end
            end
        end

        -- Error: "[E] message (file:line)"
        local error_msg, file, line_num = line:match("^%[E%]%s*(.+)%s*%(([^:]+):(%d+)%)$")
        if error_msg and file and line_num then
            for pos_id, result in pairs(results) do
                if result.status == TEST_FAILED and result.errors and #result.errors == 0 then
                    table.insert(result.errors, { message = error_msg, line = tonumber(line_num) - 1 })
                end
            end
        end
    end

    local global_failure = nil
    if output:match("Failed to compile") then
        global_failure = "Compilation failed"
    elseif output:match("Test suite aborted") or output:match("Failed to initialize") then
        global_failure = "Test suite aborted"
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
