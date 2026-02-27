local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local junit = require("neotest-scala.junit")
local build = require("neotest-scala.build")

local M = {}

---@param strategy table|nil
---@return boolean
local function is_dap_run(strategy)
    return type(strategy) == "table" and strategy.type == "scala" and strategy.request == "launch"
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

    if is_dap_run(spec.strategy) then
        local parsed = framework.parse_stdout_results(log, node)
        if type(parsed) == "table" and next(parsed) ~= nil then
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
                test_result = { status = TEST_FAILED }
            end

            test_results[position.id] = test_result
        end
    end

    return test_results
end

return M
