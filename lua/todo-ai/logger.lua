---@class Logger
local M = {}

M.LOG_FILE = '/tmp/todo-ai.log'
local LOG_FILE = M.LOG_FILE  -- Keep local reference for compatibility
local LOG_LEVELS = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

-- Default log level from config or INFO
local current_level = LOG_LEVELS.INFO

---Initialize logger with config
---@param config table|nil
function M.init(config)
  if config and config.log_level then
    current_level = LOG_LEVELS[config.log_level] or LOG_LEVELS.INFO
  end
end

---Write log entry to file
---@param level string
---@param context string
---@param data any
local function write_log(level, context, data)
  if LOG_LEVELS[level] < current_level then
    return
  end

  local data_str = tostring(data or '')
  if type(data) == 'table' then
    local ok, json = pcall(vim.fn.json_encode, data)
    data_str = ok and json or vim.inspect(data)
  end

  -- Forward to Rust backend if available
  local backend = package.loaded['todo-ai.backend']
  if backend and backend.is_available() then
    pcall(backend.notify, 'log', { level = level, context = context, data = data_str })
    return
  end

  -- Fallback: write to file directly
  local timestamp = os.date('%Y-%m-%d %H:%M:%S')
  local entry = string.format('%s [%s] %s: %s', timestamp, level, context, data_str)

  vim.schedule(function()
    local file = io.open(LOG_FILE, 'a')
    if file then
      file:write(entry .. '\n')
      file:close()
    end
  end)
end

---Debug log
---@param context string
---@param data any
function M.debug(context, data)
  write_log('DEBUG', context, data)
end

---Info log
---@param context string
---@param data any
function M.info(context, data)
  write_log('INFO', context, data)
end

---Warning log
---@param context string
---@param data any
function M.warn(context, data)
  write_log('WARN', context, data)
  if LOG_LEVELS.WARN >= current_level then
    vim.notify(context .. ': ' .. tostring(data or ''), vim.log.levels.WARN)
  end
end

---Error log
---@param context string
---@param data any
function M.error(context, data)
  write_log('ERROR', context, data)
  if LOG_LEVELS.ERROR >= current_level then
    vim.notify(context .. ': ' .. tostring(data or ''), vim.log.levels.ERROR)
  end
end

---Set log level
---@param level string
function M.set_level(level)
  current_level = LOG_LEVELS[level] or LOG_LEVELS.INFO
end

return M