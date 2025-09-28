---HTTP client using Plenary's curl
---@class HttpClient
local M = {}

local curl = require('plenary.curl')
local retry_manager = require('todo-ai.retry_manager')
local logger = require('todo-ai.logger')
local config = require('todo-ai.config')

---Make HTTP request with Plenary's curl
---@param url string
---@param opts table
---@return table|nil response, string|nil error
function M.request(url, opts)
  opts = opts or {}

  -- Build curl options
  local curl_opts = {
    url = url,
    method = opts.method or 'GET',
    headers = opts.headers or {},
    body = opts.body,
    timeout = opts.timeout or config.get('timeouts').default,
    raw = {'-L', '--max-redirs', '5'},  -- Follow redirects
  }

  -- Use Plenary's curl (synchronous)
  local response = curl.request(curl_opts)

  if response.status >= 200 and response.status < 300 then
    -- Success
    local ok, data = pcall(vim.fn.json_decode, response.body)
    if ok then
      return data, nil
    else
      return response.body, nil  -- Return raw if not JSON
    end
  else
    -- Error
    logger.error('http_client', string.format('Request failed: %d %s', response.status, response.body))
    return nil, string.format('HTTP %d: %s', response.status, response.body)
  end
end

---Make request with retry
---@param url string
---@param opts table
---@return boolean success, any result
function M.request_with_retry(url, opts)
  opts = opts or {}
  local service_name = opts.service_name or 'http'

  return retry_manager.execute_with_retry(
    function()
      local result, err = M.request(url, opts)
      if err then
        error(err)
      end
      return result
    end,
    service_name
  )
end

---Make async request with Plenary's curl
---@param url string
---@param opts table
---@param callback function(response: table|nil, error: string|nil)
function M.request_async(url, opts, callback)
  opts = opts or {}

  -- Log request start
  logger.info('http_client', string.format('Request: %s %s', opts.method or 'GET', url))
  if opts.provider then
    logger.info('http_client', string.format('Provider: %s', opts.provider))
  end
  if opts.body then
    logger.info('http_client', string.format('Body size: %d bytes', #opts.body))
  end

  -- Build curl options
  local curl_opts = {
    url = url,
    method = opts.method or 'GET',
    headers = opts.headers or {},
    body = opts.body,
    timeout = opts.timeout or config.get('timeouts').default,
    callback = function(response)
      vim.schedule(function()
        logger.info('http_client', string.format('Response - Exit: %s, Status: %s',
          tostring(response.exit), tostring(response.status)))

        if response.exit ~= 0 then
          local error_msg = "Curl failed: " .. tostring(response.exit)
          logger.error('http_client', error_msg)
          callback(nil, error_msg)
        elseif response.status >= 200 and response.status < 300 then
          logger.info('http_client', string.format('Success - Body size: %d bytes', #(response.body or "")))
          local ok, data = pcall(vim.fn.json_decode, response.body)
          callback(ok and data or response.body, nil)
        else
          local error_msg = string.format('HTTP %d: %s', response.status, response.body)
          logger.error('http_client', error_msg)
          callback(nil, error_msg)
        end
      end)
    end,
  }

  -- Use Plenary's async curl
  curl.request(curl_opts)
end

---Make async request with retry
---@param url string
---@param opts table
---@param callback function(success: boolean, result: any)
function M.request_async_with_retry(url, opts, callback)
  opts = opts or {}
  local service_name = opts.service_name or 'http'

  retry_manager.execute_with_retry_async(
    function(cb)
      M.request_async(url, opts, function(result, err)
        cb(result ~= nil, result or err)
      end)
    end,
    service_name,
    nil,
    callback
  )
end

return M