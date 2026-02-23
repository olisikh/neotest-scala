local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local junit = require("neotest-scala.junit")
local build = require("neotest-scala.build")

local M = {}

local function build_test_result(junit_test, position)
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

local function collect_result(framework, junit_test, position)
    local test_result = nil

    if framework.build_test_result then
        test_result = framework.build_test_result(junit_test, position)
    else
        test_result = build_test_result(junit_test, position)
    end

    test_result.test_id = position.id

    return test_result
end

local function collect_namespaces(framework, node, report_prefix)
    local ns_data = node:data()
    local namespaces = {}

    if ns_data.type == "file" then
        for _, ns_node in ipairs(node:children()) do
            if framework.build_namespace then
                table.insert(namespaces, framework.build_namespace(ns_node, report_prefix, ns_node))
            end
        end
    elseif ns_data.type == "namespace" then
        if framework.build_namespace then
            table.insert(namespaces, framework.build_namespace(node, report_prefix, node))
        end
    elseif ns_data.type == "test" then
        local ns_node = utils.find_node(node, "namespace", false)
        if ns_node and framework.build_namespace then
            table.insert(namespaces, framework.build_namespace(ns_node, report_prefix, node))
        end
    else
        vim.print("[neotest-scala] Neotest run type '" .. ns_data.type .. "' is not supported")
        return nil
    end

    return namespaces
end

local function find_test_result(opts)
    local framework = opts.framework
    local junit_results = opts.junit_results
    local position = opts.position
    local ns = opts.ns

    for _, junit_result in ipairs(junit_results) do
        -- Scalatest bypasses namespace check; frameworks handle their own matching
        local skip_namespace_check = framework.name == "scalatest"

        if skip_namespace_check or junit_result.namespace == ns.namespace then
            if framework.match_test and framework.match_test(junit_result, position) then
                return collect_result(framework, junit_result, position)
            end
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

    -- Branch on build tool
    local root_path = spec.env.root_path
    local build_tool = spec.env.build_tool

    if not build_tool and root_path then
        build_tool = build.get_tool(root_path)
    end

    if build_tool == "bloop" and framework.parse_stdout_results then
        return framework.parse_stdout_results(log, node)
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
    local namespaces = collect_namespaces(framework, node, report_prefix)

    if not namespaces then
        return {}
    end

    local test_results = {}

    for _, ns in pairs(namespaces) do
        local junit_results = junit.collect_results(ns)

        for _, test in ipairs(ns.tests) do
            local position = test:data()
            local test_result = find_test_result({
                framework = framework,
                junit_results = junit_results,
                position = position,
                ns = ns,
            })

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
