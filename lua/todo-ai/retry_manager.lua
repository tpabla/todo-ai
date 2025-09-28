---@class RetryManager
local M = {}

local config = require('todo-ai.config')
local logger = require('todo-ai.logger')

---Check if error is retryable
---@param error_msg string
---@return boolean
local function is_retryable_error(error_msg)
  local lower_error = error_msg:lower()
  return lower_error:find('timeout') or
         lower_error:find('network') or
         lower_error:find('rate limit') or
         lower_error:find('429') or
         lower_error:find('502') or
         lower_error:find('503') or
         lower_error:find('504')
end

---Calculate delay with exponential backoff
---@param attempt number
---@return number
local function calculate_delay(attempt)
  local retry_config = config.get('retry') or {
    base_delay = 1000,
    exponential_base = 2,
    max_delay = 30000
  }
  local delay = retry_config.base_delay * (retry_config.exponential_base ^ attempt)
  return math.min(delay, retry_config.max_delay)
end

---Execute function with retry logic (asynchronous)
---@param fn function Function that takes a callback(success, result)
---@param service_name string Service name for logging
---@param opts table? Ignored (for compatibility)
---@param callback function Final callback(success, result)
function M.execute_with_retry_async(fn, service_name, opts, callback)
  local retry_config = config.get('retry') or {
    max_attempts = 3,
    base_delay = 1000,
    exponential_base = 2,
    max_delay = 30000
  }
  local attempt = 0

  local function try_execute()
    attempt = attempt + 1

    fn(function(success, result)
      if success then
        logger.debug('retry_manager', service_name .. ' succeeded on attempt ' .. attempt)
        callback(true, result)
        return
      end

      local error_msg = tostring(result)
      logger.warn('retry_manager', string.format('%s failed (attempt %d): %s',
        service_name, attempt, error_msg))

      if not is_retryable_error(error_msg) or attempt >= retry_config.max_attempts then
        logger.error('retry_manager', service_name .. ' giving up after ' .. attempt .. ' attempts')
        callback(false, result)
        return
      end

      local delay = calculate_delay(attempt - 1)
      logger.debug('retry_manager', string.format('Retrying %s in %dms', service_name, delay))
      vim.defer_fn(try_execute, delay)
    end)
  end

  try_execute()
end

---Execute function with retry logic (synchronous)
---@param fn function Function to execute
---@param service_name string Service name for logging
---@param opts table? Ignored (for compatibility)
---@return boolean success, any result
function M.execute_with_retry(fn, service_name, opts)
  local retry_config = config.get('retry') or {
    max_attempts = 3,
    base_delay = 1000,
    exponential_base = 2,
    max_delay = 30000
  }

  for attempt = 0, retry_config.max_attempts - 1 do
    local success, result = pcall(fn)

    if success then
      logger.debug('retry_manager', service_name .. ' succeeded on attempt ' .. (attempt + 1))
      return true, result
    end

    local error_msg = tostring(result)
    logger.warn('retry_manager', string.format('%s failed (attempt %d): %s',
      service_name, attempt + 1, error_msg))

    if not is_retryable_error(error_msg) then
      logger.error('retry_manager', 'Non-retryable error, giving up: ' .. error_msg)
      return false, result
    end

    if attempt < retry_config.max_attempts - 1 then
      local delay = calculate_delay(attempt)
      logger.debug('retry_manager', string.format('Retrying %s in %dms', service_name, delay))
      vim.wait(delay)
    end
  end

  logger.error('retry_manager', service_name .. ' failed after ' .. retry_config.max_attempts .. ' attempts')
  return false, "Max retries exceeded"
end

return M