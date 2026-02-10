-- Bridge to the todo-ai-core Rust backend
-- Communicates via JSON messages over stdin/stdout
local M = {}

local logger = require('todo-ai.logger')

M.state = {
  job_id = nil,
  request_id = 0,
  pending = {}, -- request_id -> callback
  stdout_buffer = '',
}

-- Find the Rust binary
local function find_binary()
  -- Check common locations in order
  local candidates = {
    -- Built via `make build-rust` into plugin root
    vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h') .. '/rust/target/release/todo-ai-core',
    vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h') .. '/rust/target/debug/todo-ai-core',
    -- System-wide install
    vim.fn.exepath('todo-ai-core'),
  }

  for _, path in ipairs(candidates) do
    if path ~= '' and vim.fn.executable(path) == 1 then
      return path
    end
  end

  return nil
end

-- Start the Rust backend process (required - errors if binary not found)
function M.start()
  if M.state.job_id then
    return true
  end

  local binary = find_binary()
  if not binary then
    logger.error('bridge', 'todo-ai-core binary not found. Run `make build-rust` first.')
    return false
  end

  logger.info('bridge', 'Starting backend: ' .. binary)

  M.state.job_id = vim.fn.jobstart({binary}, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= '' then
          M.handle_response(line)
        end
      end
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= '' then
          logger.error('bridge', 'Backend stderr: ' .. line)
        end
      end
    end,
    on_exit = function(_, code, _)
      logger.info('bridge', 'Backend exited with code: ' .. code)
      M.state.job_id = nil
      -- Fail all pending requests
      for id, cb in pairs(M.state.pending) do
        cb(nil, 'Backend process exited')
        M.state.pending[id] = nil
      end
    end,
    stdin = 'pipe',
    stdout_buffered = false,
  })

  if M.state.job_id <= 0 then
    logger.error('bridge', 'Failed to start backend process')
    M.state.job_id = nil
    return false
  end

  -- Verify with ping
  M.call('ping', {}, function(result, err)
    if err then
      logger.error('bridge', 'Backend ping failed: ' .. err)
    else
      logger.info('bridge', 'Backend ready: v' .. (result.version or 'unknown'))
    end
  end)

  return true
end

-- Stop the backend process
function M.stop()
  if M.state.job_id then
    vim.fn.jobstop(M.state.job_id)
    M.state.job_id = nil
  end
end

-- Send a request to the backend
function M.call(method, params, callback)
  if not M.state.job_id then
    error('todo-ai: Rust backend is not running. Call bridge.start() first.')
  end

  M.state.request_id = M.state.request_id + 1
  local id = M.state.request_id

  local request = vim.fn.json_encode({
    id = id,
    method = method,
    params = params or {},
  })

  if callback then
    M.state.pending[id] = callback
  end

  vim.fn.chansend(M.state.job_id, request .. '\n')
end

-- Synchronous call (blocks until response)
function M.call_sync(method, params, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local result_data = nil
  local error_data = nil
  local done = false

  M.call(method, params, function(result, err)
    result_data = result
    error_data = err
    done = true
  end)

  -- Wait for response
  local start = vim.loop.now()
  while not done and (vim.loop.now() - start) < timeout_ms do
    vim.wait(10, function() return done end)
  end

  if not done then
    return nil, 'Request timed out'
  end

  return result_data, error_data
end

-- Handle a response line from the backend
function M.handle_response(line)
  local ok, response = pcall(vim.fn.json_decode, line)
  if not ok then
    logger.error('bridge', 'Failed to parse response: ' .. line)
    return
  end

  local id = response.id
  local callback = M.state.pending[id]
  if not callback then
    return
  end
  M.state.pending[id] = nil

  vim.schedule(function()
    if response.error then
      callback(nil, response.error)
    else
      callback(response.result, nil)
    end
  end)
end

-- Check if backend is running
function M.is_running()
  return M.state.job_id ~= nil
end

-- --- Convenience methods that map to backend RPC calls ---

-- Apply search/replace changes to lines
function M.apply_changes(lines, changes, callback)
  M.call('apply_changes', {lines = lines, changes = changes}, callback)
end

-- Parse an LLM response
function M.parse_response(response_text, hint, callback)
  M.call('parse_response', {response = response_text, hint = hint}, callback)
end

-- Validate a parsed response against schema
function M.validate_response(parsed_response, callback)
  M.call('validate_response', {response = parsed_response}, callback)
end

-- Scan lines for TODO items
function M.scan_todos(lines, comment_string, callback)
  M.call('scan_todos', {lines = lines, comment_string = comment_string}, callback)
end

-- Build the complete prompt
function M.build_prompt(instruction, context, callback)
  M.call('build_prompt', {instruction = instruction, context = context}, callback)
end

-- Send request to LLM provider (runs in Rust for HTTP)
function M.send_to_provider(params, callback)
  M.call('send_to_provider', params, callback)
end

-- Calculate position of search text in content
function M.calculate_position(content, search_text, callback)
  M.call('calculate_position', {content = content, search_text = search_text}, callback)
end

-- Track change regions for navigation
function M.track_change_regions(lines, changes, rejected_indices, callback)
  M.call('track_change_regions', {
    lines = lines,
    changes = changes,
    rejected_indices = rejected_indices or {},
  }, callback)
end

return M
