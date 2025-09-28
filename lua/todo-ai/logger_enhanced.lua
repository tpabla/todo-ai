---@class LoggerEnhanced
---@field levels table<string, number>
---@field config LoggerConfig
---@field file_handle file*|nil
---@field buffer table[]
local M = {}

---@class LoggerConfig
---@field level string
---@field file string
---@field max_file_size number
---@field buffer_size number
---@field structured boolean

-- Log levels
M.levels = {
  DEBUG = 10,
  INFO = 20,
  WARN = 30,
  ERROR = 40,
  CRITICAL = 50,
}

-- Default configuration
M.config = {
  level = 'INFO',
  file = '/tmp/todo-ai.log',
  max_file_size = 10 * 1024 * 1024,  -- 10MB
  buffer_size = 100,
  structured = true,
  enable_vim_notify = true,
}

-- State
M.file_handle = nil
M.buffer = {}
M.stats = {
  total_logs = 0,
  by_level = {},
  errors = 0,
}

---Initialize logger
---@param config table|nil
function M.init(config)
  if config then
    M.config = vim.tbl_extend('force', M.config, config)
  end

  -- Load config from config manager
  local ok, config_mgr = pcall(require, 'todo-ai.config_manager')
  if ok then
    M.config.level = config_mgr.get('log_level') or M.config.level
    M.config.file = config_mgr.get('log_file') or M.config.file
  end

  -- Ensure log directory exists
  local dir = vim.fn.fnamemodify(M.config.file, ':h')
  vim.fn.mkdir(dir, 'p')

  -- Open log file
  M.open_log_file()

  -- Set up periodic flush
  vim.fn.timer_start(5000, function()
    M.flush()
  end, {['repeat'] = -1})

  -- Log startup
  M.info("logger.init", {
    level = M.config.level,
    file = M.config.file,
    pid = vim.fn.getpid(),
    version = vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch,
  })
end

---Open log file
function M.open_log_file()
  -- Check file size and rotate if needed
  if vim.fn.filereadable(M.config.file) == 1 then
    local size = vim.fn.getfsize(M.config.file)
    if size > M.config.max_file_size then
      M.rotate_log()
    end
  end

  -- Open file
  M.file_handle = io.open(M.config.file, 'a')
  if not M.file_handle then
    vim.notify("Failed to open log file: " .. M.config.file, vim.log.levels.WARN)
  end
end

---Rotate log file
function M.rotate_log()
  if M.file_handle then
    M.file_handle:close()
  end

  -- Rename old file
  local timestamp = os.date('%Y%m%d_%H%M%S')
  local backup_file = M.config.file .. '.' .. timestamp

  os.rename(M.config.file, backup_file)

  -- Compress old file if possible
  if vim.fn.executable('gzip') == 1 then
    vim.fn.system({'gzip', backup_file})
  end

  -- Keep only last 5 backups
  local pattern = M.config.file .. '.*'
  local backups = vim.fn.glob(pattern, false, true)
  if #backups > 5 then
    for i = 1, #backups - 5 do
      os.remove(backups[i])
    end
  end
end

---Format log entry
---@param level string
---@param context string
---@param data table|string|nil
---@return string
function M.format_entry(level, context, data)
  local entry = {
    timestamp = os.date('%Y-%m-%d %H:%M:%S'),
    level = level,
    context = context,
    pid = vim.fn.getpid(),
  }

  if M.config.structured then
    -- Structured JSON logging
    if type(data) == 'table' then
      entry.data = data
    elseif data then
      entry.message = tostring(data)
    end

    local ok, json = pcall(vim.fn.json_encode, entry)
    if ok then
      return json
    end
  end

  -- Fallback to text format
  local parts = {
    entry.timestamp,
    string.format('[%s]', level),
    context,
  }

  if data then
    if type(data) == 'table' then
      local ok, json = pcall(vim.fn.json_encode, data)
      if ok then
        table.insert(parts, json)
      else
        table.insert(parts, vim.inspect(data))
      end
    else
      table.insert(parts, tostring(data))
    end
  end

  return table.concat(parts, ' ')
end

---Write log entry
---@param level string
---@param context string
---@param data table|string|nil
function M.write(level, context, data)
  -- Check level
  if M.levels[level] < M.levels[M.config.level] then
    return
  end

  -- Update stats
  M.stats.total_logs = M.stats.total_logs + 1
  M.stats.by_level[level] = (M.stats.by_level[level] or 0) + 1

  -- Format entry
  local entry = M.format_entry(level, context, data)

  -- Add to buffer
  table.insert(M.buffer, entry)

  -- Write immediately for errors
  if level == 'ERROR' or level == 'CRITICAL' then
    M.flush()
    M.stats.errors = M.stats.errors + 1
  elseif #M.buffer >= M.config.buffer_size then
    M.flush()
  end

  -- Also notify in vim for warnings and errors
  if M.config.enable_vim_notify then
    if level == 'ERROR' or level == 'CRITICAL' then
      vim.notify(context .. ': ' .. (type(data) == 'string' and data or ''),
                vim.log.levels.ERROR)
    elseif level == 'WARN' then
      vim.notify(context .. ': ' .. (type(data) == 'string' and data or ''),
                vim.log.levels.WARN)
    end
  end
end

---Flush buffer to file
function M.flush()
  if #M.buffer == 0 then
    return
  end

  if not M.file_handle then
    M.open_log_file()
  end

  if M.file_handle then
    for _, entry in ipairs(M.buffer) do
      M.file_handle:write(entry .. '\n')
    end
    M.file_handle:flush()
  end

  M.buffer = {}
end

---Debug log
---@param context string
---@param data table|string|nil
function M.debug(context, data)
  M.write('DEBUG', context, data)
end

---Info log
---@param context string
---@param data table|string|nil
function M.info(context, data)
  M.write('INFO', context, data)
end

---Warning log
---@param context string
---@param data table|string|nil
function M.warn(context, data)
  M.write('WARN', context, data)
end

---Error log
---@param context string
---@param data table|string|nil
function M.error(context, data)
  M.write('ERROR', context, data)
end

---Critical log
---@param context string
---@param data table|string|nil
function M.critical(context, data)
  M.write('CRITICAL', context, data)
end

---Performance timer
---@param context string
---@return function stop_timer
function M.timer(context)
  local start_time = vim.loop.hrtime()

  return function(data)
    local duration = (vim.loop.hrtime() - start_time) / 1000000  -- Convert to ms

    M.info(context .. '.timer', vim.tbl_extend('force', data or {}, {
      duration_ms = duration,
    }))
  end
end

---Log function entry/exit
---@param fn function
---@param context string
---@return function wrapped
function M.wrap(fn, context)
  return function(...)
    local args = {...}
    M.debug(context .. '.enter', { args = args })

    local start_time = vim.loop.hrtime()
    local results = {pcall(fn, ...)}
    local duration = (vim.loop.hrtime() - start_time) / 1000000

    if results[1] then
      -- Success
      M.debug(context .. '.exit', {
        duration_ms = duration,
        results = {unpack(results, 2)},
      })
      return unpack(results, 2)
    else
      -- Error
      M.error(context .. '.error', {
        duration_ms = duration,
        error = results[2],
        args = args,
      })
      error(results[2])
    end
  end
end

---Get log statistics
---@return table
function M.get_stats()
  return vim.deepcopy(M.stats)
end

---Search logs
---@param pattern string
---@param max_lines number|nil
---@return string[]
function M.search(pattern, max_lines)
  max_lines = max_lines or 100

  if not vim.fn.filereadable(M.config.file) then
    return {}
  end

  local lines = {}
  local file = io.open(M.config.file, 'r')
  if not file then
    return {}
  end

  for line in file:lines() do
    if line:match(pattern) then
      table.insert(lines, line)
      if #lines >= max_lines then
        break
      end
    end
  end

  file:close()
  return lines
end

---View logs in buffer
function M.view()
  -- Flush pending logs
  M.flush()

  -- Open log file in new buffer
  vim.cmd('split ' .. M.config.file)

  -- Set buffer options
  vim.bo.readonly = true
  vim.bo.modifiable = false
  vim.bo.filetype = M.config.structured and 'json' or 'log'

  -- Jump to end
  vim.cmd('normal! G')
end

---Clean up and close
function M.shutdown()
  M.flush()

  if M.file_handle then
    M.file_handle:close()
    M.file_handle = nil
  end

  M.info("logger.shutdown", {
    stats = M.stats,
  })
end

-- Auto-initialize on require
M.init()

-- Set up shutdown hook
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    M.shutdown()
  end,
})

return M