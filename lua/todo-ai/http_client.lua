---HTTP client using Plenary's curl
---@class HttpClient
local M = {}

local curl = require('plenary.curl')
local retry_manager = require('todo-ai.retry_manager')
local logger = require('todo-ai.logger')

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
    timeout = opts.timeout or 30000,
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
    service_name,
    opts.retry_config
  )
end

---Make async request with Plenary's curl
---@param url string
---@param opts table
---@param callback function(response: table|nil, error: string|nil)
function M.request_async(url, opts, callback)
  opts = opts or {}

  -- Build curl options
  local curl_opts = {
    url = url,
    method = opts.method or 'GET',
    headers = opts.headers or {},
    body = opts.body,
    timeout = opts.timeout or 30000,
    callback = function(response)
      vim.schedule(function()
        if response.exit ~= 0 then
          callback(nil, "Curl failed: " .. tostring(response.exit))
        elseif response.status >= 200 and response.status < 300 then
          local ok, data = pcall(vim.fn.json_decode, response.body)
          callback(ok and data or response.body, nil)
        else
          callback(nil, string.format('HTTP %d: %s', response.status, response.body))
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
    opts.retry_config,
    callback
  )
end

return M