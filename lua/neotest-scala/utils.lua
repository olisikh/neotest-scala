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

---Returns Metals LSP client if Metals is active on current buffer
---@param bufnr integer? bunfr to look for metals client
---@return vim.lsp.Client?
function M.find_metals(bufnr)
    local clients = vim.lsp.get_clients({ name = "metals", bufnr = bufnr })
    if #clients > 0 then
        return clients[1]
    end
    return nil
end

-- TODO: Delete me?
function M.inspect_buf(txt)
    vim.cmd([[new]])
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.inspect(txt), "\n"))
end

---Get the first build target name by listing build targets that Metals has found
---@param timeout integer? timeout for the request
---@return string | nil project name (build target) or nil if Metals unavailable or got no response from Metals
function M.get_project_name(timeout)
    local metals = M.find_metals()
    local project = nil

    if metals then
        local response = metals.request_sync(
            "workspace/executeCommand",
            { command = "metals.list-build-targets" },
            timeout or 10000,
            0
        )

        if not response or #response.result == 0 then
            vim.print("[neotest-scala]: Metals returned no project name, please try again.")
        elseif response.err then
            vim.print("[neotest-scala]: Request to metals failed: " .. response.err.message)
        else
            project = response.result[1]
        end
    end

    return project
end

---Get project report, contains information about the project, it's classpath in particular
---@param path string project path (root folder)
---@param project string project name
---@param timeout integer? timeout for the request
---@return string | nil report about the project
function M.build_target_info(path, project, timeout)
    local metals = M.find_metals()

    if metals then
        local metals_uri = string.format("metalsDecode:file://%s/%s.metals-buildtarget", path, project)

        local params = {
            command = "metals.file-decode",
            arguments = { metals_uri },
        }
        local response = metals.request_sync("workspace/executeCommand", params, timeout or 10000, 0)
        if not response or response.err then
            vim.print("[neotest-scala]: Failed to get build target info, please try again")
        else
            return response.result.value
        end
    end

    return nil
end

---Detect which build tool is being used, uses Metals, checking which build tool it has been configured with
---@param path string project path (root folder)
---@param project string project name
---@param timeout integer? timeout for the request
---@return string
function M.detect_build_tool(path, project, timeout)
    local report = M.build_target_info(path, project, timeout)

    if report then
        local lines = vim.tbl_map(vim.trim, vim.split(report, "\n"))
        for _, line in ipairs(lines) do
            if vim.startswith(line, "file://" .. path .. "/.bloop/" .. project) then
                return "bloop"
            end
        end
    end

    return "sbt"
end

---Search for a test library dependency in a test build target
---@param path string project path (root folder)
---@param project string project name
---@param timeout integer? timeout for the request
---@return string name of the test library being used in the project
function M.get_framework(path, project, timeout)
    local report = M.build_target_info(path, project .. "-test", timeout)

    local framework = nil

    if report then
        framework = report:match("(specs2)-core_.*-.*%.jar")
            or report:match("(munit)_.*-.*%.jar")
            or report:match("(scalatest)_.*-.*%.jar")
            or report:match("(utest)_.*-.*%.jar")
    end

    return framework or "scalatest"
end

return M
