local M = {}

M.job_id = nil
M.pipe = nil
M.pending = {}
M.stream_handlers = {}
M.request_id = 0
M.read_buffer = ""

function M.start(config)
  if M.pipe then
    error("Backend already running")
  end

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local binary = plugin_dir .. "/rust/target/release/todo-ai-backend"

  if vim.fn.executable(binary) ~= 1 then
    error("todo-ai-backend binary not found at: " .. binary .. " — run 'make build-rust'")
  end

  local socket_path = string.format("/tmp/todo-ai-%d.sock", vim.fn.getpid())
  local ready = false

  M.job_id = vim.fn.jobstart({ binary, "--socket", socket_path }, {
    on_stdout = function(_, data, _)
      if ready then return end
      for _, line in ipairs(data) do
        if line ~= "" and not ready then
          ready = true
          vim.schedule(function()
            M._connect(line, config)
          end)
        end
      end
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        if line ~= "" then
          vim.schedule(function()
            vim.notify("[todo-ai backend] " .. line, vim.log.levels.ERROR)
          end)
        end
      end
    end,
    on_exit = function(_, code, _)
      vim.schedule(function()
        M.job_id = nil
        M.pipe = nil
        M.pending = {}
        M.read_buffer = ""
        if code ~= 0 then
          vim.notify("[todo-ai backend] exited with code " .. code, vim.log.levels.ERROR)
        end
      end)
    end,
  })

  if M.job_id <= 0 then
    error("Failed to start todo-ai-backend")
  end
end

function M._connect(socket_path, config)
  local pipe = vim.loop.new_pipe(false)
  pipe:connect(socket_path, function(err)
    if err then
      vim.schedule(function()
        error("Failed to connect to backend socket: " .. err)
      end)
      return
    end

    M.pipe = pipe

    pipe:read_start(function(read_err, data)
      if read_err then
        vim.schedule(function()
          vim.notify("[todo-ai backend] read error: " .. read_err, vim.log.levels.ERROR)
        end)
        return
      end
      if data then
        M._on_read(data)
      end
    end)

    -- Send initialize request with full config
    M.request("initialize", { config = config or {} }, function(result, rpc_err)
      if rpc_err then
        vim.notify("[todo-ai backend] initialize failed: " .. rpc_err.message, vim.log.levels.ERROR)
        return
      end
      vim.notify("[todo-ai backend] connected v" .. (result.version or "?"), vim.log.levels.INFO)
    end)
  end)
end

function M._on_read(data)
  M.read_buffer = M.read_buffer .. data

  while true do
    local newline_pos = M.read_buffer:find("\n")
    if not newline_pos then break end

    local line = M.read_buffer:sub(1, newline_pos - 1)
    M.read_buffer = M.read_buffer:sub(newline_pos + 1)

    if line ~= "" then
      local ok, msg = pcall(vim.json.decode, line)
      if ok and msg then
        vim.schedule(function()
          M._dispatch(msg)
        end)
      end
    end
  end
end

function M._dispatch(msg)
  -- Response to a request (has id)
  if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) then
    local callback = M.pending[msg.id]
    if callback then
      M.pending[msg.id] = nil
      if msg.error then
        callback(nil, msg.error)
      else
        callback(msg.result, nil)
      end
    end
    return
  end

  -- Notification from server (no id, has method)
  if msg.method then
    local handler = M.stream_handlers[msg.method]
    if handler then
      handler(msg.params)
    end
    return
  end
end

function M.request(method, params, callback)
  if not M.pipe then
    error("Backend not connected")
  end

  M.request_id = M.request_id + 1
  local id = M.request_id

  local msg = vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or vim.empty_dict(),
  }) .. "\n"

  M.pending[id] = callback
  M.pipe:write(msg)
end

function M.notify(method, params)
  if not M.pipe then
    error("Backend not connected")
  end

  local msg = vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }) .. "\n"

  M.pipe:write(msg)
end

function M.on_stream(method, handler)
  M.stream_handlers[method] = handler
end

function M.is_available()
  return M.pipe ~= nil
end

function M.stop()
  if not M.pipe then return end

  -- Send shutdown notification (no callback expected)
  pcall(function()
    M.notify("shutdown", {})
  end)

  -- Close pipe
  if M.pipe and not M.pipe:is_closing() then
    M.pipe:read_stop()
    M.pipe:close()
  end
  M.pipe = nil

  -- Stop the process
  if M.job_id then
    vim.fn.jobstop(M.job_id)
    M.job_id = nil
  end

  M.pending = {}
  M.stream_handlers = {}
  M.read_buffer = ""
  M.request_id = 0
end

return M
