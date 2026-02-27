local root_logger_name = "neotest-scala"
local log_dir = "/tmp/neotest-scala/log"
local dir_initialized = false

local LEVELS = {
    debug = { name = "DEBUG", value = vim.log.levels.DEBUG },
    info = { name = "INFO", value = vim.log.levels.INFO },
    warn = { name = "WARN", value = vim.log.levels.WARN },
    error = { name = "ERROR", value = vim.log.levels.ERROR },
}

local settings = {
    enabled = true,
    level = LEVELS.info.name,
}

local logger = {}

---@param level_name string
---@return table|nil
local function level_from_name(level_name)
    if type(level_name) ~= "string" then
        return nil
    end

    return LEVELS[string.lower(level_name)]
end

---@param opts table|nil
function logger.configure(opts)
    local logging = opts and opts.logging or nil
    if not logging then
        return
    end

    if type(logging.enabled) == "boolean" then
        settings.enabled = logging.enabled
    end

    local selected_level = level_from_name(logging.level)
    if selected_level then
        settings.level = selected_level.name
    end
end

local function ensure_log_dir()
    if dir_initialized then
        return true
    end

    local stat = vim.uv.fs_stat(log_dir)
    if not stat then
        vim.fn.mkdir(log_dir, "p")
    end

    dir_initialized = true
    return true
end

local function get_log_path()
    ensure_log_dir()
    local date = os.date("%Y-%m-%d")
    return string.format("%s/%s.log", log_dir, date)
end

local function flatten_message(message)
    if message == nil then
        return ""
    end

    if type(message) == "table" then
        return vim.inspect(message)
    end

    return tostring(message)
end

---@param name string
---@param level_name string
---@param message any
---@param opts table|nil
local function write_line(name, level_name, message, opts)
    if vim.in_fast_event and vim.in_fast_event() and not (opts and opts._scheduled) then
        local scheduled_opts = {}
        if type(opts) == "table" then
            for key, value in pairs(opts) do
                scheduled_opts[key] = value
            end
        end
        scheduled_opts._scheduled = true

        vim.schedule(function()
            write_line(name, level_name, message, scheduled_opts)
        end)
        return
    end

    if not settings.enabled then
        return
    end

    local message_level = level_from_name(level_name)
    local configured_level = level_from_name(settings.level)
    if not message_level or not configured_level then
        return
    end

    if message_level.value < configured_level.value then
        return
    end

    local path = get_log_path()
    local bufnr = opts and opts.bufnr or nil
    if bufnr == nil then
        local ok, current_buf = pcall(vim.api.nvim_get_current_buf)
        if ok then
            bufnr = current_buf
        else
            bufnr = "unknown"
        end
    end

    local file = opts and opts.file or nil
    if (file == nil or file == "") and type(bufnr) == "number" then
        local ok, buf_name = pcall(vim.api.nvim_buf_get_name, bufnr)
        if ok then
            file = buf_name
        end
    end
    if file == nil or file == "" then
        file = "unknown"
    end

    local text = flatten_message(message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local formatted =
        string.format("%s [%s] (bufnr=%s file=%s) %s - %s\n", timestamp, message_level.name, bufnr, file, name, text)
    local fd = vim.uv.fs_open(path, "a", 420)
    if not fd then
        return
    end

    vim.uv.fs_write(fd, formatted, -1)
    vim.uv.fs_close(fd)
end

---@param name string|nil
---@return table
local function make_logger(name)
    local logger_name = name or root_logger_name
    return {
        name = logger_name,
        debug = function(message, opts)
            write_line(logger_name, LEVELS.debug.name, message, opts)
        end,
        info = function(message, opts)
            write_line(logger_name, LEVELS.info.name, message, opts)
        end,
        warn = function(message, opts)
            write_line(logger_name, LEVELS.warn.name, message, opts)
        end,
        error = function(message, opts)
            write_line(logger_name, LEVELS.error.name, message, opts)
        end,
    }
end

local root_logger = make_logger(root_logger_name)

function logger.new(name)
    return make_logger(name)
end

function logger.debug(message, opts)
    root_logger.debug(message, opts)
end

function logger.info(message, opts)
    root_logger.info(message, opts)
end

function logger.warn(message, opts)
    root_logger.warn(message, opts)
end

function logger.error(message, opts)
    root_logger.error(message, opts)
end

return logger
