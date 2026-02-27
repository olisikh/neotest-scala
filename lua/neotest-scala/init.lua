local lib = require("neotest.lib")
local fw = require("neotest-scala.framework")
local utils = require("neotest-scala.utils")
local metals = require("neotest-scala.metals")
local build = require("neotest-scala.build")
local strategy = require("neotest-scala.strategy")
local results = require("neotest-scala.results")

---@class neotest-scala.AdapterArgsContext
---@field path string
---@field build_target_info table<string, string[]>
---@field project_name string
---@field framework string

---@class neotest-scala.AdapterSetupOpts
---@field cache_build_info? boolean
---@field build_tool? "auto"|"bloop"|"sbt"
---@field args? string[]|fun(context: neotest-scala.AdapterArgsContext): string[]

---@type neotest.Adapter
local adapter = { name = "neotest-scala" }

adapter.root = lib.files.match_root_pattern("build.sbt")

---This is a placeholder for the args function,
---it will be overridden by passing a function or a table to the adapter setup opts.
---The function receives an object with the path of the test file, build target info, project name and framework,
---and should return an array of strings with extra arguments to pass to the test command.
---@param _ neotest-scala.AdapterArgsContext
---@return string[]
local function get_args(_)
    return {}
end

local cache_build_info = true

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
    local root = adapter.root(path)

    if not root then
        return {}
    end

    local frameworks = metals.get_frameworks(root, path, cache_build_info)
    if not frameworks or #frameworks == 0 then
        return {}
    end

    local tree = fw.select_framework_tree({
        frameworks = frameworks,
        path = path,
        content = content,
    })
    if not tree then
        return {}
    end

    return tree
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function adapter.build_spec(args)
    local position = args.tree:data()
    local root_path = adapter.root(position.path)
    assert(root_path, "[neotest-scala]: Can't resolve root project folder")

    local build_target_info = metals.get_build_target_info({
        root_path = root_path,
        target_path = position.path,
        cache_enabled = cache_build_info,
    })

    if build.is_auto_mode() and cache_build_info then
        local fresh_build_target_info = metals.get_build_target_info({
            root_path = root_path,
            target_path = position.path,
            cache_enabled = false,
        })

        if fresh_build_target_info then
            build_target_info = fresh_build_target_info
        end
    end

    if not build_target_info then
        vim.print("[neotest-scala]: Metals returned no build information, try again later")
        return {}
    end

    local project_name = metals.get_project_name(build_target_info)
    if not project_name then
        vim.print("[neotest-scala]: Can't resolve project name")
        return {}
    end

    local framework = nil
    if position.extra and position.extra.framework then
        framework = position.extra.framework
    else
        if lib.files and type(lib.files.read) == "function" then
            local ok, source_content = pcall(lib.files.read, position.path)
            if ok and source_content then
                local frameworks = metals.get_frameworks(root_path, position.path, cache_build_info)
                local _, selected_framework = fw.select_framework_tree({
                    frameworks = frameworks or {},
                    path = position.path,
                    content = source_content,
                })
                framework = selected_framework
            end
        end

        framework = framework or metals.get_framework(build_target_info)
    end

    if not framework then
        vim.print("[neotest-scala]: Failed to detect testing library based on classpath")
        return {}
    end

    local framework_class = fw.get_framework_class(framework)
    if not framework_class then
        return {}
    end

    local build_tool = build.get_tool(root_path, build_target_info)
    build_tool = build.enforce_framework_tool(build_tool, framework)

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
    local command = framework_class.build_command({
        root_path = root_path,
        project = project_name,
        tree = args.tree,
        name = test_name,
        extra_args = extra_args,
        build_tool = build_tool,
    })
    if strategy.reset_run_state then
        strategy.reset_run_state()
    end
    local strategy_config = strategy.get_config({
        strategy = args.strategy,
        tree = args.tree,
        project = project_name,
        root = root_path,
        framework = framework,
        build_tool = build_tool,
    })

    return {
        command = command,
        strategy = strategy_config,
        cwd = root_path,
        env = {
            root_path = root_path,
            build_target_info = build_target_info,
            project_name = project_name,
            framework = framework,
            build_tool = build_tool,
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
    ---@param _ table
    ---@param opts neotest-scala.AdapterSetupOpts|nil
    ---@return neotest.Adapter
    __call = function(_, opts)
        opts = opts or {}

        cache_build_info = opts.cache_build_info ~= false

        metals.setup()

        build.setup({
            build_tool = opts.build_tool,
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
