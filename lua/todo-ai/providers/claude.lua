local M = {}
local providers = require('todo-ai.providers')
local parser = require('todo-ai.parser')

M.api_key = vim.env.ANTHROPIC_API_KEY
M.api_url = 'https://api.anthropic.com/v1/messages'
M.default_model = 'claude-3-5-sonnet-20241022' -- Latest Claude 3.5 Sonnet

-- System prompt for all Claude interactions
function M.get_system_prompt()
  local schema = require('todo-ai.schema')
  return string.format([[
You are a code assistant integrated into Neovim. You must ALWAYS respond with valid JSON following this schema:

%s

Rules:
1. ALWAYS use the "changes" array for any code modifications to files
2. Use "code_snippet" ONLY for showing example code in chat (won't modify files)
3. For each change, specify exact start_line and end_line (1-indexed)
4. The "code" field in changes should contain ONLY the replacement code
5. Include "description" for each change explaining what it does
6. Include overall "explanation" summarizing all changes
7. Maintain original indentation in replaced code
8. Escape all quotes properly for valid JSON
9. NEVER include markdown formatting in JSON values
10. For new files, use "new_file" with path and single change starting at line 1

Examples:
%s]],
    schema.get_schema_description(),
    vim.fn.json_encode(schema.examples.multiple_changes))
end

function M.build_prompt(instruction, context)
  -- Parse context if it's JSON
  local context_obj = nil
  local ok, parsed = pcall(vim.fn.json_decode, context)
  if ok then
    context_obj = parsed
  end

  -- Build appropriate prompt based on context
  if context_obj and context_obj.selected_text then
    -- Visual selection mode
    return string.format([[
File: %s
Language: %s

Full file content:
%s

The user has selected lines %d-%d:
```
%s
```

Task: %s

Create a "changes" array entry to replace lines %d-%d with the new implementation.]],
      context_obj.file_path or 'unknown',
      context_obj.language or 'unknown',
      context_obj.file_content or '',
      context_obj.line_number or 0,
      context_obj.end_line or context_obj.line_number or 0,
      context_obj.selected_text or '',
      instruction,
      context_obj.line_number or 0,
      context_obj.end_line or context_obj.line_number or 0)
  elseif context_obj and context_obj.line_number then
    -- TODO mode - we know the line number
    return string.format([[
File: %s
Language: %s

Full file content:
%s

TODO at line %d: %s

Context around TODO:
%s

Create a "changes" array entry to replace the TODO at line %d.]],
      context_obj.file_path or 'unknown',
      context_obj.language or 'unknown',
      context_obj.file_content or '',
      context_obj.line_number or 0,
      instruction,
      vim.fn.json_encode(context_obj.surrounding_lines or {}),
      context_obj.line_number or 0)
  else
    -- Chat mode or general query
    return string.format([[
Task: %s

Context:
%s

Provide appropriate response using the JSON schema. Use "code_snippet" for examples, "changes" for file modifications.]],
      instruction,
      context)
  end
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
    system = M.get_system_prompt(),
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
    system = M.get_system_prompt(),
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
    system = M.get_system_prompt(),
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
    system = M.get_system_prompt(),
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