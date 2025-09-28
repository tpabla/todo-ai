-- Utility functions and error handling
local M = {}

-- Constants
M.constants = {
  MAX_LINE_LENGTH = 2000,
  MAX_FILE_LINES = 100,
  DEFAULT_TIMEOUT = 120000,
  CLAUDE_TIMEOUT = 300000,
  MAX_RETRIES = 3,
  RETRY_DELAY = 1000,
  MIN_BUFFER_SIZE = 0,
  MAX_BUFFER_SIZE = 1000000,
}

-- Error types
M.errors = {
  INVALID_BUFFER = "Invalid buffer",
  INVALID_PARAMETERS = "Invalid parameters",
  API_ERROR = "API error",
  NETWORK_ERROR = "Network error",
  TIMEOUT_ERROR = "Request timeout",
  PARSE_ERROR = "Parse error",
  FILE_ERROR = "File error",
  PERMISSION_ERROR = "Permission denied",
}

-- Validate buffer
function M.validate_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false, M.errors.INVALID_BUFFER
  end
  return true
end

-- Validate line range
function M.validate_line_range(bufnr, start_line, end_line)
  local ok, err = M.validate_buffer(bufnr)
  if not ok then
    return false, err
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  if not start_line or start_line < 1 or start_line > line_count then
    return false, M.errors.INVALID_PARAMETERS .. ": start_line out of range"
  end

  if not end_line or end_line < start_line or end_line > line_count then
    return false, M.errors.INVALID_PARAMETERS .. ": end_line out of range"
  end

  return true
end

-- Safe JSON decode
function M.safe_json_decode(str)
  if not str or type(str) ~= 'string' or str == '' then
    return nil, M.errors.INVALID_PARAMETERS .. ": empty or invalid JSON string"
  end

  local ok, result = pcall(vim.fn.json_decode, str)
  if not ok then
    return nil, M.errors.PARSE_ERROR .. ": " .. tostring(result)
  end

  return result, nil
end

-- Safe JSON encode
function M.safe_json_encode(obj)
  if obj == nil then
    return nil, M.errors.INVALID_PARAMETERS .. ": nil object"
  end

  local ok, result = pcall(vim.fn.json_encode, obj)
  if not ok then
    return nil, M.errors.PARSE_ERROR .. ": " .. tostring(result)
  end

  return result, nil
end

-- Debounce function
function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = {...}
    if timer then
      vim.fn.timer_stop(timer)
    end
    timer = vim.fn.timer_start(delay, function()
      timer = nil
      fn(unpack(args))
    end)
  end
end

-- Throttle function
function M.throttle(fn, delay)
  local last_call = 0
  local timer = nil

  return function(...)
    local now = vim.loop.now()
    local args = {...}

    if now - last_call >= delay then
      last_call = now
      fn(unpack(args))
    else
      if timer then
        vim.fn.timer_stop(timer)
      end
      timer = vim.fn.timer_start(delay - (now - last_call), function()
        timer = nil
        last_call = vim.loop.now()
        fn(unpack(args))
      end)
    end
  end
end

-- Retry with exponential backoff
function M.retry(fn, max_retries, initial_delay)
  max_retries = max_retries or M.constants.MAX_RETRIES
  initial_delay = initial_delay or M.constants.RETRY_DELAY

  local function attempt(retry_count, delay)
    local result, err = fn()

    if result then
      return result, nil
    end

    if retry_count >= max_retries then
      return nil, err or "Max retries exceeded"
    end

    vim.defer_fn(function()
      attempt(retry_count + 1, delay * 2)
    end, delay)
  end

  return attempt(0, initial_delay)
end

-- Sanitize file path
function M.sanitize_path(path)
  if not path or type(path) ~= 'string' then
    return nil, M.errors.INVALID_PARAMETERS .. ": invalid path"
  end

  -- Remove dangerous patterns
  path = path:gsub('%.%./', '')  -- Remove relative parent dirs
  path = path:gsub('^/', '')     -- Remove absolute paths
  path = path:gsub('\\', '/')    -- Normalize separators

  -- Validate characters
  if path:match('[<>:"|?*]') then
    return nil, M.errors.INVALID_PARAMETERS .. ": invalid characters in path"
  end

  return path, nil
end

-- Deep copy table
function M.deep_copy(orig)
  local orig_type = type(orig)
  local copy

  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[M.deep_copy(orig_key)] = M.deep_copy(orig_value)
    end
    setmetatable(copy, M.deep_copy(getmetatable(orig)))
  else
    copy = orig
  end

  return copy
end

-- Merge tables
function M.merge_tables(t1, t2)
  local result = M.deep_copy(t1)

  for k, v in pairs(t2 or {}) do
    if type(v) == 'table' and type(result[k]) == 'table' then
      result[k] = M.merge_tables(result[k], v)
    else
      result[k] = v
    end
  end

  return result
end

-- Validate API response
function M.validate_api_response(response)
  if not response then
    return false, M.errors.API_ERROR .. ": empty response"
  end

  if response.error then
    return false, M.errors.API_ERROR .. ": " .. (response.error.message or vim.fn.json_encode(response.error))
  end

  return true
end

-- Create safe callback wrapper
function M.safe_callback(callback, error_handler)
  return function(...)
    local ok, result = pcall(callback, ...)
    if not ok then
      if error_handler then
        error_handler(result)
      else
        vim.notify('Callback error: ' .. tostring(result), vim.log.levels.ERROR)
      end
    end
    return result
  end
end

-- Cleanup function for resources
function M.cleanup(resources)
  for _, resource in ipairs(resources or {}) do
    if resource.type == 'timer' and resource.id then
      vim.fn.timer_stop(resource.id)
    elseif resource.type == 'buffer' and resource.id then
      if vim.api.nvim_buf_is_valid(resource.id) then
        vim.api.nvim_buf_delete(resource.id, { force = true })
      end
    elseif resource.type == 'window' and resource.id then
      if vim.api.nvim_win_is_valid(resource.id) then
        vim.api.nvim_win_close(resource.id, true)
      end
    end
  end
end

-- Format error message
function M.format_error(err, context)
  local formatted = '[todo-ai] '

  if context then
    formatted = formatted .. context .. ': '
  end

  formatted = formatted .. tostring(err)

  return formatted
end

-- Validate string length
function M.validate_string_length(str, max_length)
  if not str then
    return true
  end

  if type(str) ~= 'string' then
    return false, M.errors.INVALID_PARAMETERS .. ": expected string"
  end

  if #str > (max_length or M.constants.MAX_BUFFER_SIZE) then
    return false, M.errors.INVALID_PARAMETERS .. ": string too long"
  end

  return true
end

-- Get safe substring
function M.safe_substring(str, start_pos, end_pos)
  if not str or type(str) ~= 'string' then
    return ''
  end

  start_pos = math.max(1, start_pos or 1)
  end_pos = math.min(#str, end_pos or #str)

  if start_pos > end_pos then
    return ''
  end

  return str:sub(start_pos, end_pos)
end

return M