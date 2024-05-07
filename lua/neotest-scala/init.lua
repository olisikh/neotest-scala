local Path = require("plenary.path")
local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local commands = require("neotest-scala.commands")

---@type neotest.Adapter
local adapter = { name = "neotest-scala" }

adapter.root = lib.files.match_root_pattern("build.sbt")

-- NOTE: get_runner(), get_args(), get_framework() down below are defined as defaults, can be overriden by the plugin user
local function get_runner()
    local vim_test_runner = vim.g["test#scala#runner"]
    if vim_test_runner == "blooptest" then
        return "bloop"
    end
    if vim_test_runner and lib.func_util.index({ "bloop", "sbt" }, vim_test_runner) then
        return vim_test_runner
    end
    return "bloop"
end

local function get_args()
    return {}
end

-- TODO: Automatically detect framework based on build.sbt
local function get_framework()
    return "utest"
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
    local query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition
	  
      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ;; utest, munit, scalatest (FunSuite)
      ((call_expression
        function: (call_expression
        function: (identifier) @func_name (#match? @func_name "test")
        arguments: (arguments (string) @test.name))
      )) @test.definition


      ;; scalatest (FreeSpec), specs2 (mutable.Specification)
      (infix_expression 
        left: (string) @test.name
        operator: (_) @spec_init (#any-of? @spec_init "in" ">>")
        right: (_)
      ) @test.definition
    ]]
    return lib.treesitter.parse_positions(path, query, {
        nested_tests = true,
        require_namespaces = true,
        position_id = build_position_id,
    })
end

---Get project name from build file.
---@return string|nil
local function get_project_name(path, runner)
    if runner == "bloop" then
        return commands.get_bloop_project_name_sync()
    elseif runner == "sbt" then
        return commands.get_sbt_project_name_sync()
    end

    return nil
end

---Builds strategy configuration for running tests.
---@param strategy string
---@param tree neotest.Tree
---@param project string
---@return table|nil
local function get_strategy_config(strategy, tree, project)
    local position = tree:data()
    if strategy ~= "dap" or position.type == "dir" then
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

        -- Constructs ScalaTestSuitesDebugRequest request.
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

    local runner = get_runner()
    assert(lib.func_util.index({ "bloop", "sbt" }, runner), "[neotest-scala]: runner must be either 'sbt' or 'bloop'")

    local project = get_project_name(position.path, runner)
    assert(project, "[neotest-scala]: scala project not found in the build file")

    local framework = fw.get_framework_class(get_framework())
    if not framework then
        return {}
    end

    local extra_args = vim.list_extend(get_args(), args.extra_args or {})
    local command = framework.build_command(runner, project, args.tree, utils.get_position_name(position), extra_args)
    local strategy = get_strategy_config(args.strategy, args.tree, project)

    return { command = command, strategy = strategy }
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
function adapter.results(_, result, tree)
    local success, lines = pcall(lib.files.read_lines, result.output)
    local framework = fw.get_framework_class(get_framework())
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
        if is_callable(opts.framework) then
            get_framework = opts.framework
        elseif opts.framework then
            get_framework = function()
                return opts.framework
            end
        end
        return adapter
    end,
})

return adapter
