local M = {}
local providers = require('todo-ai.providers')
local parser = require('todo-ai.parser')

M.api_url = vim.env.OLLAMA_URL or 'http://localhost:11434'
M.default_model = 'llama3.2' -- User can specify any model name

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

  local prompt = M.build_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json'
  }

  local body = vim.fn.json_encode({
    model = model,
    prompt = prompt,
    temperature = temperature,
    stream = false
  })

  local response, err = providers.request(M.api_url .. '/api/generate', {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 60  -- Ollama can be slow
  })

  if err then
    return nil, err
  end

  -- Extract response from Ollama
  if response.response then
    return parser.parse(response.response, 'ollama')
  end

  return nil, 'No response from Ollama'
end

function M.complete_async(instruction, context, opts, callback)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7

  local prompt = M.build_prompt(instruction, context)

  local headers = {
    ['content-type'] = 'application/json'
  }

  local body = vim.fn.json_encode({
    model = model,
    prompt = prompt,
    temperature = temperature,
    stream = false
  })

  providers.request_async(M.api_url .. '/api/generate', {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 60
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    if response.response then
      local parsed = parser.parse(response.response, 'ollama')
      callback(parsed, nil)
    else
      callback(nil, 'No response from Ollama')
    end
  end)
end

function M.chat(messages, opts)
  opts = opts or {}
  local model = opts.model or M.default_model
  local temperature = opts.temperature or 0.7

  -- Convert messages to Ollama format
  local ollama_messages = {}
  for _, msg in ipairs(messages) do
    table.insert(ollama_messages, {
      role = msg.role == 'ai' and 'assistant' or msg.role,
      content = msg.content
    })
  end

  local headers = {
    ['content-type'] = 'application/json'
  }

  local body = vim.fn.json_encode({
    model = model,
    messages = ollama_messages,
    temperature = temperature,
    stream = false
  })

  local response, err = providers.request(M.api_url .. '/api/chat', {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 60
  })

  if err then
    return nil, err
  end

  -- Extract content from Ollama response
  if response.message and response.message.content then
    local content = response.message.content
    local parsed = parser.parse(content, 'ollama')
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

  -- Convert messages to Ollama format
  local ollama_messages = {}
  for _, msg in ipairs(messages) do
    table.insert(ollama_messages, {
      role = msg.role == 'ai' and 'assistant' or msg.role,
      content = msg.content
    })
  end

  local headers = {
    ['content-type'] = 'application/json'
  }

  local body = vim.fn.json_encode({
    model = model,
    messages = ollama_messages,
    temperature = temperature,
    stream = false
  })

  providers.request_async(M.api_url .. '/api/chat', {
    method = 'POST',
    headers = headers,
    body = body,
    timeout = 60
  }, function(response, err)
    if err then
      callback(nil, err)
      return
    end

    if response.message and response.message.content then
      local content = response.message.content
      local parsed = parser.parse(content, 'ollama')
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

-- Check if Ollama is available
function M.is_available()
  local response, err = providers.request(M.api_url .. '/api/tags', {
    method = 'GET',
    timeout = 5
  })
  return response ~= nil and err == nil
end

return M