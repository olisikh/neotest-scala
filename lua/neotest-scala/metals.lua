local lib = require("neotest.lib")

local M = {}

-- Cache for build target info
local build_target_cache = {}
local cache_timestamp = {}

---Returns Metals LSP client if Metals is active on current buffer
---@param bufnr integer? buffer to look for metals client
---@return vim.lsp.Client?
function M.find_client(bufnr)
    local clients = vim.lsp.get_clients({ name = "metals", bufnr = bufnr })
    if #clients > 0 then
        return clients[1]
    end
    return nil
end

---NOTE: If the format in which metals returns decoded file output changes - this function might start failing
---@param text string
---@return table
local function parse_build_target_info(text)
    local result = {}
    local curr_section = nil

    for line in text:gmatch("[^\r\n]+") do
        local indent, content = line:match("^(%s*)(.*)")
        local indent_lvl = #indent

        if indent_lvl == 0 and content ~= "" then
            curr_section = content
            result[curr_section] = {}
        elseif indent_lvl > 0 and content ~= "" and curr_section then
            table.insert(result[curr_section], (content:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")))
        end
    end

    return result
end

---Get project report from Metals
---@param metals vim.lsp.Client metals client
---@param path string project path (root folder)
---@param project string project name
---@param timeout integer? timeout for the request
---@return table | nil report about the project
local function fetch_build_target_info(metals, path, project, timeout)
    local build_target_info = nil

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
            build_target_info = parse_build_target_info(response.result.value)
        end
    end

    return build_target_info
end

--- Get cache key for build target info
---@param root_path string
---@param target_path string
---@return string
local function get_cache_key(root_path, target_path)
    return root_path .. ":" .. target_path
end

---Get the build target info by listing build targets that Metals has found
---@param root_path string project path where build.sbt is
---@param target_path string path to the file or folder that is being tested
---@param cache_enabled boolean whether to cache results
---@param timeout integer? timeout for the request
---@return table | nil build target info
function M.get_build_target_info(root_path, target_path, cache_enabled, timeout)
    if cache_enabled then
        local cache_key = get_cache_key(root_path, target_path)
        local cached = build_target_cache[cache_key]
        local timestamp = cache_timestamp[cache_key]

        if cached and timestamp and (os.time() - timestamp) < 60 then
            return cached
        end
    end

    local metals = M.find_client()
    local result = nil
    timeout = timeout or 10000

    if metals then
        local body = { command = "metals.list-build-targets" }
        local response = metals.request_sync("workspace/executeCommand", body, timeout, 0)

        if not response or #response.result == 0 then
            vim.print("[neotest-scala]: Metals returned no project name, please try again.")
        elseif response.err then
            vim.print("[neotest-scala]: Request to metals failed: " .. response.err.message)
        else
            if #response.result > 1 then
                local target_src_path = target_path:gsub("%*$", "")

                for _, name in ipairs(response.result) do
                    local build_target_info = fetch_build_target_info(metals, root_path, name, timeout)
                    if build_target_info and build_target_info["Sources"] then
                        for _, src_path in ipairs(build_target_info["Sources"]) do
                            src_path = src_path:gsub("%*$", "")

                            if vim.startswith(target_src_path, src_path) then
                                result = build_target_info
                                break
                            end
                        end
                    end
                end
            else
                result = response.result[1]
            end
        end
    end

    if cache_enabled and result then
        local cache_key = get_cache_key(root_path, target_path)
        build_target_cache[cache_key] = result
        cache_timestamp[cache_key] = os.time()
    end

    return result
end

---Invalidate build target cache
---@param root_path string|nil Optional: invalidate only for this root
function M.invalidate_cache(root_path)
    if root_path then
        for key, _ in pairs(build_target_cache) do
            if vim.startswith(key, root_path) then
                build_target_cache[key] = nil
                cache_timestamp[key] = nil
            end
        end
    else
        build_target_cache = {}
        cache_timestamp = {}
    end
end

---Take build target name and turn it into a module name
---@param build_target_info table
---@return string|nil
function M.get_project_name(build_target_info)
    if build_target_info and build_target_info["Target"] then
        return (build_target_info["Target"][1]:gsub("-test$", ""))
    end
end

---Search for a test library dependency in a test build target
---@param build_target_info table build target info
---@return string name of the test library being used in the project
function M.get_framework(build_target_info)
    local framework = nil

    if build_target_info then
        local classpath = build_target_info["Scala Classpath"] or build_target_info["Classpath"]

        if classpath then
            for _, jar in ipairs(classpath) do
                framework = jar:match("(specs2)-core_.*-.*%.jar")
                    or jar:match("(munit)_.*-.*%.jar")
                    or jar:match("(scalatest)_.*-.*%.jar")
                    or jar:match("(utest)_.*-.*%.jar")
                    or jar:match("(zio%%-test)_.*-.*%.jar")

                if framework then
                    break
                end
            end
        end
    end

    return framework or "scalatest"
end

return M
