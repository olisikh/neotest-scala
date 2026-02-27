local logger = require("neotest-scala.logger")

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return ""
  end

  local content = fd:read("*a") or ""
  fd:close()
  return content
end

describe("logger", function()
  local log_path = "/tmp/neotest-scala/log/" .. os.date("%Y-%m-%d") .. ".log"
  local original_in_fast_event
  local original_schedule

  before_each(function()
    original_in_fast_event = vim.in_fast_event
    original_schedule = vim.schedule
    logger.configure({
      logging = {
        enabled = true,
        level = "info",
      },
    })
  end)

  after_each(function()
    vim.in_fast_event = original_in_fast_event
    vim.schedule = original_schedule
  end)

  it("writes info messages when enabled", function()
    local token = "logger-info-" .. tostring(vim.uv.hrtime())
    local scoped = logger.new("logger-spec")

    scoped.info(token, {
      bufnr = 7,
      file = "/tmp/logger_spec.scala",
    })

    local content = read_file(log_path)
    assert.is_not_nil(content:find(token, 1, true))
    assert.is_not_nil(content:find("[INFO]", 1, true))
    assert.is_not_nil(content:find("logger-spec - " .. token, 1, true))
  end)

  it("filters info messages when level is warn", function()
    local token = "logger-filter-" .. tostring(vim.uv.hrtime())
    local scoped = logger.new("logger-spec")

    logger.configure({
      logging = {
        enabled = true,
        level = "warn",
      },
    })

    scoped.info(token, {
      bufnr = 8,
      file = "/tmp/logger_spec.scala",
    })

    local content = read_file(log_path)
    assert.is_nil(content:find(token, 1, true))
  end)

  it("accepts case-insensitive level values", function()
    local token = "logger-warn-" .. tostring(vim.uv.hrtime())
    local scoped = logger.new("logger-spec")

    logger.configure({
      logging = {
        enabled = true,
        level = "WARN",
      },
    })

    scoped.warn(token, {
      bufnr = 9,
      file = "/tmp/logger_spec.scala",
    })

    local content = read_file(log_path)
    assert.is_not_nil(content:find(token, 1, true))
  end)

  it("schedules writes in fast event context", function()
    local token = "logger-fast-" .. tostring(vim.uv.hrtime())
    local scoped = logger.new("logger-spec")

    vim.in_fast_event = function()
      return true
    end
    vim.schedule = function(cb)
      cb()
    end

    scoped.info(token)

    local content = read_file(log_path)
    assert.is_not_nil(content:find(token, 1, true))
  end)
end)
