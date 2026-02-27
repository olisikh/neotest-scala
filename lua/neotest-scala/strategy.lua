local utils = require("neotest-scala.utils")

local M = {}
local did_notify_test_fallback = false

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
        if not did_notify_test_fallback then
            did_notify_test_fallback = true
            vim.notify(
                "neotest-scala: DAP nearest test is running at file scope for reliability.",
                vim.log.levels.INFO
            )
        end
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
