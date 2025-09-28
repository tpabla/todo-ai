---@class AsyncManager
---@field locks table<string, boolean>
---@field queues table<string, function[]>
---@field active_requests table<string, boolean>
---@field request_timestamps table<string, number>
local M = {}

-- State
M.locks = {}
M.queues = {}
M.active_requests = {}
M.request_timestamps = {}
M.rate_limits = {}

-- Constants
M.DEFAULT_RATE_LIMIT = {
  max_requests = 10,
  window_ms = 60000,  -- 1 minute
  current_count = 0,
  window_start = 0,
}

M.PROVIDER_LIMITS = {
  claude = { max_requests = 5, window_ms = 60000 },
  openai = { max_requests = 20, window_ms = 60000 },
  ollama = { max_requests = 100, window_ms = 60000 },
}

---Acquire a lock for a resource
---@param resource string
---@param timeout_ms number|nil
---@return boolean acquired
function M.acquire_lock(resource, timeout_ms)
  timeout_ms = timeout_ms or 5000

  local start_time = vim.loop.now()

  -- Spin lock with timeout
  while M.locks[resource] do
    if vim.loop.now() - start_time > timeout_ms then
      return false  -- Timeout
    end
    vim.wait(10)  -- Small delay
  end

  M.locks[resource] = true
  return true
end

---Release a lock
---@param resource string
function M.release_lock(resource)
  M.locks[resource] = false

  -- Process any queued operations
  if M.queues[resource] and #M.queues[resource] > 0 then
    local next_op = table.remove(M.queues[resource], 1)
    vim.defer_fn(next_op, 0)
  end
end

---Execute with lock
---@param resource string
---@param fn function
---@param callback function|nil
function M.with_lock(resource, fn, callback)
  if M.acquire_lock(resource, 5000) then
    local ok, result = pcall(fn)
    M.release_lock(resource)

    if callback then
      if ok then
        callback(result, nil)
      else
        callback(nil, result)
      end
    end

    return ok, result
  else
    local error_msg = "Failed to acquire lock for: " .. resource
    if callback then
      callback(nil, error_msg)
    end
    return false, error_msg
  end
end

---Queue an operation
---@param resource string
---@param fn function
function M.queue_operation(resource, fn)
  if not M.queues[resource] then
    M.queues[resource] = {}
  end

  table.insert(M.queues[resource], fn)

  -- Try to execute if not locked
  if not M.locks[resource] then
    local op = table.remove(M.queues[resource], 1)
    if op then
      vim.defer_fn(op, 0)
    end
  end
end

---Check rate limit for a provider
---@param provider string
---@return boolean allowed, number|nil retry_after_ms
function M.check_rate_limit(provider)
  local now = vim.loop.now()

  -- Initialize rate limit if needed
  if not M.rate_limits[provider] then
    local limits = M.PROVIDER_LIMITS[provider] or M.DEFAULT_RATE_LIMIT
    M.rate_limits[provider] = {
      max_requests = limits.max_requests,
      window_ms = limits.window_ms,
      current_count = 0,
      window_start = now,
    }
  end

  local limit = M.rate_limits[provider]

  -- Reset window if expired
  if now - limit.window_start > limit.window_ms then
    limit.current_count = 0
    limit.window_start = now
  end

  -- Check if under limit
  if limit.current_count < limit.max_requests then
    limit.current_count = limit.current_count + 1
    return true, nil
  else
    -- Calculate retry time
    local retry_after = limit.window_ms - (now - limit.window_start)
    return false, retry_after
  end
end

---Execute API request with rate limiting
---@param provider string
---@param fn function
---@param callback function
function M.rate_limited_request(provider, fn, callback)
  local allowed, retry_after = M.check_rate_limit(provider)

  if allowed then
    -- Execute immediately
    fn(callback)
  else
    -- Queue for retry
    vim.defer_fn(function()
      M.rate_limited_request(provider, fn, callback)
    end, retry_after or 1000)

    -- Notify user
    vim.notify(string.format(
      "Rate limit reached for %s. Retrying in %d seconds...",
      provider, math.ceil((retry_after or 1000) / 1000)
    ), vim.log.levels.WARN)
  end
end

---Track active request
---@param request_id string
---@return boolean allowed
function M.start_request(request_id)
  -- Check if already active
  if M.active_requests[request_id] then
    return false  -- Duplicate request
  end

  M.active_requests[request_id] = true
  M.request_timestamps[request_id] = vim.loop.now()
  return true
end

---Complete a request
---@param request_id string
function M.complete_request(request_id)
  M.active_requests[request_id] = nil

  -- Log duration
  if M.request_timestamps[request_id] then
    local duration = vim.loop.now() - M.request_timestamps[request_id]
    M.request_timestamps[request_id] = nil

    local logger = require('todo-ai.logger')
    logger.debug("request.complete", {
      id = request_id,
      duration_ms = duration
    })
  end
end

---Cancel a request
---@param request_id string
function M.cancel_request(request_id)
  M.active_requests[request_id] = nil
  M.request_timestamps[request_id] = nil
end

---Check if request is active
---@param request_id string
---@return boolean
function M.is_request_active(request_id)
  return M.active_requests[request_id] == true
end

---Debounced execution
---@param key string
---@param fn function
---@param delay_ms number
---@return function
function M.debounce(key, fn, delay_ms)
  local timers = {}

  return function(...)
    local args = {...}

    if timers[key] then
      vim.fn.timer_stop(timers[key])
    end

    timers[key] = vim.fn.timer_start(delay_ms, function()
      timers[key] = nil
      fn(unpack(args))
    end)
  end
end

---Throttled execution
---@param key string
---@param fn function
---@param limit_ms number
---@return function
function M.throttle(key, fn, limit_ms)
  local last_call = {}

  return function(...)
    local now = vim.loop.now()

    if not last_call[key] or (now - last_call[key]) >= limit_ms then
      last_call[key] = now
      return fn(...)
    end
  end
end

---Batch operations
---@param key string
---@param items table
---@param batch_size number
---@param processor function
---@param callback function|nil
function M.batch_process(key, items, batch_size, processor, callback)
  local total = #items
  local processed = 0
  local results = {}

  local function process_batch(start_idx)
    local batch = {}
    local end_idx = math.min(start_idx + batch_size - 1, total)

    for i = start_idx, end_idx do
      table.insert(batch, items[i])
    end

    processor(batch, function(batch_results)
      -- Collect results
      for _, result in ipairs(batch_results or {}) do
        table.insert(results, result)
      end

      processed = processed + #batch

      -- Continue or complete
      if processed < total then
        vim.defer_fn(function()
          process_batch(processed + 1)
        end, 10)  -- Small delay between batches
      else
        if callback then
          callback(results)
        end
      end
    end)
  end

  -- Start processing
  process_batch(1)
end

---Concurrent execution with limit
---@param tasks function[]
---@param max_concurrent number
---@param callback function|nil
function M.concurrent_limit(tasks, max_concurrent, callback)
  local completed = 0
  local running = 0
  local results = {}
  local task_index = 1

  local function run_next()
    if task_index > #tasks then
      -- All tasks started
      if running == 0 and callback then
        callback(results)
      end
      return
    end

    if running >= max_concurrent then
      -- Wait for a slot
      return
    end

    local idx = task_index
    task_index = task_index + 1
    running = running + 1

    tasks[idx](function(result)
      running = running - 1
      completed = completed + 1
      results[idx] = result

      -- Run next task
      run_next()

      -- Check if all complete
      if completed == #tasks and callback then
        callback(results)
      end
    end)

    -- Try to run another
    run_next()
  end

  -- Start initial batch
  for i = 1, math.min(max_concurrent, #tasks) do
    run_next()
  end
end

---Create a semaphore
---@param max_count number
---@return table semaphore
function M.create_semaphore(max_count)
  return {
    count = max_count,
    max = max_count,
    waiting = {},

    acquire = function(self, callback)
      if self.count > 0 then
        self.count = self.count - 1
        callback()
      else
        table.insert(self.waiting, callback)
      end
    end,

    release = function(self)
      self.count = math.min(self.count + 1, self.max)

      if #self.waiting > 0 then
        local next_callback = table.remove(self.waiting, 1)
        self.count = self.count - 1
        vim.defer_fn(next_callback, 0)
      end
    end,
  }
end

---Get stats
---@return table
function M.get_stats()
  local active_count = 0
  for _ in pairs(M.active_requests) do
    active_count = active_count + 1
  end

  local queued_count = 0
  for _, queue in pairs(M.queues) do
    queued_count = queued_count + #queue
  end

  return {
    active_requests = active_count,
    queued_operations = queued_count,
    locked_resources = vim.tbl_keys(M.locks),
    rate_limits = M.rate_limits,
  }
end

---Reset all state
function M.reset()
  M.locks = {}
  M.queues = {}
  M.active_requests = {}
  M.request_timestamps = {}
  M.rate_limits = {}
end

return M