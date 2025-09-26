local M = {}
local logger = require('todo-ai.logger')

-- Provider registry
M.providers = {}

-- Register all providers
function M.setup()
  M.providers.claude = require('todo-ai.providers.claude')
  M.providers.ollama = require('todo-ai.providers.ollama')
  M.providers.openai = require('todo-ai.providers.openai')
end

-- Get provider by name
function M.get(name)
  return M.providers[name]
end

-- Make HTTP request using curl
function M.request(url, opts)
  opts = opts or {}
  local method = opts.method or 'POST'
  local headers = opts.headers or {}
  local body = opts.body
  local timeout = opts.timeout or 30

  -- Build curl command
  local cmd = {'curl', '-s', '-X', method, url}

  -- Add timeout
  table.insert(cmd, '--max-time')
  table.insert(cmd, tostring(timeout))

  -- Add headers
  for k, v in pairs(headers) do
    table.insert(cmd, '-H')
    table.insert(cmd, string.format('%s: %s', k, v))
  end

  -- Add body if present
  if body then
    table.insert(cmd, '-d')
    table.insert(cmd, body)
  end

  -- Log the request
  logger.debug('HTTP Request', {
    url = url,
    method = method,
    headers = headers,
    body = body and #body > 1000 and (body:sub(1, 1000) .. '...') or body
  })

  -- Execute curl command
  local result = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    logger.error('Request failed', { exit_code = exit_code, result = result })
    return nil, 'Request failed: ' .. result
  end

  -- Log raw response
  logger.debug('HTTP Response', {
    status = 'success',
    response = result and #result > 1000 and (result:sub(1, 1000) .. '...') or result
  })

  -- Parse JSON response
  local ok, data = pcall(vim.fn.json_decode, result)
  if not ok then
    logger.error('Failed to parse JSON', { error = data, response = result })
    return nil, 'Failed to parse response: ' .. result
  end

  return data, nil
end

-- Async HTTP request using jobstart
function M.request_async(url, opts, callback)
  opts = opts or {}
  local method = opts.method or 'POST'
  local headers = opts.headers or {}
  local body = opts.body
  local timeout = opts.timeout or 30

  -- Build curl command
  local cmd = {'curl', '-s', '-X', method, url}

  -- Add timeout
  table.insert(cmd, '--max-time')
  table.insert(cmd, tostring(timeout))

  -- Add headers
  for k, v in pairs(headers) do
    table.insert(cmd, '-H')
    table.insert(cmd, string.format('%s: %s', k, v))
  end

  -- Add body if present
  if body then
    table.insert(cmd, '-d')
    table.insert(cmd, body)
  end

  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          table.insert(stdout, line)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        local error_msg = table.concat(stderr, '\n')
        logger.error('Async request failed', { exit_code = code, stderr = error_msg })
        callback(nil, 'Request failed: ' .. error_msg)
        return
      end

      local response = table.concat(stdout, '\n')

      -- Log response
      logger.debug('Async HTTP Response', {
        status = 'success',
        response = response and #response > 1000 and (response:sub(1, 1000) .. '...') or response
      })

      local ok, data = pcall(vim.fn.json_decode, response)
      if not ok then
        logger.error('Failed to parse async JSON', { error = data, response = response })
        callback(nil, 'Failed to parse response: ' .. response)
        return
      end

      callback(data, nil)
    end
  })
end

return M