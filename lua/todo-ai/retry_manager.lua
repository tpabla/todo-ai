---Retry manager with exponential backoff
---@class RetryManager
local M = {}

local circuit_breaker = require('todo-ai.circuit_breaker')
local logger = require('todo-ai.logger')

---@class RetryConfig
---@field max_retries number Maximum number of retry attempts
---@field base_delay number Base delay in milliseconds
---@field max_delay number Maximum delay in milliseconds
---@field exponential_base number Base for exponential backoff (typically 2)
---@field jitter boolean Add random jitter to prevent thundering herd

M.default_config = {
  max_retries = 3,
  base_delay = 1000,      -- Start with 1 second
  max_delay = 30000,      -- Max 30 seconds
  exponential_base = 2,   -- Double each time
  jitter = true,          -- Add randomization
}

---Calculate delay with exponential backoff
---@param attempt number Current attempt (0-indexed)
---@param config RetryConfig
---@return number delay_ms
local function calculate_delay(attempt, config)
  -- Exponential backoff: base_delay * (exponential_base ^ attempt)
  local delay = config.base_delay * math.pow(config.exponential_base, attempt)

  -- Cap at max delay
  delay = math.min(delay, config.max_delay)

  -- Add jitter (0-25% random addition)
  if config.jitter then
    local jitter_amount = delay * 0.25 * math.random()
    delay = delay + jitter_amount
  end

  return math.floor(delay)
end

---Check if error is retryable
---@param error_message string
---@return boolean
local function is_retryable_error(error_message)
  -- Network errors
  if error_message:match('timeout') or
     error_message:match('connection') or
     error_message:match('network') then
    return true
  end

  -- Rate limiting
  if error_message:match('429') or
     error_message:match('rate limit') or
     error_message:match('too many requests') then
    return true
  end

  -- Server errors (5xx)
  if error_message:match('50[0-9]') or
     error_message:match('server error') or
     error_message:match('internal error') then
    return true
  end

  -- Specific API errors that are retryable
  if error_message:match('temporary') or
     error_message:match('try again') then
    return true
  end

  return false
end

---Execute function with retry logic
---@param fn function The function to execute
---@param service_name string Name of the service (for circuit breaker)
---@param config? RetryConfig Optional retry configuration
---@return boolean success, any result_or_error
function M.execute_with_retry(fn, service_name, config)
  config = vim.tbl_extend('force', M.default_config, config or {})

  -- Check circuit breaker first
  local can_proceed, cb_error = circuit_breaker.can_proceed(service_name)
  if not can_proceed then
    logger.error('retry_manager', 'Circuit breaker open: ' .. cb_error)
    return false, cb_error
  end

  local last_error
  for attempt = 0, config.max_retries do
    -- Log attempt
    if attempt > 0 then
      local delay = calculate_delay(attempt - 1, config)
      logger.debug('retry_manager', string.format(
        'Retrying %s (attempt %d/%d) after %dms delay',
        service_name, attempt + 1, config.max_retries + 1, delay
      ))
      vim.wait(delay)
    end

    -- Try to execute
    local ok, result = pcall(fn)

    if ok then
      -- Success!
      circuit_breaker.record_success(service_name)
      return true, result
    else
      last_error = result
      logger.warn('retry_manager', string.format(
        '%s failed (attempt %d): %s',
        service_name, attempt + 1, tostring(result)
      ))

      -- Check if error is retryable
      if not is_retryable_error(tostring(result)) then
        logger.error('retry_manager', 'Non-retryable error, giving up')
        circuit_breaker.record_failure(service_name, tostring(result))
        return false, result
      end

      -- Record failure for circuit breaker
      if attempt == config.max_retries then
        circuit_breaker.record_failure(service_name, tostring(result))
      end
    end
  end

  return false, last_error
end

---Async version with retry logic
---@param fn function The async function to execute (takes callback)
---@param service_name string Name of the service
---@param config? RetryConfig Optional retry configuration
---@param callback function(success: boolean, result: any)
function M.execute_with_retry_async(fn, service_name, config, callback)
  config = vim.tbl_extend('force', M.default_config, config or {})


  -- Check circuit breaker first
  local can_proceed, cb_error = circuit_breaker.can_proceed(service_name)
  if not can_proceed then
    logger.error('retry_manager', 'Circuit breaker open: ' .. cb_error)
    callback(false, cb_error)
    return
  end

  local function attempt_execution(attempt_num)
    if attempt_num > config.max_retries then
      callback(false, "Max retries exceeded")
      return
    end

    -- Calculate and apply delay for retries
    if attempt_num > 0 then
      local delay = calculate_delay(attempt_num - 1, config)
      logger.debug('retry_manager', string.format(
        'Retrying %s (attempt %d/%d) after %dms delay',
        service_name, attempt_num + 1, config.max_retries + 1, delay
      ))

      vim.defer_fn(function()
        attempt_execution_impl(attempt_num)
      end, delay)
    else
      attempt_execution_impl(attempt_num)
    end
  end

  local function attempt_execution_impl(attempt_num)
    fn(function(success, result)
      if success then
        circuit_breaker.record_success(service_name)
        callback(true, result)
      else
        logger.warn('retry_manager', string.format(
          '%s failed (attempt %d): %s',
          service_name, attempt_num + 1, tostring(result)
        ))

        if not is_retryable_error(tostring(result)) then
          logger.error('retry_manager', 'Non-retryable error, giving up')
          circuit_breaker.record_failure(service_name, tostring(result))
          callback(false, result)
        elseif attempt_num >= config.max_retries then
          circuit_breaker.record_failure(service_name, tostring(result))
          callback(false, result)
        else
          -- Retry
          attempt_execution(attempt_num + 1)
        end
      end
    end)
  end

  attempt_execution(0)
end

---Get retry statistics
---@param service_name string
---@return table
function M.get_stats(service_name)
  return {
    circuit_state = circuit_breaker.get_state(service_name),
    config = M.default_config,
  }
end

return M