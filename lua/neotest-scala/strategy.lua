local utils = require("neotest-scala.utils")

local M = {}

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

---@class neotest-scala.StrategyGetConfigOpts
---@field strategy string|nil
---@field tree neotest.Tree

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
        return build_test_file_config(position.path)
    end

    return nil
end

return M
