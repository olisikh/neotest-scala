local utils = require("neotest-scala.utils")

local M = {}

--TODO: is there a way to get project names asynchronously and cache the result?
---Get first project name from bloop projects.
---@return string|nil
function M.get_bloop_project_name_sync()
    local command = "bloop projects"
    local handle = assert(io.popen(command), string.format("[neotest-scala]: unable to execute: [%s]", command))
    local result = handle:read("*l")
    handle:close()
    return result
end

-- TODO: is there a reliable way to cache this?
function M.get_sbt_project_name_sync()
    local command = "sbt projects"
    local handle = assert(io.popen(command), string.format("[neotest-scala]: unable to execute: [%s]", command))
    local last_line = nil
    for line in handle:lines() do
        last_line = line
    end
    handle:close()

    if last_line ~= nil then
        local active_project = vim.trim(utils.strip_sbt_log_prefix(last_line))
        return active_project:match("^%*%s(.*)$")
    end

    return nil
end

return M
