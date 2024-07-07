local Path = require("plenary.path")
local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local junit = require("neotest-scala.junit")

---@type neotest.Adapter
local adapter = { name = "neotest-scala" }

adapter.root = lib.files.match_root_pattern("build.sbt")

local function get_args(_, _, _, _)
    return {}
end

---Check if subject file is a test file
---@async
---@param file_path string
---@return boolean
function adapter.is_test_file(file_path)
    if not vim.endswith(file_path, ".scala") then
        return false
    end

    local file_name = string.lower(utils.get_file_name(file_path))
    local patterns = { "test", "spec", "suite" }
    for _, pattern in ipairs(patterns) do
        if string.find(file_name, pattern) then
            return true
        end
    end
    return false
end

---Filter directories when searching for test files
---@async
---@param name string Name of directory
---@param rel_path string Path to directory, relative to root
---@param root string Root directory of project
---@return boolean
function adapter.filter_dir(_, _, _)
    return true
end

---@param pos neotest.Position
---@return string
local get_parent_name = function(pos)
    if pos.type == "dir" or pos.type == "file" then
        return ""
    end
    if pos.type == "namespace" then
        return utils.get_package_name(pos.path) .. pos.name
    end
    return utils.get_position_name(pos)
end

---@param position neotest.Position The position to return an ID for
---@param parents neotest.Position[] Parent positions for the position
---@return string
local function build_position_id(position, parents)
    return table.concat(
        vim.tbl_flatten({
            vim.tbl_map(get_parent_name, parents),
            utils.get_position_name(position),
        }),
        "."
    )
end

---@async
---@param path string Path to the file with tests
---@return neotest.Tree | nil
function adapter.discover_positions(path)
    --query
    local query = [[
      ;; zio-test
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition
	  
      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ;; utest, munit, zio-test, scalatest (FunSuite)
      ((call_expression
        function: (call_expression
        function: (identifier) @func_name (#any-of? @func_name "test" "suite" "suiteAll")
        arguments: (arguments (string) @test.name))
      )) @test.definition

      ;; scalatest (FreeSpec), specs2 (mutable.Specification)
      ;; specs2 supports 'in', 'can', 'should' and '>>' syntax for test blocks
      (infix_expression 
        left: (string) @test.name
        operator: (_) @spec_init (#any-of? @spec_init "-" "in" "should" "can" ">>")
        right: (_)
      ) @test.definition
    ]]
    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = build_position_id,
    })
end

---Builds strategy configuration for running tests.
---@param strategy string
---@param tree neotest.Tree
---@param project string
---@return table|nil
local function get_strategy_config(strategy, tree, project)
    local position = tree:data()
    if strategy == "integrated" then
        -- NOTE: run with a background process running actual sbt/bloop test, so no debug configuration required
        return nil
    end

    if position.type == "dir" then
        return nil
    end

    if position.type == "file" then
        return {
            type = "scala",
            request = "launch",
            name = "NeotestScala",
            metals = {
                runType = "testFile",
                path = position.path,
            },
        }
    end

    local metals_args = nil
    if position.type == "namespace" then
        metals_args = {
            testClass = utils.get_package_name(position.path) .. position.name,
        }
    end

    if position.type == "test" then
        local root = adapter.root(position.path)
        local parent = tree:parent():data()

        -- NOTE: Constructs ScalaTestSuitesDebugRequest request, to debug a specific test within a test class.
        -- Test framework must implement sbt.testing.TestSelector for metals to recognize the individual tests
        -- https://github.com/scalameta/metals/blob/main/metals/src/main/scala/scala/meta/internal/metals/ServerCommands.scala#L808C18-L808C45
        metals_args = {
            target = { uri = "file:" .. root .. "/?id=" .. project .. "-test" },
            requestData = {
                suites = {
                    {
                        className = get_parent_name(parent),
                        tests = { utils.get_position_name(position) },
                    },
                },
                jvmOptions = {},
                environmentVariables = {},
            },
        }
    end

    if metals_args ~= nil then
        return {
            type = "scala",
            request = "launch",
            -- NOTE: The `from_lens` is set here because nvim-metals passes the
            -- complete `metals` param to metals server without modifying (reading) it.
            name = "from_lens",
            metals = metals_args,
        }
    end

    return nil
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function adapter.build_spec(args)
    local position = args.tree:data()
    local root_path = adapter.root(position.path)
    assert(root_path, "[neotest-scala]: Can't resolve root project folder")

    local build_target_info = utils.get_build_target_info(root_path, position.path)
    if not build_target_info then
        vim.print("[neotest-scala]: Can't resolve project, has Metals initialised? Please try again.")
        return {}
    end

    local project_name = utils.get_project_name(build_target_info)
    if not project_name then
        vim.print("[neotest-scala]: Can't resolve project name")
        return {}
    end

    local framework = utils.get_framework(build_target_info)
    local framework_class = fw.get_framework_class(framework)
    if not framework_class then
        vim.print("[neotest-scala]: Failed to detect testing library used in the project")
        return {}
    end

    local extra_args = vim.list_extend(
        get_args({
            path = root_path,
            build_target_info = build_target_info,
            project_name = project_name,
            framework = framework,
        }),
        args.extra_args or {}
    )

    local test_name = utils.get_position_name(position)
    local command = framework_class.build_command(project_name, args.tree, test_name, extra_args)
    local strategy = get_strategy_config(args.strategy, args.tree, project_name)

    vim.print("[neotest-scala] Running test command: " .. vim.inspect(command))

    return {
        command = command,
        strategy = strategy,
        env = {
            root_path = root_path,
            build_target_info = build_target_info,
            project_name = project_name,
            framework = framework,
        },
    }
end

local function collect_result(framework, junit_test, position)
    local test_result = nil

    if framework.build_test_result then
        test_result = framework.build_test_result(junit_test, position)
    else
        test_result = {}

        local message = junit_test.error_message or junit_test.error_stacktrace
        if message then
            test_result.errors = { { message = message } }
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
        junit_report_path = report_prefix .. "TEST-" .. package_name .. id .. ".xml",
        positions = {},
    }

    for _, n in node:iter_nodes() do
        table.insert(namespace["positions"], n:data())
    end

    return namespace
end

local function match_test(namespace, junit_result, position)
    local package_name = utils.get_package_name(position.path)
    local junit_test_id = (package_name .. namespace.namespace .. "." .. junit_result.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")

    return junit_test_id == test_id
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param node neotest.Tree
---@return table<string, neotest.Result>
function adapter.results(spec, _, node)
    local framework = fw.get_framework_class(spec.env.framework)
    if not framework then
        vim.print("[neotest-scala] Test framework '" .. spec.env.framework .. "' is not supported")
        return {}
    end

    local project_dir = spec.env.build_target_info["Base Directory"][1]:match("^file:(.*)")
    local report_prefix = project_dir .. "target/test-reports/"

    local ns_data = node:data()
    local namespaces = {}

    if ns_data.type == "file" then
        for _, ns_node in ipairs(node:children()) do
            table.insert(namespaces, build_namespace(ns_node, report_prefix, ns_node))
        end
    elseif ns_data.type == "namespace" then
        table.insert(namespaces, build_namespace(node, report_prefix, node))
    elseif ns_data.type == "test" then
        local ns_node = utils.find_node(node, "namespace", false)
        if ns_node then
            table.insert(namespaces, build_namespace(ns_node, report_prefix, node))
        end
    else
        vim.print("[neotest-scala] Neotest run type '" .. ns_data.type .. "' is not supported")
        return {}
    end

    local test_results = {}

    for _, ns in pairs(namespaces) do
        local junit_results = junit.collect_results(ns)

        for _, position in ipairs(ns.positions) do
            local test_result = nil

            for _, junit_result in ipairs(junit_results) do
                if junit_result.namespace == ns.namespace then
                    if framework.match_test then
                        if framework.match_test(junit_result, position) then
                            test_result = collect_result(framework, junit_result, position)
                        end
                    elseif match_test(ns, junit_result, position) then
                        test_result = collect_result(framework, junit_result, position)
                    end
                end

                if test_result then
                    break
                end
            end

            if test_result then
                test_results[position.id] = test_result
            else
                test_results[position.id] = {
                    status = TEST_PASSED,
                }
            end
        end
    end

    return test_results
end

local function is_callable(obj)
    return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

setmetatable(adapter, {
    __call = function(_, opts)
        if is_callable(opts.args) then
            get_args = opts.args
        elseif opts.args then
            get_args = function()
                return opts.args
            end
        end
        return adapter
    end,
})

return adapter
