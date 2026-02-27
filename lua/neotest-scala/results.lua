local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local junit = require("neotest-scala.junit")
local build = require("neotest-scala.build")
local logger = require("neotest-scala.logger")
local results_logger = logger.new("results")

local M = {}

---@param strategy table|nil
---@return boolean
local function is_dap_run(strategy)
    return type(strategy) == "table" and strategy.type == "scala" and strategy.request == "launch"
end

---@param node neotest.Tree
---@return table<string, neotest.Result>
local function build_no_suite_failure_results(node)
    local message = "No test suites were run."
    local failures = {}

    for _, child in node:iter_nodes() do
        local data = child:data()
        if data.type == "test" then
            failures[data.id] = {
                status = TEST_FAILED,
                errors = { { message = message } },
            }
        end
    end

    return failures
end

local function collect_namespaces(framework, node, report_prefix)
    local ns_data = node:data()
    local namespaces = {}

    if ns_data.type == "file" then
        for _, ns_node in ipairs(node:children()) do
            table.insert(namespaces, framework.build_namespace(ns_node, report_prefix, ns_node))
        end
    elseif ns_data.type == "namespace" then
        table.insert(namespaces, framework.build_namespace(node, report_prefix, node))
    elseif ns_data.type == "test" then
        local ns_node = utils.find_node(node, "namespace", false)
        if ns_node then
            table.insert(namespaces, framework.build_namespace(ns_node, report_prefix, node))
        end
    else
        vim.print("[neotest-scala] Neotest run type '" .. ns_data.type .. "' is not supported")
        results_logger.warn("Neotest run type is not supported: " .. ns_data.type, { file = ns_data.path })
        return nil
    end

    return namespaces
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param node neotest.Tree
---@return table<string, neotest.Result>
function M.collect(spec, result, node)
    local lib = require("neotest.lib")
    local run_file = nil
    if node and type(node.data) == "function" then
        local node_data = node:data()
        if node_data then
            run_file = node_data.path
        end
    end

    local success, output = pcall(lib.files.read, result.output)
    if not success then
        vim.print("[neotest-scala] Failed to read test output")
        results_logger.error("Failed to read test output", { file = run_file })
        return {}
    elseif string.match(output, "Compilation failed") then
        vim.print("[neotest-scala] Compilation failed")
        results_logger.warn("Compilation failed", { file = run_file })
        return {}
    end

    if not spec.env then
        return {}
    end

    local framework = fw.get_framework_class(spec.env.framework)
    if not framework then
        vim.print("[neotest-scala] Test framework '" .. spec.env.framework .. "' is not supported")
        results_logger.warn("Test framework is not supported: " .. tostring(spec.env.framework), { file = run_file })
        return {}
    end

    results_logger.debug({
        event = "results:collect",
        framework = framework.name,
        build_tool = spec.env.build_tool,
        dap = is_dap_run(spec.strategy),
    }, { file = run_file })

    if is_dap_run(spec.strategy) then
        if output:match("No test suites were run%.?") then
            results_logger.warn("No test suites were run", { file = run_file })
            return build_no_suite_failure_results(node)
        end

        local parsed = framework.parse_stdout_results(output, node)
        if type(parsed) == "table" and next(parsed) ~= nil then
            results_logger.debug("Using DAP stdout parser results", { file = run_file })
            return parsed
        end
    end

    -- Branch on build tool
    local root_path = spec.env.root_path
    local build_tool = spec.env.build_tool
    local build_target_info = spec.env.build_target_info

    if not build_tool and root_path then
        build_tool = build.get_tool(root_path, build_target_info)
    end

    if build_tool == "bloop" then
        results_logger.debug("Using bloop stdout parser results", { file = run_file })
        return framework.parse_stdout_results(output, node)
    end

    local base_dir = spec.env.build_target_info["Base Directory"]
    if not base_dir or not base_dir[1] then
        vim.print("[neotest-scala] Cannot find base directory")
        results_logger.warn("Cannot find base directory", { file = run_file })
        return {}
    end

    local project_dir = base_dir[1]:match("^file:(.*)")
    if not project_dir then
        vim.print("[neotest-scala] Cannot parse project directory")
        results_logger.warn("Cannot parse project directory", { file = run_file })
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
            local test_result = framework.build_position_result({
                position = position,
                test_node = test,
                junit_results = junit_results,
                namespace = ns,
            })

            if not test_result then
                vim.print(
                    "[neotest-scala] Framework '"
                        .. framework.name
                        .. "' returned no result for position '"
                        .. position.id
                        .. "'"
                )
                results_logger.warn("Framework returned no result for position " .. position.id, { file = position.path })
                test_result = { status = TEST_FAILED }
            end

            test_results[position.id] = test_result
        end
    end

    return test_results
end

return M
