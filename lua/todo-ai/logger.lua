local M = {}

M.log_file = '/tmp/todo-ai.log'
M.enabled = true

function M.log(level, message, data)
  if not M.enabled then
    return
  end

  local file = io.open(M.log_file, 'a')
  if not file then
    return
  end

  local timestamp = os.date('%Y-%m-%d %H:%M:%S')
  local log_entry = string.format('[%s] [%s] %s', timestamp, level, message)

  if data then
    log_entry = log_entry .. '\n' .. vim.inspect(data)
  end

  file:write(log_entry .. '\n')
  file:close()
end

function M.debug(message, data)
  M.log('DEBUG', message, data)
end

function M.info(message, data)
  M.log('INFO', message, data)
end

function M.warn(message, data)
  M.log('WARN', message, data)
end

function M.error(message, data)
  M.log('ERROR', message, data)
end

function M.clear()
  local file = io.open(M.log_file, 'w')
  if file then
    file:close()
  end
end

return M