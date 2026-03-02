local M = {}
local parser = require('todo-ai.parser')
local config = require('todo-ai.config')
local prompt_builder = require('todo-ai.prompt_builder')
local logger = require('todo-ai.logger')

-- Build the claude -p command (prompt comes via stdin)
local function build_cmd(system_prompt)
  return {
    'claude',
    '-p',
    '--output-format', 'json',
    '--system-prompt', system_prompt,
    '--no-session-persistence',
  }
end

-- Parse the JSON result from claude -p
local function parse_cli_result(json_str)
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    error('Failed to parse claude CLI output: ' .. tostring(data))
  end
  if data.is_error then
    error('Claude CLI error: ' .. (data.result or 'unknown error'))
  end
  if not data.result or data.result == '' then
    error('No content in claude CLI response')
  end
  return data.result
end

function M.complete(instruction, context, opts)
  opts = opts or {}
  local prompt = prompt_builder.build_user_prompt(instruction, context)
  local system_prompt = prompt_builder.get_system_prompt()
  local cmd = build_cmd(system_prompt)

  local result = vim.fn.system(cmd, prompt)
  if vim.v.shell_error ~= 0 then
    error('claude CLI failed: ' .. result)
  end

  return parser.parse(parse_cli_result(result), 'claude')
end

function M.complete_async(instruction, context, opts, callback)
  opts = opts or {}

  logger.info('claude-cli', '=== CLAUDE CLI REQUEST START ===')

  vim.schedule(function()
    vim.notify("Sending to Claude CLI...", vim.log.levels.INFO)
  end)

  local prompt = prompt_builder.build_user_prompt(instruction, context)
  local system_prompt = prompt_builder.get_system_prompt()
  local cmd = build_cmd(system_prompt)

  logger.info('claude-cli', string.format('Prompt length: %d chars', #prompt))
  logger.info('claude-cli', string.format('System prompt length: %d chars', #system_prompt))

  local stdout = {}
  local stderr = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdin = 'pipe',
    env = vim.tbl_extend('force', vim.fn.environ(), { CLAUDECODE = '', ANTHROPIC_API_KEY = '' }),
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          table.insert(stdout, line)
          logger.debug('claude-cli', string.format('stdout chunk: %s', line:sub(1, 200)))
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          table.insert(stderr, line)
          logger.debug('claude-cli', string.format('stderr: %s', line:sub(1, 500)))
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        logger.info('claude-cli', string.format('Process exited with code: %d', code))
        logger.info('claude-cli', string.format('stdout lines: %d, stderr lines: %d', #stdout, #stderr))

        local raw = table.concat(stdout, '\n')
        logger.info('claude-cli', string.format('Raw output length: %d chars', #raw))
        if #raw > 0 then
          logger.info('claude-cli', string.format('Raw output preview: %s', raw:sub(1, 500)))
        end
        if #stderr > 0 then
          logger.info('claude-cli', string.format('Stderr output: %s', table.concat(stderr, '\n'):sub(1, 500)))
        end

        if code ~= 0 then
          local err_msg = table.concat(stderr, '\n')
          logger.error('claude-cli', string.format('CLI failed (code %d): %s', code, err_msg))
          callback(nil, 'claude CLI failed (code ' .. code .. '): ' .. err_msg)
          return
        end

        local content_ok, content = pcall(parse_cli_result, raw)
        if not content_ok then
          logger.error('claude-cli', string.format('parse_cli_result failed: %s', tostring(content)))
          callback(nil, tostring(content))
          return
        end

        logger.info('claude-cli', string.format('Got content: %d chars', #content))
        logger.info('claude-cli', string.format('Content preview: %s', content:sub(1, 300)))

        local parse_ok, parsed = pcall(parser.parse, content, 'claude')
        if parse_ok then
          logger.info('claude-cli', string.format('Parse successful! Keys: %s', vim.inspect(vim.tbl_keys(parsed or {}))))
          callback(parsed, nil)
        else
          logger.error('claude-cli', string.format('Parse failed: %s', tostring(parsed)))
          callback(nil, 'Parser error: ' .. tostring(parsed))
        end

        logger.info('claude-cli', '=== CLAUDE CLI REQUEST END ===')
      end)
    end,
  })

  logger.info('claude-cli', string.format('Job started with id: %d', job_id))
  if job_id <= 0 then
    logger.error('claude-cli', string.format('jobstart failed with: %d', job_id))
    callback(nil, 'Failed to start claude CLI process')
    return
  end

  -- Send prompt via stdin and close
  vim.fn.chansend(job_id, prompt)
  vim.fn.chanclose(job_id, 'stdin')
  logger.info('claude-cli', 'Prompt sent via stdin')
end

function M.chat(messages, opts)
  opts = opts or {}

  local parts = {}
  for _, msg in ipairs(messages) do
    local role = msg.role == 'ai' and 'assistant' or msg.role
    table.insert(parts, string.format('[%s]: %s', role, msg.content))
  end

  local prompt = table.concat(parts, '\n\n')
  local system_prompt = prompt_builder.get_system_prompt()
  local cmd = build_cmd(system_prompt)

  local result = vim.fn.system(cmd, prompt)
  if vim.v.shell_error ~= 0 then
    error('claude CLI failed: ' .. result)
  end

  return parser.parse(parse_cli_result(result), 'claude')
end

function M.chat_async(messages, opts, callback)
  opts = opts or {}

  local parts = {}
  for _, msg in ipairs(messages) do
    local role = msg.role == 'ai' and 'assistant' or msg.role
    table.insert(parts, string.format('[%s]: %s', role, msg.content))
  end

  local prompt = table.concat(parts, '\n\n')
  local system_prompt = prompt_builder.get_system_prompt()
  local cmd = build_cmd(system_prompt)

  local stdout = {}
  local stderr = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdin = 'pipe',
    env = vim.tbl_extend('force', vim.fn.environ(), { CLAUDECODE = '', ANTHROPIC_API_KEY = '' }),
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then table.insert(stdout, line) end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then table.insert(stderr, line) end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local raw = table.concat(stdout, '\n')

        if code ~= 0 then
          callback(nil, 'claude CLI failed: ' .. table.concat(stderr, '\n'))
          return
        end

        local content_ok, content = pcall(parse_cli_result, raw)
        if not content_ok then
          callback(nil, tostring(content))
          return
        end

        local json_ok, json_data = pcall(vim.json.decode, content)
        if json_ok and json_data.mode == 'chat' then
          callback({
            mode = 'chat',
            content = json_data.explanation or content,
            explanation = json_data.explanation,
          }, nil)
          return
        end

        local parse_ok, parsed = pcall(parser.parse, content, 'claude')
        if parse_ok then
          callback(parsed, nil)
        else
          callback({
            mode = 'chat',
            content = content,
            explanation = content,
          }, nil)
        end
      end)
    end,
  })

  if job_id <= 0 then
    callback(nil, 'Failed to start claude CLI process')
    return
  end

  vim.fn.chansend(job_id, prompt)
  vim.fn.chanclose(job_id, 'stdin')
end

return M
