-- Pi coding agent RPC client
-- Spawns pi in RPC mode and communicates via JSON lines on stdin/stdout
local M = {}

M.job = nil
M.read_buffer = ""
M.event_handlers = {}

-- Start pi in RPC mode
function M.start(config)
  if M.job then return end

  if vim.fn.executable('pi') ~= 1 then
    error("pi not found in PATH — install pi coding agent: npm install -g @mariozechner/pi-coding-agent")
  end

  local cmd = { 'pi', '--mode', 'rpc' }

  -- Provider/model
  if config.pi_provider then
    table.insert(cmd, '--provider')
    table.insert(cmd, config.pi_provider)
  end
  if config.pi_model then
    table.insert(cmd, '--model')
    table.insert(cmd, config.pi_model)
  end
  if config.pi_thinking then
    table.insert(cmd, '--thinking')
    table.insert(cmd, config.pi_thinking)
  end

  -- System prompt additions
  if config.pi_system_prompt then
    table.insert(cmd, '--append-system-prompt')
    table.insert(cmd, config.pi_system_prompt)
  end

  -- Extra args
  if config.pi_extra_args then
    for _, arg in ipairs(config.pi_extra_args) do
      table.insert(cmd, arg)
    end
  end

  local logger = require('todo-ai.logger')
  logger.info('pi_client', 'Starting pi: ' .. table.concat(cmd, ' '))

  M.job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      M._on_stdout(data)
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          logger.debug('pi_client', 'stderr: ' .. line)
        end
      end
    end,
    on_exit = function(_, code)
      logger.info('pi_client', 'pi exited with code ' .. code)
      M.job = nil
    end,
    stdin = 'pipe',
  })

  if M.job <= 0 then
    M.job = nil
    error("Failed to start pi")
  end
end

-- Handle stdout data from pi
function M._on_stdout(data)
  for _, chunk in ipairs(data) do
    if chunk == '' then
      -- Empty string = line boundary in nvim job protocol
      if M.read_buffer ~= '' then
        M._dispatch(M.read_buffer)
        M.read_buffer = ''
      end
    else
      -- Could be partial or complete line
      -- Split by newlines in case multiple JSON lines arrive in one chunk
      local lines = vim.split(chunk, '\n', { plain = true })
      for i, line in ipairs(lines) do
        if i < #lines then
          -- Complete line
          local full = M.read_buffer .. line
          M.read_buffer = ''
          if full ~= '' then
            M._dispatch(full)
          end
        else
          -- Last segment might be partial
          M.read_buffer = M.read_buffer .. line
        end
      end
    end
  end
end

-- Dispatch a single JSON event
function M._dispatch(json_str)
  local logger = require('todo-ai.logger')
  local ok, event = pcall(vim.fn.json_decode, json_str)
  if not ok then
    logger.error('pi_client', 'Failed to parse: ' .. json_str:sub(1, 200))
    return
  end

  local event_type = event.type
  if not event_type then return end

  logger.debug('pi_client', 'Event: ' .. event_type)

  -- Call registered handlers
  if M.event_handlers[event_type] then
    for _, handler in ipairs(M.event_handlers[event_type]) do
      vim.schedule(function()
        handler(event)
      end)
    end
  end

  -- Call wildcard handlers
  if M.event_handlers['*'] then
    for _, handler in ipairs(M.event_handlers['*']) do
      vim.schedule(function()
        handler(event)
      end)
    end
  end
end

-- Register an event handler
function M.on(event_type, handler)
  if not M.event_handlers[event_type] then
    M.event_handlers[event_type] = {}
  end
  table.insert(M.event_handlers[event_type], handler)
end

-- Clear all event handlers
function M.clear_handlers()
  M.event_handlers = {}
end

-- Send a command to pi
function M.send(cmd)
  if not M.job then
    error("pi not running")
  end
  local json = vim.fn.json_encode(cmd) .. '\n'
  vim.fn.chansend(M.job, json)
end

-- Send a prompt to pi
function M.prompt(message)
  M.send({ type = 'prompt', message = message })
end

-- Abort current operation
function M.abort()
  if M.job then
    M.send({ type = 'abort' })
  end
end

-- Check if pi is running
function M.is_running()
  return M.job ~= nil
end

-- Stop pi
function M.stop()
  if M.job then
    vim.fn.jobstop(M.job)
    M.job = nil
  end
end

return M
