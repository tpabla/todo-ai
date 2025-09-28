---Command executor using Plenary's Job
---@class CommandExecutor
local M = {}

local has_plenary, Job = pcall(require, 'plenary.job')

-- Fallback to vim.loop if Plenary not available
if has_plenary then
  ---Execute command using Plenary's Job
---@param cmd string[] Command array
---@param opts table Options {timeout: number, cwd: string}
---@param callback function(success: boolean, output: string|nil, error: string|nil)
function M.execute(cmd, opts, callback)
  opts = opts or {}
  local stdout_chunks = {}
  local stderr_chunks = {}
  local handle
  local timeout_timer

  -- Set up timeout if specified
  if opts.timeout and opts.timeout > 0 then
    timeout_timer = vim.loop.new_timer()
    timeout_timer:start(opts.timeout, 0, function()
      if handle and not handle:is_closing() then
        handle:kill('sigterm')
        vim.schedule(function()
          callback(false, nil, "Command timed out after " .. opts.timeout .. "ms")
        end)
      end
    end)
  end

  -- Use vim.loop.spawn for proper async execution
  handle = vim.loop.spawn(cmd[1], {
    args = vim.list_slice(cmd, 2),
    cwd = opts.cwd,
    stdio = {nil, 'pipe', 'pipe'},
  }, function(code)
    -- Clean up timer
    if timeout_timer then
      timeout_timer:stop()
      timeout_timer:close()
    end

    -- Process completion
    vim.schedule(function()
      local stdout = table.concat(stdout_chunks)
      local stderr = table.concat(stderr_chunks)

      if code == 0 then
        callback(true, stdout, nil)
      else
        callback(false, stdout, stderr ~= '' and stderr or "Exit code: " .. code)
      end
    end)
  end)

  if not handle then
    if timeout_timer then
      timeout_timer:stop()
      timeout_timer:close()
    end
    callback(false, nil, "Failed to spawn command")
    return
  end

  -- Read stdout
  if handle.stdout then
    vim.loop.read_start(handle.stdout, function(err, data)
      if data then
        table.insert(stdout_chunks, data)
      end
    end)
  end

  -- Read stderr
  if handle.stderr then
    vim.loop.read_start(handle.stderr, function(err, data)
      if data then
        table.insert(stderr_chunks, data)
      end
    end)
  end
end

---Execute command synchronously
---@param cmd string[] Command array
---@param opts? table Options
---@return boolean success, string|nil output, string|nil error
function M.execute_sync(cmd, opts)
  opts = opts or {}

  if has_plenary then
    -- Use Plenary's Job for better handling
    local job = Job:new({
      command = cmd[1],
      args = vim.list_slice(cmd, 2),
      cwd = opts.cwd,
      enable_recording = true,
    })

    local ok, result = pcall(job.sync, job, opts.timeout or 30000)
    if not ok then
      return false, nil, tostring(result)
    end

    local output = table.concat(job:result(), '\n')
    if job.code == 0 then
      return true, output, nil
    else
      local stderr = table.concat(job:stderr_result(), '\n')
      return false, output, stderr ~= '' and stderr or "Exit code: " .. job.code
    end
  else
    -- Fallback to system
    local result = vim.fn.system(cmd)
    local code = vim.v.shell_error
    if code == 0 then
      return true, result, nil
    else
      return false, nil, result
    end
  end
end

---Execute async using Plenary if available
---@param cmd string[] Command array
---@param opts table Options
---@param callback function(success: boolean, output: string|nil, error: string|nil)
function M.execute_async(cmd, opts, callback)
  opts = opts or {}

  if has_plenary then
    -- Use Plenary's Job for clean async
    Job:new({
      command = cmd[1],
      args = vim.list_slice(cmd, 2),
      cwd = opts.cwd,
      enable_recording = true,
      on_exit = function(job, return_val)
        local output = table.concat(job:result(), '\n')
        local stderr = table.concat(job:stderr_result(), '\n')

        vim.schedule(function()
          if return_val == 0 then
            callback(true, output, nil)
          else
            callback(false, output, stderr ~= '' and stderr or "Exit code: " .. return_val)
          end
        end)
      end,
    }):start()
  else
    -- Fallback to original vim.loop implementation
    M.execute(cmd, opts, callback)
  end
end
end  -- End of if has_plenary

return M