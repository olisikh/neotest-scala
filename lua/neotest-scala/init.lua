local Path = require("plenary.path")
local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local ts = vim.treesitter

---@type neotest.Adapter
local adapter = { name = "neotest-scala" }

adapter.root = lib.files.match_root_pattern("build.sbt")

local function get_runner(build_target_info, path, project_name)
    local vim_test_runner = vim.g["test#scala#runner"]

    local runner = "sbt"

    if vim_test_runner == "blooptest" then
        runner = "bloop"
    elseif vim_test_runner and lib.func_util.index({ "bloop", "sbt" }, vim_test_runner) then
        runner = vim_test_runner
    else
        if build_target_info and build_target_info["Classes Directory"] then
            local classpath = build_target_info["Classes Directory"]

            for _, jar in ipairs(classpath) do
                if
                    vim.startswith(jar, "file://" .. path .. "/.bloop/" .. project_name .. "/bloop-bsp-clients-classes")
                then
                    runner = "bloop"
                    break
                end
            end
        end
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

    local runner = get_runner(build_target_info, root_path, project_name)
    assert(lib.func_util.index({ "bloop", "sbt" }, runner), "[neotest-scala]: Runner must be either 'sbt' or 'bloop'")

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
            runner = runner,
            framework = framework,
        }),
        args.extra_args or {}
    )

    local test_name = utils.get_position_name(position)
    local command = framework_class.build_command(runner, project_name, args.tree, test_name, extra_args)
    local strategy = get_strategy_config(args.strategy, args.tree, project_name)

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

-- ---Extract results from the test output.
-- ---@param tree neotest.Tree
-- ---@param test_results table<string, string>
-- ---@param match_func nil|fun(test_results: table<string, string>, position_id :string):string|nil
-- ---@return table<string, neotest.Result>
-- local function get_results(tree, test_results, match_func)
--     local no_results = vim.tbl_isempty(test_results)
--     local results = {}
--     for _, node in tree:iter_nodes() do
--         local position = node:data()
--         if no_results then
--             results[position.id] = { status = TEST_FAILED }
--         else
--             local test_result
--             if match_func then
--                 test_result = match_func(test_results, position.id)
--             else
--                 test_result = test_results[position.id]
--             end
--             if test_result then
--                 results[position.id] = test_result
--             end
--         end
--     end
--     return results
-- end

--query
local junit_query = ts.query.parse(
    "xml",
    [[
(element 
  (STag 
    (Name) @_1 (#eq? @_1 "testcase")
    (Attribute 
      (Name) @_2 (#eq? @_2 "name")
      (AttValue) @testcase.name
    )
  )
  (content
    (element
      (STag 
        (Name) @_4 (#eq? @_4 "failure")
        (Attribute 
          (Name) @_5 (#eq? @_5 "message")
          (AttValue) @testcase.message
        )
        (Attribute
          (Name) @_7 (#eq? @_7 "type")
          (AttValue) @testcase.error_type
        )
      )
      (content) @testcase.error_message
    )? @testcase.content
  ) @testcase
)
]]
)

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function adapter.results(spec, result, tree)
    if not spec.env or not spec.env.framework or not spec.env.build_target_info then
        return {}
    end

    local framework = fw.get_framework_class(spec.env.framework)
    if not framework then
        vim.print("[neotest-scala] test framework " .. spec.env.framework .. " is not supported")
        return {}
    end

    local project_dir = spec.env.build_target_info["Base Directory"][1]:match("^file:(.*)")
    local report_prefix = project_dir .. "target/test-reports/"

    local nodes_group = {}
    for _, node in tree:iter_nodes() do
        local data = node:data()
        local path = data.path

        if not nodes_group[path] then
            nodes_group[path] = { nodes = {} }
        end

        if data.type == "namespace" then
            local package_name = utils.get_package_name(path)
            local test_name = data.id
            assert(test_name, "[neotest-scala] Failed to resolve file_name of the test: " .. path)

            nodes_group[path] = {
                test_report_file = report_prefix .. "TEST-" .. package_name .. test_name .. ".xml",
                test_suite_name = package_name .. test_name,
                package_name = package_name,
                nodes = {},
            }
        end

        table.insert(nodes_group[path]["nodes"], data)
    end

    local junit_tests = {}
    local test_results = {}

    for _, node_group in pairs(nodes_group) do
        local success, junit_xml = pcall(lib.files.read, node_group.test_report_file)
        if not success then
            return {}
        end

        local report_tree = ts.get_string_parser(junit_xml, "xml")
        local parsed = report_tree:parse()[1]

        local query_results = junit_query:iter_matches(parsed:root(), report_tree:source())

        for _, matches, _ in query_results do
            local test_name_node = matches[3]
            local error_message_node = matches[6]
            local error_type_node = matches[8]
            local error_stacktrace_node = matches[9]

            local test = {}
            if test_name_node then
                test.name = utils.string_unescape_xml(
                    utils.string_remove_dquotes(ts.get_node_text(test_name_node, report_tree:source()))
                )
            end
            if error_message_node then
                test.error_message = utils.string_unescape_xml(
                    utils.string_remove_ansi(
                        utils.string_remove_dquotes(ts.get_node_text(error_message_node, report_tree:source()))
                    )
                )
            end
            if error_type_node then
                test.error_type = utils.string_remove_dquotes(ts.get_node_text(error_type_node, report_tree:source()))
            end
            if error_stacktrace_node then
                test.error_stacktrace = utils.string_unescape_xml(
                    utils.string_remove_ansi(
                        utils.string_despace(ts.get_node_text(error_stacktrace_node, report_tree:source()))
                    )
                )
            end

            utils.print_table(test)

            table.insert(junit_tests, test)
        end

        local function collect_result(junit_test, node)
            local test_result = {
                test_id = node.id,
            }

            local message = junit_test.error_message or junit_test.error_stacktrace
            if message then
                test_result.errors = {
                    {
                        message = message,
                    },
                }
                test_result.status = TEST_FAILED
            else
                test_result.status = TEST_PASSED
            end

            test_results[node.id] = test_result
        end

        for _, node in ipairs(node_group.nodes) do
            for _, junit_test in ipairs(junit_tests) do
                if framework.match_func and framework.match_func(junit_test, node) then
                    collect_result(junit_test, node)
                else
                    local junit_test_id = (node_group.test_suite_name .. "." .. junit_test.name)
                        :gsub("-", ".")
                        :gsub(" ", "")

                    local test_id = node.id:gsub("-", "."):gsub(" ", "")

                    if junit_test_id == test_id then
                        collect_result(junit_test, node)
                    end
                end

                -- vim.print(junit_test_id)
                -- vim.print(test_id)
            end
        end
    end

    -- local success, lines = pcall(lib.files.read_lines, result.output)
    -- if not success or not framework then
    --     return {}
    -- end
    --
    -- local results = framework.get_test_results(lines)
    --
    -- return get_results(tree, results, framework.match_func)

    -- vim.print(vim.inspect(test_results))

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
