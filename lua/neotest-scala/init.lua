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

---@param file_content string
---@return boolean
local function is_specs2_textspec(file_content)
    return file_content:match('s2"""') ~= nil
end

---@param content string The file content
---@return table[] Array of {name=string, path=string, ref=string, line=number}
local function parse_specs2_textspec(content)
    local tests = {}
    local parent_sections = {}

    local s2_start = content:find('s2"""')
    if not s2_start then
        return tests
    end

    local search_start = s2_start + 5
    local s2_end = content:find('"""', search_start)
    if not s2_end then
        return tests
    end

    local spec_string = content:sub(s2_start + 5, s2_end - 1)
    local base_line = 1
    local before_s2 = content:sub(1, s2_start)
    for _ in before_s2:gmatch("\n") do
        base_line = base_line + 1
    end

    local current_line = base_line

    for line in spec_string:gmatch("([^\n]*)\n?") do
        current_line = current_line + 1
        local indent = #line:match("^%s*")
        local trimmed = line:match("^%s*(.-)%s*$")

        if trimmed and #trimmed > 0 then
            local has_ref = trimmed:match("%$([%w_]+)")
            local text_before_ref = trimmed:match("^([^$]+)")

            if text_before_ref then
                text_before_ref = text_before_ref:match("^%s*(.-)%s*$")
            end

            if has_ref and text_before_ref and #text_before_ref > 0 then
                while #parent_sections > 0 and parent_sections[#parent_sections].indent >= indent do
                    table.remove(parent_sections)
                end

                local path_parts = {}
                for _, section in ipairs(parent_sections) do
                    if section.text and #section.text > 0 then
                        table.insert(path_parts, section.text)
                    end
                end
                table.insert(path_parts, text_before_ref)
                local full_path = table.concat(path_parts, "::")

                table.insert(tests, {
                    name = text_before_ref,
                    path = full_path,
                    ref = has_ref,
                    line = current_line,
                })
            elseif not has_ref and #trimmed > 0 then
                while #parent_sections > 0 and parent_sections[#parent_sections].indent >= indent do
                    table.remove(parent_sections)
                end
                if trimmed and #trimmed > 0 then
                    table.insert(parent_sections, { text = trimmed, indent = indent })
                end
            end
        end
    end

    return tests
end

---Find method definition line for a specs2 TextSpec reference
---@param content string The file content
---@param ref string The method reference (e.g., "e1")
---@return number|nil The line number of the method definition
local function find_textspec_method_line(content, ref)
    local pattern = "def%s+" .. ref .. "%s*="
    local start = content:find(pattern)
    if not start then
        return nil
    end
    local line = 1
    for _ in content:sub(1, start):gmatch("\n") do
        line = line + 1
    end
    return line
end

---Discover positions for specs2 TextSpec files
---@param path string
---@param content string
---@return neotest.Tree|nil
local function discover_textspec_positions(path, content)
    local tests = parse_specs2_textspec(content)
    if #tests == 0 then
        return nil
    end

    local class_match = content:match("class%s+([%w_]+)%s+extends")
    if not class_match then
        return nil
    end

    local package_match = content:match("package%s+([%w%.]+)")

    local class_start = content:find("class%s+" .. class_match)
    local class_line = 1
    for _ in content:sub(1, class_start):gmatch("\n") do
        class_line = class_line + 1
    end

    local test_positions = {}
    local last_method_line = class_line

    for _, test in ipairs(tests) do
        local method_line = find_textspec_method_line(content, test.ref)
        if method_line then
            if method_line > last_method_line then
                last_method_line = method_line
            end
            table.insert(test_positions, {
                name = test.name,
                type = "test",
                path = path,
                range = { method_line - 1, 0, method_line - 1, #test.name },
                extra = { textspec_path = test.path },
            })
        end
    end

    if #test_positions == 0 then
        return nil
    end

    local total_lines = 1
    for _ in content:gmatch("\n") do
        total_lines = total_lines + 1
    end

    local positions = {
        {
            name = vim.fn.fnamemodify(path, ":t"),
            type = "file",
            path = path,
            range = { 0, 0, total_lines - 1, 0 },
        },
        {
            name = class_match,
            type = "namespace",
            path = path,
            range = { class_line - 1, 0, last_method_line - 1, 0 },
        },
    }

    for _, pos in ipairs(test_positions) do
        table.insert(positions, pos)
    end

    table.sort(positions, function(a, b)
        return a.range[1] < b.range[1]
    end)

    return lib.positions.parse_tree(positions, {
        nested_tests = true,
        require_namespaces = false,
        position_id = function(pos, parents)
            if pos.type == "file" then
                return pos.path
            end
            local parent_names = {}
            for _, p in ipairs(parents) do
                if p.type ~= "file" then
                    table.insert(parent_names, p.name)
                end
            end
            if pos.type == "namespace" then
                local pkg = package_match and (package_match .. ".") or ""
                return pkg .. pos.name
            end
            local pkg = package_match and (package_match .. ".") or ""
            local ns_name = #parent_names > 0 and parent_names[1] or ""
            return pkg .. ns_name .. "." .. pos.name
        end,
    })
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

--- Flatten table (replacement for deprecated vim.tbl_flatten)
---@param tbl table
---@return table
local function flatten(tbl)
    local result = {}
    for _, v in ipairs(tbl) do
        if type(v) == "table" then
            for _, item in ipairs(v) do
                table.insert(result, item)
            end
        else
            table.insert(result, v)
        end
    end
    return result
end

---@param position neotest.Position The position to return an ID for
---@param parents neotest.Position[] Parent positions for the position
---@return string
local function build_position_id(position, parents)
    return table.concat(
        flatten({
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
    local content = lib.files.read(path)

    if is_specs2_textspec(content) then
        return discover_textspec_positions(path, content)
    end

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
---@param root string
---@return table|nil
local function get_strategy_config(strategy, tree, project, root)
    local position = tree:data()
    if strategy == "integrated" then
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
        local parent = tree:parent()
        if not parent then
            return nil
        end
        local parent_data = parent:data()

        metals_args = {
            target = { uri = "file:" .. root .. "/?id=" .. project .. "-test" },
            requestData = {
                suites = {
                    {
                        className = get_parent_name(parent_data),
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
    local command = framework_class.build_command(root_path, project_name, args.tree, test_name, extra_args)
    local strategy = get_strategy_config(args.strategy, args.tree, project_name, root_path)

    local build_tool = utils.get_build_tool(root_path)
    -- vim.print("[neotest-scala] Running tests with " .. build_tool .. ": " .. vim.inspect(command))

    return {
        command = command,
        strategy = strategy,
        cwd = root_path,
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

    local namespace = {
        path = path,
        namespace = id,
        report_path = report_prefix .. "TEST-" .. id .. ".xml",
        tests = {},
    }

    for _, n in node:iter_nodes() do
        if n:data().type == "test" then
            table.insert(namespace["tests"], n)
        end
    end

    return namespace
end

local function match_test(namespace, junit_result, position)
    local junit_test_id = (namespace.namespace .. "." .. junit_result.name):gsub("-", "."):gsub(" ", "")
    local test_id = position.id:gsub("-", "."):gsub(" ", "")

    return junit_test_id == test_id
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param node neotest.Tree
---@return table<string, neotest.Result>
function adapter.results(spec, result, node)
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

        for _, test in ipairs(ns.tests) do
            local position = test:data()
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
            end
            -- Don't return results for tests without JUnit results
            -- Let neotest handle missing results via _missing_results
        end
    end

    return test_results
end

local function is_callable(obj)
    return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

setmetatable(adapter, {
    __call = function(_, opts)
        opts = opts or {}

        -- Initialize utils with configuration
        utils.setup({
            build_tool = opts.build_tool,
            compile_on_save = opts.compile_on_save,
            cache_build_info = opts.cache_build_info,
        })

        -- Setup compile on save if enabled
        if opts.compile_on_save then
            local root = adapter.root(vim.fn.getcwd())
            if root then
                utils.setup_compile_on_save(root)
            end
        end

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
