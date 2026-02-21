local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local junit = require("neotest-scala.junit")
local textspec = require("neotest-scala.framework.specs2.textspec")

local M = {}

local function collect_result(framework, junit_test, position)
    local test_result = nil

    if framework.build_test_result then
        test_result = framework.build_test_result(junit_test, position)
    else
        test_result = {}

        local message = junit_test.error_message or junit_test.error_stacktrace

        if message then
            local error = { message = message }

            local file_name = utils.get_file_name(position.path)
            local stacktrace = junit_test.error_stacktrace or ""
            local line = string.match(stacktrace, "%(" .. file_name .. ":(%d+)%)")

            if line then
                error.line = tonumber(line) - 1
            end

            test_result.errors = { error }
            test_result.status = TEST_FAILED
        else
            test_result.status = TEST_PASSED
        end
    end

    test_result.test_id = position.id

    return test_result
end

local function build_namespace(ns_node, report_prefix, node)
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
        table.insert(namespace["tests"], n)
    end

    return namespace
end

local function match_test(namespace, junit_result, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = (package_name .. namespace.namespace .. "." .. junit_result.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")

    return junit_test_id == test_id
end

local function collect_namespaces(node, report_prefix)
    local ns_data = node:data()
    local namespaces = {}

    if ns_data.type == "file" then
        for _, ns_node in ipairs(node:children()) do
            if textspec.is_textspec_namespace(ns_node) then
                table.insert(namespaces, textspec.build_namespace(ns_node, report_prefix))
            else
                table.insert(namespaces, build_namespace(ns_node, report_prefix, ns_node))
            end
        end
    elseif ns_data.type == "namespace" then
        if textspec.is_textspec_namespace(node) then
            table.insert(namespaces, textspec.build_namespace(node, report_prefix))
        else
            table.insert(namespaces, build_namespace(node, report_prefix, node))
        end
    elseif ns_data.type == "test" then
        local ns_node = utils.find_node(node, "namespace", false)
        if ns_node then
            if textspec.is_textspec_namespace(ns_node) then
                table.insert(namespaces, textspec.build_namespace(ns_node, report_prefix))
            else
                table.insert(namespaces, build_namespace(ns_node, report_prefix, node))
            end
        end
    else
        vim.print("[neotest-scala] Neotest run type '" .. ns_data.type .. "' is not supported")
        return nil
    end

    return namespaces
end

local function match_junit_result(framework, junit_result, position, ns)
    if framework.match_test and framework.match_test(junit_result, position) then
        return true
    end

    if position.extra and position.extra.textspec_path then
        return textspec.match_test(junit_result, position)
    end

    return match_test(ns, junit_result, position)
end

local function find_test_result(framework, junit_results, position, ns, framework_name)
    for _, junit_result in ipairs(junit_results) do
        local matches = false

        if framework_name == "scalatest" then
            matches = framework.match_test and framework.match_test(junit_result, position)
        elseif junit_result.namespace == ns.namespace then
            matches = match_junit_result(framework, junit_result, position, ns)
        end

        if matches then
            return collect_result(framework, junit_result, position)
        end
    end

    return nil
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param node neotest.Tree
---@return table<string, neotest.Result>
function M.collect(spec, result, node)
    local lib = require("neotest.lib")

    local success, log = pcall(lib.files.read, result.output)
    if not success then
        vim.print("[neotest-scala] Failed to read test output")
        return {}
    elseif string.match(log, "Compilation failed") then
        vim.print("[neotest-scala] Compilation failed")
        return {}
    end

    if not spec.env then
        return {}
    end

    local framework = fw.get_framework_class(spec.env.framework)
    if not framework then
        vim.print("[neotest-scala] Test framework '" .. spec.env.framework .. "' is not supported")
        return {}
    end

    local base_dir = spec.env.build_target_info["Base Directory"]
    if not base_dir or not base_dir[1] then
        vim.print("[neotest-scala] Cannot find base directory")
        return {}
    end

    local project_dir = base_dir[1]:match("^file:(.*)")
    if not project_dir then
        vim.print("[neotest-scala] Cannot parse project directory")
        return {}
    end

    local report_prefix = project_dir .. "target/test-reports/"
    local namespaces = collect_namespaces(node, report_prefix)

    if not namespaces then
        return {}
    end

    local test_results = {}

    for _, ns in pairs(namespaces) do
        local junit_results = junit.collect_results(ns)

        for _, test in ipairs(ns.tests) do
            local position = test:data()
            local test_result = find_test_result(framework, junit_results, position, ns, spec.env.framework)

            if test_result then
                test_results[position.id] = test_result
            else
                local test_status = utils.has_nested_tests(test) and TEST_PASSED or TEST_FAILED

                test_results[position.id] = {
                    status = test_status,
                }
            end
        end
    end

    return test_results
end

return M
