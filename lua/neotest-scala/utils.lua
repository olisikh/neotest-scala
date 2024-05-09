local lib = require("neotest.lib")

local M = {}

--- Strip quotes from the (captured) test position.
---@param position neotest.Position
---@return string
function M.get_position_name(position)
    if position.type == "test" then
        local value = string.gsub(position.name, '"', "")
        return value
    end
    return position.name
end

---Get a package name from the top of the file.
---@return string|nil
function M.get_package_name(file)
    local success, lines = pcall(lib.files.read_lines, file)
    if not success then
        return nil
    end
    local line = lines[1]
    if vim.startswith(line, "package") then
        return vim.split(line, " ")[2] .. "."
    end
    return ""
end

---@param project string
---@param runner string
---@param test_path string|nil
---@param extra_args table|string
---@return string[]
function M.build_command_with_test_path(project, runner, test_path, extra_args)
    if runner == "bloop" then
        local full_test_path
        if not test_path then
            full_test_path = {}
        else
            full_test_path = { "--", test_path }
        end
        return vim.tbl_flatten({ "bloop", "test", extra_args, project, full_test_path })
    end

    if not test_path then
        return vim.tbl_flatten({ "sbt", extra_args, project .. "/test" })
    end

    return vim.tbl_flatten({ "sbt", extra_args, project .. "/testOnly -- " .. '"' .. test_path .. '"' })
end

--- Strip ANSI characters from the string, leaving the rest of the string intact.
---@param s string
---@return string
function M.strip_ansi_chars(s)
    local v = s:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
    return v
end

--- Strip sbt info logging prefix from string.
---@param s string
---@return string
function M.strip_sbt_log_prefix(s)
    local v = s:gsub("^%[info%] ", ""):gsub("^%[error%] ", ""):gsub("^%[debug%]", ""):gsub("^%[warn%] ", "")
    return v
end

function M.strip_bloop_error_prefix(s)
    local v = s:gsub("^%[E%] ", "")
    return v
end

---Returns metals LSP client if metals is active on current buffer
---@param bufnr integer?
---@return vim.lsp.Client?
function M.find_metals(bufnr)
    local clients = vim.lsp.get_clients({ name = "metals", bufnr = bufnr })
    if #clients > 0 then
        return clients[1]
    end
    return nil
end

function M.get_project_name_sync()
    local metals = M.find_metals()
    local project = nil

    if metals then
        local response =
            metals.request_sync("workspace/executeCommand", { command = "metals.list-build-targets" }, 10000, 0)

        if not response or #response.result == 0 then
            vim.print("[neotest-scala]: Metals returned no project name, try again.")
        elseif response.err then
            vim.print("[neotest-scala]: Request to metals failed: " .. response.err.message)
        else
            project = response.result[1]
        end

        return project
    end
end

-- function M.get_project_name(callback)
--     local metals = M.find_metals()
--
--     if metals then
--         metals.request("workspace/executeCommand", { command = "metals.list-build-targets" }, function(err, result, _)
--             if err then
--                 vim.print("[neotest-scala]: Request to metals failed: " .. err.message)
--             elseif #result == 0 then
--                 vim.print("[neotest-scala]: Metals returned no project name, try again.")
--             else
--                 callback(result[1])
--             end
--         end, 0)
--     else
--         vim.print("No metals, no party.")
--     end
-- end

return M
