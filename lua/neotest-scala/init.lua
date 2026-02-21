local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local metals = require("neotest-scala.metals")
local build = require("neotest-scala.build")
local textspec = require("neotest-scala.framework.specs2.textspec")
local strategy = require("neotest-scala.strategy")
local results = require("neotest-scala.results")

---@type neotest.Adapter
local adapter = { name = "neotest-scala" }

adapter.root = lib.files.match_root_pattern("build.sbt")

local function get_args(_, _, _, _)
    return {}
end

local cache_build_info = true

---@param position neotest.Position
---@param parents neotest.Position[]
---@return string
local function build_position_id(position, parents)
    local result = {}

    for _, parent in ipairs(parents) do
        if parent.type == "namespace" then
            table.insert(result, utils.get_package_name(parent.path) .. parent.name)
        elseif parent.type ~= "dir" and parent.type ~= "file" then
            table.insert(result, utils.get_position_name(parent))
        end
    end

    table.insert(result, utils.get_position_name(position))

    return table.concat(result, ".")
end

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

---@async
---@param name string
---@param rel_path string
---@param root string
---@return boolean
function adapter.filter_dir(_, _, _)
    return true
end

---@async
---@param path string
---@return neotest.Tree | nil
function adapter.discover_positions(path)
    local content = lib.files.read(path)

    if textspec.is_textspec(content) then
        return textspec.discover_positions(path, content)
    end

    local query = [[
      (object_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      (class_definition
        name: (identifier) @namespace.name
      ) @namespace.definition

      ((call_expression
        function: (call_expression
        function: (identifier) @func_name (#any-of? @func_name "test" "suite" "suiteAll")
        arguments: (arguments (string) @test.name))
      )) @test.definition

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

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function adapter.build_spec(args)
    local position = args.tree:data()
    local root_path = adapter.root(position.path)
    assert(root_path, "[neotest-scala]: Can't resolve root project folder")

    local build_target_info = metals.get_build_target_info(root_path, position.path, cache_build_info)
    if not build_target_info then
        vim.print("[neotest-scala]: Can't resolve project, has Metals initialised? Please try again.")
        return {}
    end

    local project_name = metals.get_project_name(build_target_info)
    if not project_name then
        vim.print("[neotest-scala]: Can't resolve project name")
        return {}
    end

    local framework = metals.get_framework(build_target_info)
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
    local strategy_config = strategy.get_config(args.strategy, args.tree, project_name, root_path)

    return {
        command = command,
        strategy = strategy_config,
        cwd = root_path,
        env = {
            root_path = root_path,
            build_target_info = build_target_info,
            project_name = project_name,
            framework = framework,
        },
    }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param node neotest.Tree
---@return table<string, neotest.Result>
function adapter.results(spec, result, node)
    return results.collect(spec, result, node)
end

local function is_callable(obj)
    return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

setmetatable(adapter, {
    __call = function(_, opts)
        opts = opts or {}

        cache_build_info = opts.cache_build_info ~= false

        metals.setup()

        build.setup({
            build_tool = opts.build_tool,
            compile_on_save = opts.compile_on_save,
        })

        local root = adapter.root(vim.fn.getcwd())

        if root then
            -- Prefetch build info when Scala files are opened
            vim.api.nvim_create_autocmd("BufReadPost", {
                pattern = "*.scala",
                callback = function(args)
                    local buf_path = args.file
                    local buf_root = adapter.root(buf_path)
                    if buf_root == root then
                        metals.prefetch(root, buf_path, cache_build_info)
                    end
                end,
                group = vim.api.nvim_create_augroup("neotest-scala-prefetch", { clear = true }),
            })
        end

        if opts.compile_on_save then
            if root then
                build.setup_compile_on_save(root, function(r, p)
                    return metals.get_build_target_info(r, p, cache_build_info)
                end)
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
