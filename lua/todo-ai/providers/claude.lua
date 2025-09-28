local M = {}
local providers = require('todo-ai.providers')
local parser = require('todo-ai.parser')
local config = require('todo-ai.config')
local prompt_builder = require('todo-ai.prompt_builder')

M.api_key = vim.env.ANTHROPIC_API_KEY
M.api_url = 'https://api.anthropic.com/v1/messages'
M.default_model = 'claude-3-5-sonnet-20241022' -- Latest Claude 3.5 Sonnet

-- Use centralized prompt builder

function M.complete(instruction, context, opts)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    return nil, 'ANTHROPIC_API_KEY not set'
  end

  local prompt = prompt_builder.build_user_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json',
    ['x-api-key'] = M.api_key,
    ['anthropic-version'] = '2023-06-01'
  }

  local body = vim.fn.json_encode({
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    system = prompt_builder.get_system_prompt(),
    messages = {
      {
        role = 'user',
        content = prompt
      }
    }
  })

  local response, err = providers.request(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = config.get('timeouts').llm_request
  })

  if err then
    return nil, err
  end

  -- Check for API errors
  if response.error then
    return nil, 'Claude API error: ' .. (response.error.message or vim.fn.json_encode(response.error))
  end

  -- Extract content from Claude response
  if response.content and #response.content > 0 then
    local content = response.content[1].text
    return parser.parse(content, 'claude')
  end

  return nil, 'No content in response. Full response: ' .. vim.fn.json_encode(response)
end

function M.complete_async(instruction, context, opts, callback)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  -- Log request details
  local logger = require('todo-ai.logger')
  logger.info('claude', string.format('=== CLAUDE REQUEST START ==='))
  logger.info('claude', string.format('Model: %s, Temperature: %.1f, Max tokens: %d', model, temperature, max_tokens))
  logger.info('claude', string.format('Instruction length: %d chars', #instruction))
  logger.info('claude', string.format('Context length: %d chars', #context))

  -- Show user notification
  vim.schedule(function()
    vim.notify(string.format("📡 Sending to Claude (%s)...", model), vim.log.levels.INFO, { title = "Claude API", timeout = 3000 })
  end)

  if not M.api_key then
    logger.error('claude', 'ANTHROPIC_API_KEY not set!')
    vim.schedule(function()
      vim.notify("❌ ANTHROPIC_API_KEY not set!\n\nSet it in your environment:\nexport ANTHROPIC_API_KEY='your-key-here'",
        vim.log.levels.ERROR, { title = "Claude API", timeout = 5000 })
    end)
    callback(nil, 'ANTHROPIC_API_KEY not set')
    return
  end

  logger.info('claude', 'API key found, building prompt...')

  local prompt = prompt_builder.build_user_prompt(instruction, context)
  logger.info('claude', string.format('Built prompt: %d chars', #prompt))

  local headers = {
    ['content-type'] = 'application/json',
    ['x-api-key'] = M.api_key,
    ['anthropic-version'] = '2023-06-01'
  }

  local body = vim.fn.json_encode({
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    system = prompt_builder.get_system_prompt(),
    messages = {
      {
        role = 'user',
        content = prompt
      }
    }
  })

  logger.info('claude', string.format('Request body size: %d bytes', #body))
  logger.info('claude', string.format('Sending request to: %s', M.api_url))

  providers.request_async(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = config.get('timeouts').llm_request,
    provider = 'claude'  -- Add provider tag for logging
  }, function(success, result)
    logger.info('claude', string.format('Response received - Success: %s', tostring(success)))

    if not success then
      logger.error('claude', string.format('Request failed: %s', tostring(result)))
      vim.schedule(function()
        vim.notify(string.format("❌ Claude request failed:\n%s", tostring(result)),
          vim.log.levels.ERROR, { title = "Claude API", timeout = 5000 })
      end)
      callback(nil, result)
      return
    end

    local response = result

    -- Log response structure
    logger.info('claude', string.format('Response type: %s', type(response)))
    if type(response) == 'table' then
      logger.info('claude', string.format('Response keys: %s', vim.inspect(vim.tbl_keys(response))))
    end

    -- Check for API errors
    if response.error then
      local error_msg = response.error.message or vim.fn.json_encode(response.error)
      logger.error('claude', string.format('API error: %s', error_msg))
      vim.schedule(function()
        vim.notify(string.format("❌ Claude API error:\n%s", error_msg),
          vim.log.levels.ERROR, { title = "Claude API", timeout = 5000 })
      end)
      callback(nil, 'Claude API error: ' .. error_msg)
      return
    end

    -- Extract content from Claude response
    if response.content and #response.content > 0 then
      local content = response.content[1].text
      logger.info('claude', string.format('Got content: %d chars', #content))
      logger.info('claude', string.format('Content preview: %s...', content:sub(1, 100)))

      local parse_success, parsed = pcall(parser.parse, content, 'claude')
      if parse_success then
        logger.info('claude', 'Parse successful!')
        logger.info('claude', string.format('Parsed response keys: %s', vim.inspect(vim.tbl_keys(parsed or {}))))
        callback(parsed, nil)
      else
        logger.error('claude', string.format('Parse failed: %s', tostring(parsed)))
        callback(nil, 'Parser error: ' .. tostring(parsed))
      end
    else
      logger.error('claude', string.format('No content in response: %s', vim.fn.json_encode(response)))
      vim.schedule(function()
        vim.notify("❌ No content in Claude response", vim.log.levels.ERROR, { title = "Claude API", timeout = 5000 })
      end)
      callback(nil, 'No content in response. Full response: ' .. vim.fn.json_encode(response))
    end

    logger.info('claude', '=== CLAUDE REQUEST END ===')
  end)
end

function M.chat(messages, opts)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    return nil, 'ANTHROPIC_API_KEY not set'
  end

  -- Convert messages to Claude format
  local claude_messages = {}
  for _, msg in ipairs(messages) do
    if msg.role == 'system' then
      -- Claude doesn't support system role, convert to user with context
      table.insert(claude_messages, {
        role = 'user',
        content = 'Context: ' .. msg.content
      })
    elseif msg.role == 'ai' then
      table.insert(claude_messages, {
        role = 'assistant',
        content = msg.content
      })
    else
      table.insert(claude_messages, msg)
    end
  end

  local headers = {
    ['content-type'] = 'application/json',
    ['x-api-key'] = M.api_key,
    ['anthropic-version'] = '2023-06-01'
  }

  local body = vim.fn.json_encode({
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    system = prompt_builder.get_system_prompt(),
    messages = claude_messages
  })

  local response, err = providers.request(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = config.get('timeouts').llm_request
  })

  if err then
    return nil, err
  end

  -- Check for API errors
  if response.error then
    return nil, 'Claude API error: ' .. (response.error.message or vim.fn.json_encode(response.error))
  end

  -- Extract content from Claude response
  if response.content and #response.content > 0 then
    local content = response.content[1].text
    local parsed = parser.parse(content, 'claude')
    if parsed.code then
      return parsed
    else
      return { content = content }
    end
  end

  return nil, 'No content in response. Full response: ' .. vim.fn.json_encode(response)
end

function M.chat_async(messages, opts, callback)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    callback(nil, 'ANTHROPIC_API_KEY not set')
    return
  end

  -- Convert messages to Claude format
  local claude_messages = {}
  for _, msg in ipairs(messages) do
    if msg.role == 'system' then
      -- Claude doesn't support system role, convert to user with context
      table.insert(claude_messages, {
        role = 'user',
        content = 'Context: ' .. msg.content
      })
    elseif msg.role == 'ai' then
      table.insert(claude_messages, {
        role = 'assistant',
        content = msg.content
      })
    else
      table.insert(claude_messages, msg)
    end
  end

  local headers = {
    ['content-type'] = 'application/json',
    ['x-api-key'] = M.api_key,
    ['anthropic-version'] = '2023-06-01'
  }

  local body = vim.fn.json_encode({
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    system = prompt_builder.get_system_prompt(),
    messages = claude_messages
  })

  providers.request_async(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = config.get('timeouts').llm_request
  }, function(success, result)
    if not success then
      callback(nil, result)
      return
    end

    local response = result
    -- Check for API errors
    if response.error then
      callback(nil, 'Claude API error: ' .. (response.error.message or vim.fn.json_encode(response.error)))
      return
    end

    -- Extract content from Claude response
    if response.content and #response.content > 0 then
      local content = response.content[1].text

      -- For chat mode, first try to parse as JSON to check for mode
      local json_ok, json_data = pcall(vim.fn.json_decode, content)
      if json_ok and json_data.mode == "chat" then
        -- Pure chat response - just return the explanation as content
        callback({
          mode = "chat",
          content = json_data.explanation or content,
          explanation = json_data.explanation
        }, nil)
        return
      end

      -- Otherwise, use the standard parser for SEARCH/REPLACE responses
      local parse_success, parsed = pcall(parser.parse, content, 'claude')
      if parse_success then
        callback(parsed, nil)
      else
        -- Fallback: if parsing fails, treat as plain content
        callback({
          mode = "chat",
          content = content,
          explanation = content
        }, nil)
      end
    else
      callback(nil, 'No content in response. Full response: ' .. vim.fn.json_encode(response))
    end
  end)
end

return M