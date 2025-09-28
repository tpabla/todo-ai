---@class SecureExec
---@field ALLOWED_COMMANDS table<string, boolean>
---@field MAX_COMMAND_LENGTH number
local M = {}

-- Whitelist of allowed commands
M.ALLOWED_COMMANDS = {
  curl = true,
  git = true,
  find = true,
  grep = true,
  rg = true,
  tree = true,
  ls = true,
  cat = true,
  head = true,
  tail = true,
  wc = true,
  make = true,
  sleep = true,  -- For testing timeouts
}

-- Explicitly blocked dangerous commands
M.DANGEROUS_COMMANDS = {
  rm = true,
  sudo = true,
  eval = true,
  exec = true,
  source = true,
  chmod = true,
  chown = true,
  dd = true,
  mkfs = true,
  fdisk = true,
  kill = true,
  killall = true,
  shutdown = true,
  reboot = true,
  passwd = true,
}

M.MAX_COMMAND_LENGTH = 10000

---Validate and sanitize a command
---@param cmd string
---@return boolean ok, string|nil error
function M.validate_command(cmd)
  if not cmd or type(cmd) ~= 'string' then
    return false, "Invalid command type"
  end

  if #cmd > M.MAX_COMMAND_LENGTH then
    return false, "Command too long"
  end

  -- Check if it's a dangerous command
  local base_cmd = cmd:match('^%s*(%S+)') or cmd
  if M.DANGEROUS_COMMANDS[base_cmd] then
    return false, "Dangerous command blocked: " .. base_cmd
  end

  -- Check for dangerous patterns
  local dangerous_patterns = {
    '%.%.',  -- Directory traversal
    '`',     -- Command substitution
    '%$%(', -- Command substitution
    '&&',    -- Command chaining (restrict)
    '||',    -- Command chaining (restrict)
    ';',     -- Command separator
    '|',     -- Pipe (restrict)
    '>',     -- Redirection
    '<',     -- Redirection
    '&',     -- Background
    '\n',    -- Newline injection
    '\r',    -- Carriage return
  }

  for _, pattern in ipairs(dangerous_patterns) do
    if cmd:match(pattern) then
      return false, "Dangerous pattern detected: " .. pattern
    end
  end

  return true
end

---Escape shell arguments safely
---@param arg string
---@return string
local function shell_escape(arg)
  if not arg then return "''" end

  -- Use single quotes and escape any existing single quotes
  -- This prevents any shell interpretation
  arg = tostring(arg)
  arg = arg:gsub("'", "'\\''")
  return "'" .. arg .. "'"
end

---Execute curl safely with proper escaping
---@param url string
---@param opts table|nil
---@return string|nil result, string|nil error
function M.curl(url, opts)
  opts = opts or {}

  -- Validate URL
  if not url or type(url) ~= 'string' then
    return nil, "Invalid URL"
  end

  -- Basic URL validation
  if not url:match('^https?://') then
    return nil, "URL must start with http:// or https://"
  end

  -- Validate URL length
  if #url > 2000 then
    return nil, "URL too long"
  end

  -- Build curl command safely using table
  local cmd_parts = {'curl'}

  -- Add options
  if opts.method then
    table.insert(cmd_parts, '-X')
    table.insert(cmd_parts, opts.method)
  end

  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(cmd_parts, '-H')
      table.insert(cmd_parts, header)
    end
  end

  if opts.data then
    table.insert(cmd_parts, '-d')
    table.insert(cmd_parts, opts.data)
  end

  if opts.timeout then
    table.insert(cmd_parts, '--max-time')
    table.insert(cmd_parts, tostring(opts.timeout))
  end

  -- Security options
  table.insert(cmd_parts, '--no-buffer')
  table.insert(cmd_parts, '--fail')
  table.insert(cmd_parts, '--silent')
  table.insert(cmd_parts, '--show-error')
  table.insert(cmd_parts, '--location')  -- Follow redirects
  table.insert(cmd_parts, '--max-redirs')
  table.insert(cmd_parts, '5')

  -- Add URL last
  table.insert(cmd_parts, url)

  -- Execute using vim.fn.systemlist for safer execution
  local result = vim.fn.systemlist(cmd_parts)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    return nil, "Curl failed with exit code: " .. exit_code
  end

  return table.concat(result, '\n'), nil
end

---Execute curl asynchronously
---@param url string
---@param opts table|nil
---@param callback function
function M.curl_async(url, opts, callback)
  opts = opts or {}

  -- Validate inputs
  if not url or type(url) ~= 'string' then
    callback(nil, "Invalid URL")
    return
  end

  if not url:match('^https?://') then
    callback(nil, "URL must start with http:// or https://")
    return
  end

  -- Build command array (safer than string concatenation)
  local cmd = {'curl'}

  -- Method
  if opts.method then
    table.insert(cmd, '-X')
    table.insert(cmd, opts.method)
  end

  -- Headers
  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(cmd, '-H')
      table.insert(cmd, header)
    end
  end

  -- Data
  if opts.data then
    table.insert(cmd, '-d')
    table.insert(cmd, opts.data)
  end

  -- Timeout
  table.insert(cmd, '--max-time')
  table.insert(cmd, tostring(opts.timeout or 30))

  -- Security options
  table.insert(cmd, '--no-buffer')
  table.insert(cmd, '--fail')
  table.insert(cmd, '--silent')
  table.insert(cmd, '--show-error')
  table.insert(cmd, '--location')
  table.insert(cmd, '--max-redirs')
  table.insert(cmd, '5')

  -- URL
  table.insert(cmd, url)

  -- Use jobstart for async execution
  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      if exit_code == 0 then
        callback(table.concat(stdout_data, '\n'), nil)
      else
        local error_msg = table.concat(stderr_data, '\n')
        if error_msg == '' then
          error_msg = "Curl failed with exit code: " .. exit_code
        end
        callback(nil, error_msg)
      end
    end,
  })
end

---Execute git command safely
---@param args string[]
---@return string|nil result, string|nil error
function M.git(args)
  if not args or type(args) ~= 'table' then
    return nil, "Invalid arguments"
  end

  -- Whitelist git subcommands
  local allowed_subcommands = {
    status = true,
    log = true,
    diff = true,
    branch = true,
    ['ls-files'] = true,
    ['rev-parse'] = true,
    remote = true,
    show = true,
  }

  local subcommand = args[1]
  if not subcommand or not allowed_subcommands[subcommand] then
    return nil, "Git subcommand not allowed: " .. tostring(subcommand)
  end

  -- Build command
  local cmd = {'git'}
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  -- Execute
  local result = vim.fn.systemlist(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    return nil, "Git command failed with exit code: " .. exit_code
  end

  return table.concat(result, '\n'), nil
end

---Execute find command safely
---@param path string
---@param opts table|nil
---@return string[]|nil files, string|nil error
function M.find(path, opts)
  opts = opts or {}

  -- Validate path
  if not path or path:match('%.%.') then
    return nil, "Invalid path"
  end

  -- Limit search depth
  local max_depth = opts.max_depth or 5

  -- Build command
  local cmd = {'find', path}

  -- Type
  if opts.type then
    table.insert(cmd, '-type')
    table.insert(cmd, opts.type)
  end

  -- Max depth
  table.insert(cmd, '-maxdepth')
  table.insert(cmd, tostring(max_depth))

  -- Name pattern
  if opts.name then
    table.insert(cmd, '-name')
    table.insert(cmd, opts.name)
  end

  -- Limit results
  local result = vim.fn.systemlist(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    return nil, "Find command failed"
  end

  -- Limit results to prevent memory issues
  if #result > 1000 then
    local truncated = {}
    for i = 1, 1000 do
      truncated[i] = result[i]
    end
    return truncated, nil
  end

  return result, nil
end

---Sanitize command arguments
---@param args table
---@return table
function M.sanitize_args(args)
  if not args or type(args) ~= 'table' then
    return {}
  end

  local sanitized = {}
  for _, arg in ipairs(args) do
    local safe_arg = tostring(arg)

    -- Remove command injection attempts
    if safe_arg:match('[;&|]') then
      -- Skip this argument entirely if it contains shell metacharacters
      goto continue
    end

    -- Remove command substitution
    safe_arg = safe_arg:gsub('%$%(.-%)','')
    safe_arg = safe_arg:gsub('`.-`', '')

    -- Keep the argument if it's now safe
    if safe_arg ~= '' then
      table.insert(sanitized, safe_arg)
    end

    ::continue::
  end

  return sanitized
end

---Validate URL
---@param url string
---@return boolean
function M.validate_url(url)
  if not url or type(url) ~= 'string' then
    return false
  end

  -- Must be http or https
  if not url:match('^https?://') then
    return false
  end

  -- Reject file:// and other protocols
  if url:match('^file:') or url:match('^javascript:') then
    return false
  end

  -- Reject URLs with suspicious patterns
  if url:match('%.%.') or url:match(';') or url:match("'") then
    return false
  end

  return true
end

---Validate file path
---@param path string
---@return boolean
function M.validate_file_path(path)
  if not path or type(path) ~= 'string' then
    return false
  end

  -- Reject absolute paths
  if path:match('^/') or path:match('^~') then
    return false
  end

  -- Reject directory traversal
  if path:match('%.%.') then
    return false
  end

  -- Reject system directories
  local forbidden = {'/etc', '/root', '/sys', '/proc', '.ssh', '.aws'}
  for _, dir in ipairs(forbidden) do
    if path:match(dir) then
      return false
    end
  end

  return true
end

---Execute command with timeout
---@param command string
---@param args table
---@param timeout number milliseconds
---@param callback function
function M.execute_with_timeout(command, args, timeout, callback)
  if not M.ALLOWED_COMMANDS[command] then
    callback(false, nil, "Command not allowed: " .. command)
    return
  end

  local cmd = {command}
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  local stdout_data = {}
  local stderr_data = {}
  local job_id = nil
  local timer_id = nil
  local completed = false

  -- Start timer for timeout
  timer_id = vim.fn.timer_start(timeout, function()
    if not completed and job_id then
      vim.fn.jobstop(job_id)
      callback(false, nil, "Command timeout")
      completed = true
    end
  end)

  -- Start job
  job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      if not completed then
        completed = true
        if timer_id then
          vim.fn.timer_stop(timer_id)
        end

        if exit_code == 0 then
          callback(true, table.concat(stdout_data, '\n'), nil)
        else
          callback(false, table.concat(stdout_data, '\n'), table.concat(stderr_data, '\n'))
        end
      end
    end
  })
end

---Execute command safely
---@param command string
---@param args table
---@param callback function
function M.execute_safe(command, args, callback)
  if not M.ALLOWED_COMMANDS[command] then
    callback(false, nil, "Command not allowed: " .. command)
    return
  end

  local safe_args = M.sanitize_args(args)
  local cmd = {command}
  for _, arg in ipairs(safe_args) do
    table.insert(cmd, arg)
  end

  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      if exit_code == 0 then
        callback(true, table.concat(stdout_data, '\n'), nil)
      else
        callback(false, table.concat(stdout_data, '\n'), table.concat(stderr_data, '\n'))
      end
    end
  })
end

---Validate data size
---@param data string
---@return boolean
function M.validate_data_size(data)
  if not data then
    return true
  end

  -- Reject data larger than 10MB
  if #data > 10 * 1024 * 1024 then
    error("Data size exceeds limit")
  end

  return true
end

---Safe system command execution with validation
---@param cmd string|table
---@return string|nil result, string|nil error
function M.safe_system(cmd)
  if type(cmd) == 'string' then
    -- Validate string command
    local ok, err = M.validate_command(cmd)
    if not ok then
      return nil, err
    end

    -- Extract command name
    local cmd_name = cmd:match('^%s*(%S+)')
    if not cmd_name or not M.ALLOWED_COMMANDS[cmd_name] then
      return nil, "Command not allowed: " .. tostring(cmd_name)
    end

    -- Execute with timeout
    local result = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error

    if exit_code ~= 0 then
      return nil, "Command failed with exit code: " .. exit_code
    end

    return result, nil

  elseif type(cmd) == 'table' then
    -- Table command is safer
    local cmd_name = cmd[1]
    if not cmd_name or not M.ALLOWED_COMMANDS[cmd_name] then
      return nil, "Command not allowed: " .. tostring(cmd_name)
    end

    local result = vim.fn.systemlist(cmd)
    local exit_code = vim.v.shell_error

    if exit_code ~= 0 then
      return nil, "Command failed with exit code: " .. exit_code
    end

    return table.concat(result, '\n'), nil
  else
    return nil, "Invalid command type"
  end
end

return M