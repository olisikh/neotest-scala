local nio = require("nio")

local M = {}

local cache = {}
local cache_timestamp = {}
local in_flight = {}
local running_tasks = {}
local handler_registered = false

local CACHE_TTL = 60

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

local function get_cache_key(root_path, target_path)
    return root_path .. ":" .. target_path
end

local function is_cache_valid(key)
    local timestamp = cache_timestamp[key]
    if not timestamp then
        return false
    end
    return (os.time() - timestamp) < CACHE_TTL
end

local function do_get_build_target_info(root_path, target_path, timeout_ms)
    timeout_ms = timeout_ms or 10000

    local metals = nio.lsp.get_clients({ name = "metals" })[1]
    if not metals then
        return nil
    end

    local err, targets_result = metals.request.workspace_executeCommand({
        command = "metals.list-build-targets",
    })

    if err or not targets_result or #targets_result == 0 then
        vim.schedule(function()
            vim.print("[neotest-scala]: Metals returned no build targets")
        end)
        return nil
    end

    if #targets_result == 1 then
        local project = targets_result[1]
        local metals_uri = string.format("metalsDecode:file://%s/%s.metals-buildtarget", root_path, project)

        local decode_err, decode_result = metals.request.workspace_executeCommand({
            command = "metals.file-decode",
            arguments = { metals_uri },
        })

        if decode_err or not decode_result or not decode_result.value then
            return nil
        end

        return parse_build_target_info(decode_result.value)
    end

    local target_src_path = target_path:gsub("%*$", "")

    for _, project in ipairs(targets_result) do
        local metals_uri = string.format("metalsDecode:file://%s/%s.metals-buildtarget", root_path, project)

        local decode_err, decode_result = metals.request.workspace_executeCommand({
            command = "metals.file-decode",
            arguments = { metals_uri },
        })

        if not decode_err and decode_result and decode_result.value then
            local project_info = parse_build_target_info(decode_result.value)

            if project_info and project_info["Sources"] then
                for _, src_path in ipairs(project_info["Sources"]) do
                    src_path = src_path:gsub("%*$", "")

                    if vim.startswith(target_src_path, src_path) then
                        return project_info
                    end
                end
            end
        end
    end

    return nil
end

function M.get_build_target_info(root_path, target_path, cache_enabled, timeout_ms)
    local key = get_cache_key(root_path, target_path)

    if cache_enabled and is_cache_valid(key) and cache[key] ~= nil then
        return cache[key]
    end

    if in_flight[key] then
        return in_flight[key].wait()
    end

    local future = nio.create(function()
        local result = do_get_build_target_info(root_path, target_path, timeout_ms)

        if cache_enabled and result then
            cache[key] = result
            cache_timestamp[key] = os.time()
        end

        in_flight[key] = nil
        return result
    end)

    in_flight[key] = future

    return future()
end

function M.invalidate_cache(root_path)
    if root_path then
        for k, _ in pairs(cache) do
            if vim.startswith(k, root_path) then
                cache[k] = nil
                cache_timestamp[k] = nil
            end
        end
    else
        cache = {}
        cache_timestamp = {}
    end
end

function M.get_project_name(build_target_info)
    if build_target_info and build_target_info["Target"] then
        return (build_target_info["Target"][1]:gsub("-test$", ""))
    end
    return nil
end

function M.get_framework(build_target_info)
    if not build_target_info then
        return "scalatest"
    end

    local classpath = build_target_info["Scala Classpath"] or build_target_info["Classpath"]
    if not classpath then
        return "scalatest"
    end

    for _, jar in ipairs(classpath) do
        local framework = jar:match("(specs2)-core_.*-.*%.jar")
            or jar:match("(munit)_.*-.*%.jar")
            or jar:match("(scalatest)_.*-.*%.jar")
            or jar:match("(utest)_.*-.*%.jar")
            or jar:match("(zio%%-test)_.*-.*%.jar")

        if framework then
            return framework
        end
    end

    return "scalatest"
end

local FRAMEWORK_PATTERNS = {
    { pattern = "specs2%-core_.*-.*%.jar", name = "specs2" },
    { pattern = "munit_.*-.*%.jar", name = "munit" },
    { pattern = "scalatest_.*-.*%.jar", name = "scalatest" },
    { pattern = "utest_.*-.*%.jar", name = "utest" },
    { pattern = "zio%-test_.*-.*%.jar", name = "zio-test" },
}

function M.get_frameworks(root_path, target_path, cache_enabled)
    local build_info = M.get_build_target_info(root_path, target_path, cache_enabled)
    if not build_info then
        return {}
    end

    local classpath = build_info["Scala Classpath"] or build_info["Classpath"]
    if not classpath then
        return {}
    end

    local frameworks = {}
    local found = {}

    for _, jar in ipairs(classpath) do
        for _, fw in ipairs(FRAMEWORK_PATTERNS) do
            if jar:match(fw.pattern) and not found[fw.name] then
                table.insert(frameworks, fw.name)
                found[fw.name] = true
            end
        end
    end

    return frameworks
end

function M.prefetch(root_path, file_path, cache_enabled)
    if not cache_enabled then
        return
    end

    local key = get_cache_key(root_path, file_path)

    if cache[key] ~= nil or in_flight[key] then
        return
    end

    local future = nio.create(function()
        local result = do_get_build_target_info(root_path, file_path, 10000)

        if result then
            cache[key] = result
            cache_timestamp[key] = os.time()
        end

        in_flight[key] = nil
        running_tasks[key] = nil
        return result
    end)

    in_flight[key] = future
    running_tasks[key] = nio.run(future)
end

function M.cleanup()
    for key, task in pairs(running_tasks) do
        if task and task.cancel then
            pcall(function() task:cancel() end)
        end
    end
    running_tasks = {}

    in_flight = {}
    cache = {}
    cache_timestamp = {}

    if handler_registered then
        vim.lsp.handlers["metals/buildTargetChanged"] = nil
        handler_registered = false
    end
end

local function register_lsp_handler()
    if handler_registered then
        return
    end

    pcall(function()
        vim.lsp.handlers["metals/buildTargetChanged"] = function(_, result, ctx)
            if not result then
                return
            end

            vim.schedule(function()
                local client = vim.lsp.get_client_by_id(ctx.client_id)
                if client then
                    local root_path = client.config.root_dir
                    if root_path then
                        M.invalidate_cache(root_path)
                    end
                end
            end)
        end
    end)
    handler_registered = true
end

function M.setup()
    register_lsp_handler()
end

return M
