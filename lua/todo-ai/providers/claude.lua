local M = {}
local providers = require('todo-ai.providers')
local parser = require('todo-ai.parser')

M.api_key = vim.env.ANTHROPIC_API_KEY
M.api_url = 'https://api.anthropic.com/v1/messages'
M.default_model = 'claude-3-5-sonnet-20241022' -- Latest Claude 3.5 Sonnet

function M.build_prompt(instruction, context)
  return string.format([[
Task: %s

Context:
%s

Respond with ONLY valid JSON:
{
  "code": "complete implementation to replace TODO",
  "explanation": "what the code does"
}

Important: Include the COMPLETE code in the "code" field. Escape quotes properly for valid JSON.]], instruction, context)
end

function M.complete(instruction, context, opts)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    return nil, 'ANTHROPIC_API_KEY not set'
  end

  local prompt = M.build_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json',
    ['x-api-key'] = M.api_key,
    ['anthropic-version'] = '2023-06-01'
  }

  local body = vim.fn.json_encode({
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
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
    timeout = 300  -- 5 minute timeout for Claude
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

  if not M.api_key then
    callback(nil, 'ANTHROPIC_API_KEY not set')
    return
  end

  local prompt = M.build_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json',
    ['x-api-key'] = M.api_key,
    ['anthropic-version'] = '2023-06-01'
  }

  local body = vim.fn.json_encode({
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    messages = {
      {
        role = 'user',
        content = prompt
      }
    }
  })

  providers.request_async(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 300  -- 5 minute timeout for Claude
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    -- Check for API errors
    if response.error then
      callback(nil, 'Claude API error: ' .. (response.error.message or vim.fn.json_encode(response.error)))
      return
    end

    -- Extract content from Claude response
    if response.content and #response.content > 0 then
      local content = response.content[1].text
      local parsed = parser.parse(content, 'claude')
      callback(parsed, nil)
    else
      callback(nil, 'No content in response. Full response: ' .. vim.fn.json_encode(response))
    end
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
    messages = claude_messages
  })

  local response, err = providers.request(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 300  -- 5 minute timeout for Claude
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
    messages = claude_messages
  })

  providers.request_async(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 300  -- 5 minute timeout for Claude
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    -- Check for API errors
    if response.error then
      callback(nil, 'Claude API error: ' .. (response.error.message or vim.fn.json_encode(response.error)))
      return
    end

    -- Extract content from Claude response
    if response.content and #response.content > 0 then
      local content = response.content[1].text
      local parsed = parser.parse(content, 'claude')
      if parsed.code then
        callback(parsed, nil)
      else
        callback({ content = content }, nil)
      end
    else
      callback(nil, 'No content in response. Full response: ' .. vim.fn.json_encode(response))
    end
  end)
end

return M