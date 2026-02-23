local utils = require("neotest-scala.utils")

local M = {}

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
    local project = opts.project
    local root = opts.root
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
                        className = utils.get_package_name(parent_data.path) .. parent_data.name,
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

return M
