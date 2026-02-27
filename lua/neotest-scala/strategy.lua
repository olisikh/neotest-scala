local utils = require("neotest-scala.utils")

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
---@return table
local function build_test_file_config(file_path)
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

---@class neotest-scala.StrategyGetConfigOpts
---@field strategy string|nil
---@field tree neotest.Tree
---@field project string
---@field root string

---@param opts neotest-scala.StrategyGetConfigOpts
---@return table|nil
function M.get_config(opts)
    local strategy = opts.strategy
    local tree = opts.tree
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

    local metals_args = nil
    if position.type == "namespace" then
        metals_args = {
            testClass = utils.get_package_name(position.path) .. position.name,
        }
    end

    if position.type == "test" then
        if not did_notify_test_fallback then
            did_notify_test_fallback = true
            notify_test_fallback()
        end
        return build_test_file_config(position.path)
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

function M.reset_run_state()
    did_notify_test_fallback = false
end

return M
