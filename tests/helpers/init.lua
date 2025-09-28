-- Test helpers and setup for all tests
local M = {}

-- Set up test environment globally
function M.setup()
  -- Enable test mode for synchronous execution
  vim.g.todo_ai_test_mode = true

  -- Disable auto features during tests
  vim.g.todo_ai_auto_scan = false

  -- Set shorter timeouts for tests
  vim.g.todo_ai_test_timeout = 100

  -- Disable logging noise
  vim.g.todo_ai_log_level = 'ERROR'
end

-- Clean up after tests
function M.teardown()
  vim.g.todo_ai_test_mode = false
  vim.g.todo_ai_auto_scan = nil
  vim.g.todo_ai_test_timeout = nil
  vim.g.todo_ai_log_level = nil
end

-- Mock async operations to run synchronously
function M.mock_async()
  local async_executor = require('todo-ai.async_executor')

  -- Store original
  async_executor._original_execute = async_executor.execute

  -- Replace with sync version
  async_executor.execute = function(cmd, opts, callback)
    local success, output, error = async_executor.execute_sync(cmd)
    callback(success, output, error)
  end
end

-- Restore async operations
function M.unmock_async()
  local async_executor = require('todo-ai.async_executor')
  if async_executor._original_execute then
    async_executor.execute = async_executor._original_execute
    async_executor._original_execute = nil
  end
end

-- Helper to wait with timeout
function M.wait_for(condition, timeout)
  timeout = timeout or 1000
  return vim.wait(timeout, condition, 10)
end

-- Helper to create test buffer
function M.create_test_buffer(content)
  local buf = vim.api.nvim_create_buf(false, true)
  if content then
    local lines = type(content) == 'string' and vim.split(content, '\n') or content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return buf
end

return M