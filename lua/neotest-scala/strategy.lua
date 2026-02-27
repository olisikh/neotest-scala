local utils = require("neotest-scala.utils")
local fw = require("neotest-scala.framework")

local M = {}
local did_notify_test_fallback = false
local TEST_FALLBACK_MESSAGE = "neotest-scala: DAP nearest test is running at file scope for reliability."

local function notify_test_fallback()
    if vim.in_fast_event and vim.in_fast_event() then
        vim.schedule(function()
            vim.notify(TEST_FALLBACK_MESSAGE, vim.log.levels.INFO)
        end)
        return
    end

    vim.notify(TEST_FALLBACK_MESSAGE, vim.log.levels.INFO)
end

---@param file_path string
---@return table|nil
local function build_test_file_config(file_path)
    if not file_path then
        return nil
    end

    return {
        type = "scala",
        request = "launch",
        name = "Run Test",
        metals = {
            runType = "testFile",
            path = vim.uri_from_fname(file_path),
        },
    }
end

---@param position neotest.Position
---@return boolean
local function is_safe_literal_test_name(position)
    if position.type ~= "test" or type(position.name) ~= "string" then
        return false
    end

    return not utils.is_interpolated_string(position.name)
end

---@param tree neotest.Tree
---@return neotest.Tree|nil, neotest.Tree|nil
local function resolve_top_level_test_node(tree)
    local current = tree

    while current do
        local parent = current:parent()
        if not parent then
            return nil, nil
        end

        local parent_data = parent:data()
        if parent_data.type == "test" then
            current = parent
        elseif parent_data.type == "namespace" then
            return current, parent
        else
            return nil, nil
        end
    end

    return nil, nil
end

---@param opts neotest-scala.StrategyGetConfigOpts
---@return table|nil
local function build_test_selector_config(opts)
    if not fw.supports_dap_test_selector(opts.framework) then
        return nil
    end

    local tree = opts.tree
    local position = tree:data()
    if not is_safe_literal_test_name(position) then
        return nil
    end

    local framework_class = fw.get_framework_class(opts.framework)
    if not framework_class or type(framework_class.build_dap_test_selector) ~= "function" then
        return nil
    end

    local selector_tree, namespace_node = resolve_top_level_test_node(tree)
    if not selector_tree or not namespace_node then
        return nil
    end

    local selector_position = selector_tree:data()
    if not is_safe_literal_test_name(selector_position) then
        return nil
    end

    local selector = framework_class.build_dap_test_selector({
        tree = selector_tree,
        position = selector_position,
    })
    if not selector or selector == "" then
        return nil
    end

    local namespace_data = namespace_node:data()
    local package_name = utils.get_package_name(namespace_data.path) or ""
    local class_name = package_name .. namespace_data.name

    return {
        type = "scala",
        request = "launch",
        name = "from_lens",
        metals = {
            target = { uri = "file:" .. opts.root .. "/?id=" .. opts.project .. "-test" },
            requestData = {
                suites = {
                    {
                        className = class_name,
                        tests = { selector },
                    },
                },
                jvmOptions = {},
                environmentVariables = {},
            },
        },
    }
end

---@class neotest-scala.StrategyGetConfigOpts
---@field strategy string|nil
---@field tree neotest.Tree
---@field project string
---@field root string
---@field framework string|nil
---@field build_tool "bloop"|"sbt"|nil
---@field strict_test_selectors boolean|nil

---@param opts neotest-scala.StrategyGetConfigOpts
---@return table|nil
function M.get_config(opts)
    local strategy = opts.strategy
    local tree = opts.tree
    local project = opts.project
    local root = opts.root
    local position = tree:data()
    if strategy ~= "dap" then
        return nil
    end

    if position.type == "dir" then
        return nil
    end

    if position.type == "file" then
        return build_test_file_config(position.path)
    end

    if position.type == "namespace" then
        local package_name = utils.get_package_name(position.path) or ""
        return {
            type = "scala",
            request = "launch",
            name = "from_lens",
            metals = {
                testClass = package_name .. position.name,
            },
        }
    end

    if position.type == "test" then
        if opts.strict_test_selectors == true then
            local selector_config = build_test_selector_config({
                strategy = strategy,
                tree = tree,
                project = project,
                root = root,
                framework = opts.framework,
                build_tool = opts.build_tool,
            })
            if selector_config then
                return selector_config
            end
        end

        if not did_notify_test_fallback then
            did_notify_test_fallback = true
            notify_test_fallback()
        end

        return build_test_file_config(position.path)
    end

    return nil
end

function M.reset_run_state()
    did_notify_test_fallback = false
end

return M
