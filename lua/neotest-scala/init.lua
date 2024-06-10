local Path = require("plenary.path")
local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")

---@type neotest.Adapter
local adapter = { name = "neotest-scala" }

adapter.root = lib.files.match_root_pattern("build.sbt")

local function get_runner(path, project)
    local vim_test_runner = vim.g["test#scala#runner"]

    local runner = "bloop"
    if vim_test_runner == "blooptest" then
        runner = "bloop"
    elseif vim_test_runner and lib.func_util.index({ "bloop", "sbt" }, vim_test_runner) then
        runner = vim_test_runner
    else
        runner = utils.get_build_tool_name(path, project)
    end
    return runner
end

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
    local elems = vim.split(file_path, Path.path.sep)
    local file_name = string.lower(elems[#elems])
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
---@return neotest.Tree | nil
function adapter.discover_positions(path)
    --query
    local query = [[
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
        operator: (_) @spec_init (#any-of? @spec_init "in" "should" "can" ">>")
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
    local path = adapter.root(position.path)
    assert(path, "[neotest-scala]: can't resolve root project folder")

    local project = utils.get_project_name()
    if not project then
        vim.print("[neotest-scala]: can't resolve project name, maybe metals is not ready, try again later")
        return {}
    end

    local runner = get_runner(path, project)
    assert(lib.func_util.index({ "bloop", "sbt" }, runner), "[neotest-scala]: runner must be either 'sbt' or 'bloop'")

    local framework = utils.get_framework(path, project)

    local framework_class = fw.get_framework_class(framework)
    if not framework_class then
        vim.print("[neotest-scala]: failed to detect testing library used in the project")
        return {}
    end

    local extra_args = vim.list_extend(
        get_args({
            path = path,
            project = project,
            runner = runner,
            framework = framework,
        }),
        args.extra_args or {}
    )

    local test_name = utils.get_position_name(position)
    local command = framework_class.build_command(runner, project, args.tree, test_name, extra_args)
    local strategy = get_strategy_config(args.strategy, args.tree, project)

    return {
        command = command,
        strategy = strategy,
        env = {
            path = path,
            project = project,
            framework = framework,
        },
    }
end

---Extract results from the test output.
---@param tree neotest.Tree
---@param test_results table<string, string>
---@param match_func nil|fun(test_results: table<string, string>, position_id :string):string|nil
---@return table<string, neotest.Result>
local function get_results(tree, test_results, match_func)
    local no_results = vim.tbl_isempty(test_results)
    local results = {}
    for _, node in tree:iter_nodes() do
        local position = node:data()
        if no_results then
            results[position.id] = { status = TEST_FAILED }
        else
            local test_result
            if match_func then
                test_result = match_func(test_results, position.id)
            else
                test_result = test_results[position.id]
            end
            if test_result then
                results[position.id] = test_result
            end
        end
    end
    return results
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function adapter.results(spec, result, tree)
    local success, lines = pcall(lib.files.read_lines, result.output)

    if not spec.env or not spec.env.framework then
        return {}
    end

    local framework = fw.get_framework_class(spec.env.framework)
    if not success or not framework then
        return {}
    end

    local test_results = framework.get_test_results(lines)
    return get_results(tree, test_results, framework.match_func)
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
        if is_callable(opts.runner) then
            get_runner = opts.runner
        elseif opts.runner then
            get_runner = function()
                return opts.runner
            end
        end
        return adapter
    end,
})

return adapter
