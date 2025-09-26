local M = {}
local providers = require('todo-ai.providers')
local parser = require('todo-ai.parser')

M.api_key = vim.env.OPENAI_API_KEY
M.api_url = 'https://api.openai.com/v1/chat/completions'
M.default_model = 'gpt-4o' -- User can specify any model name

function M.build_prompt(instruction, context)
  return string.format([[
You are a helpful coding assistant. Complete the following task.

Task: %s

Context:
%s

Provide ONLY the code implementation to replace the TODO comment. Do not include any explanations, comments, or markdown formatting. Just the raw code.

Example response for "write a hello world function":
def hello_world():
    print("Hello, world!")

Now provide the code for the task above:]], instruction, context)
end

function M.complete(instruction, context, opts)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    return nil, 'OPENAI_API_KEY not set'
  end

  local prompt = M.build_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. M.api_key
  }

  local body = vim.fn.json_encode({
    model = model,
    messages = {
      {
        role = 'user',
        content = prompt
      }
    },
    temperature = temperature,
    max_tokens = max_tokens
  })

  local response, err = providers.request(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body
  })

  if err then
    return nil, err
  end

  -- Extract content from OpenAI response
  if response.choices and #response.choices > 0 then
    local content = response.choices[1].message.content
    return parser.parse(content, 'openai')
  end

  return nil, 'No content in response'
end

function M.complete_async(instruction, context, opts, callback)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    callback(nil, 'OPENAI_API_KEY not set')
    return
  end

  local prompt = M.build_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. M.api_key
  }

  local body = vim.fn.json_encode({
    model = model,
    messages = {
      {
        role = 'user',
        content = prompt
      }
    },
    temperature = temperature,
    max_tokens = max_tokens
  })

  providers.request_async(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    if response.choices and #response.choices > 0 then
      local content = response.choices[1].message.content
      local parsed = parser.parse(content, 'openai')
      callback(parsed, nil)
    else
      callback(nil, 'No content in response')
    end
  end)
end

function M.chat(messages, opts)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    return nil, 'OPENAI_API_KEY not set'
  end

  -- Convert messages to OpenAI format
  local openai_messages = {}
  for _, msg in ipairs(messages) do
    table.insert(openai_messages, {
      role = msg.role == 'ai' and 'assistant' or msg.role,
      content = msg.content
    })
  end

  local headers = {
    ['content-type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. M.api_key
  }

  local body = vim.fn.json_encode({
    model = model,
    messages = openai_messages,
    temperature = temperature,
    max_tokens = max_tokens
  })

  local response, err = providers.request(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body
  })

  if err then
    return nil, err
  end

  -- Extract content from OpenAI response
  if response.choices and #response.choices > 0 then
    local content = response.choices[1].message.content
    local parsed = parser.parse(content, 'openai')
    if parsed.code then
      return parsed
    else
      return { content = content }
    end
  end

  return nil, 'No content in response'
end

function M.chat_async(messages, opts, callback)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7
  local max_tokens = opts.max_tokens or 4096

  if not M.api_key then
    callback(nil, 'OPENAI_API_KEY not set')
    return
  end

  -- Convert messages to OpenAI format
  local openai_messages = {}
  for _, msg in ipairs(messages) do
    table.insert(openai_messages, {
      role = msg.role == 'ai' and 'assistant' or msg.role,
      content = msg.content
    })
  end

  local headers = {
    ['content-type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. M.api_key
  }

  local body = vim.fn.json_encode({
    model = model,
    messages = openai_messages,
    temperature = temperature,
    max_tokens = max_tokens
  })

  providers.request_async(M.api_url, {
    method = 'POST',
    headers = headers,
    body = body
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    if response.choices and #response.choices > 0 then
      local content = response.choices[1].message.content
      local parsed = parser.parse(content, 'openai')
      if parsed.code then
        callback(parsed, nil)
      else
        callback({ content = content }, nil)
      end
    else
      callback(nil, 'No content in response')
    end
  end)
end

return M