-- Base functionality shared by all providers
local M = {}

-- Common HTTP request function using curl
function M.make_request(url, headers, body, callback)
  local curl = require('plenary.curl')

  curl.post(url, {
    headers = headers,
    body = body,
    callback = function(response)
      if response.status ~= 200 then
        local error_msg = string.format('HTTP %d: %s', response.status, response.body or 'Unknown error')
        callback(nil, error_msg)
        return
      end

      local ok, decoded = pcall(vim.fn.json_decode, response.body)
      if not ok then
        callback(nil, 'Failed to parse response: ' .. tostring(decoded))
        return
      end

      callback(decoded, nil)
    end
  })
end

-- Parse streaming response chunks
function M.parse_stream_chunk(chunk, callback)
  -- Handle SSE format: data: {json}
  for line in chunk:gmatch('[^\r\n]+') do
    if line:match('^data: ') then
      local data = line:gsub('^data: ', '')
      if data ~= '[DONE]' then
        local ok, decoded = pcall(vim.fn.json_decode, data)
        if ok then
          callback(decoded)
        end
      end
    end
  end
end

-- Build common headers
function M.build_headers(api_key, extra_headers)
  local headers = {
    ['Content-Type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. api_key
  }

  if extra_headers then
    for k, v in pairs(extra_headers) do
      headers[k] = v
    end
  end

  return headers
end

return M