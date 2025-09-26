local M = {}

M.state = {
  request_id = 0,
  pending_requests = {},
  connected = false
}

function M.connect()
  local config = require('todo-ai.config')
  local host = config.get('server_host')
  local port = config.get('server_port')

  -- Check if already connected
  if M.state.connected then
    return true
  end

  -- Try to connect
  local ok = M.check_server(host, port)
  if ok then
    M.state.connected = true
    return true
  end

  return false
end

function M.check_server(host, port)
  -- Simple check to see if server is running
  local curl_cmd = string.format('curl -s http://%s:%d/health', host, port)
  local result = vim.fn.system(curl_cmd)

  return result:find('ok') ~= nil
end

function M.request_completion(params, callback)
  if not M.connect() then
    callback({ error = 'Server not running. Run :TodoAIInstall' })
    return
  end

  local config = require('todo-ai.config')
  local host = config.get('server_host')
  local port = config.get('server_port')

  -- Generate request ID
  M.state.request_id = M.state.request_id + 1
  local request_id = M.state.request_id

  -- Store callback
  M.state.pending_requests[request_id] = callback

  -- Prepare request
  local request = vim.fn.json_encode({
    id = request_id,
    method = 'completion',
    params = params
  })

  -- Send request using curl
  local curl_cmd = string.format(
    'curl -s -X POST -H "Content-Type: application/json" -d %s http://%s:%d/api/completion',
    vim.fn.shellescape(request),
    host,
    port
  )

  vim.fn.jobstart(curl_cmd, {
    on_stdout = function(_, data)
      local response_text = table.concat(data, '')
      if response_text and response_text ~= '' then
        local ok, response = pcall(vim.fn.json_decode, response_text)
        if ok and response then
          M.handle_response(response)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        if M.state.pending_requests[request_id] then
          M.state.pending_requests[request_id]({ error = 'Request failed' })
          M.state.pending_requests[request_id] = nil
        end
      end
    end
  })
end

function M.send_chat_message(params, callback)
  if not M.connect() then
    callback({ error = 'Server not running. Run :TodoAIInstall' })
    return
  end

  local config = require('todo-ai.config')
  local host = config.get('server_host')
  local port = config.get('server_port')

  -- Generate request ID
  M.state.request_id = M.state.request_id + 1
  local request_id = M.state.request_id

  -- Store callback
  M.state.pending_requests[request_id] = callback

  -- Prepare request
  local request = vim.fn.json_encode({
    id = request_id,
    method = 'chat',
    params = params
  })

  -- Send request using curl
  local curl_cmd = string.format(
    'curl -s -X POST -H "Content-Type: application/json" -d %s http://%s:%d/api/chat',
    vim.fn.shellescape(request),
    host,
    port
  )

  vim.fn.jobstart(curl_cmd, {
    on_stdout = function(_, data)
      local response_text = table.concat(data, '')
      if response_text and response_text ~= '' then
        local ok, response = pcall(vim.fn.json_decode, response_text)
        if ok and response then
          M.handle_response(response)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        if M.state.pending_requests[request_id] then
          M.state.pending_requests[request_id]({ error = 'Request failed' })
          M.state.pending_requests[request_id] = nil
        end
      end
    end
  })
end

function M.handle_response(response)
  local request_id = response.id
  local callback = M.state.pending_requests[request_id]

  if callback then
    callback(response.result or response)
    M.state.pending_requests[request_id] = nil
  end
end

return M