---@class LLMValidator
---@field validators table<string, function>
---@field retry_count number
---@field max_retries number
local M = {}

M.validators = {}
M.retry_count = 0
M.max_retries = 3

---Validate code changes from LLM
---@param changes table[]
---@return boolean valid
---@return string|nil error
---@return table|nil fixed_changes
function M.validate_code_changes(changes)
  if not changes or type(changes) ~= 'table' then
    return false, "Invalid changes format: expected table", nil
  end

  local errors = {}
  local fixed_changes = {}

  for i, change in ipairs(changes) do
    -- Validate required fields
    if not change.start_line or type(change.start_line) ~= 'number' then
      table.insert(errors, string.format("Change %d: missing or invalid start_line", i))
    end

    if not change.end_line or type(change.end_line) ~= 'number' then
      table.insert(errors, string.format("Change %d: missing or invalid end_line", i))
    end

    if change.start_line and change.end_line and change.start_line > change.end_line then
      -- Try to fix by swapping
      local fixed = vim.deepcopy(change)
      fixed.start_line, fixed.end_line = change.end_line, change.start_line
      table.insert(fixed_changes, fixed)
      table.insert(errors, string.format("Change %d: start_line > end_line (auto-fixed)", i))
    elseif change.start_line and change.start_line < 1 then
      -- Fix invalid line numbers
      local fixed = vim.deepcopy(change)
      fixed.start_line = 1
      table.insert(fixed_changes, fixed)
      table.insert(errors, string.format("Change %d: invalid start_line (auto-fixed to 1)", i))
    else
      table.insert(fixed_changes, change)
    end

    -- Validate code content
    if not change.code or type(change.code) ~= 'string' then
      table.insert(errors, string.format("Change %d: missing or invalid code", i))
    elseif #change.code > 100000 then
      table.insert(errors, string.format("Change %d: code too large (%d chars)", i, #change.code))
    end
  end

  if #errors > 0 then
    return false, table.concat(errors, "\n"), fixed_changes
  end

  return true, nil, fixed_changes
end

---Validate LLM chat response
---@param response table
---@return boolean valid
---@return string|nil error
---@return table|nil cleaned_response
function M.validate_chat_response(response)
  if not response or type(response) ~= 'table' then
    return false, "Invalid response format", nil
  end

  local cleaned = {}

  -- Check for content or explanation
  if not response.content and not response.explanation then
    return false, "Response missing content or explanation", nil
  end

  -- Clean and validate content
  if response.content then
    if type(response.content) ~= 'string' then
      -- Try to convert to string
      cleaned.content = tostring(response.content)
    else
      cleaned.content = response.content
    end

    -- Remove potential injection attempts
    cleaned.content = M.sanitize_content(cleaned.content)
  end

  -- Validate and clean changes if present
  if response.changes then
    local valid, err, fixed = M.validate_code_changes(response.changes)
    if not valid and not fixed then
      return false, "Invalid code changes: " .. err, nil
    end
    cleaned.changes = fixed or response.changes
  end

  -- Copy other safe fields
  cleaned.explanation = response.explanation
  cleaned.success = response.success
  cleaned.error = response.error

  return true, nil, cleaned
end

---Sanitize content to prevent injection
---@param content string
---@return string
function M.sanitize_content(content)
  -- Remove potential vim command injections
  content = content:gsub(':!.*\n', '')
  content = content:gsub(':%s*!', '')

  -- Remove shell command injections
  content = content:gsub('`[^`]*`', function(match)
    -- Check if it's a code block (safe) or command execution (unsafe)
    if match:match('^`[^`\n]+`$') and match:match('[;&|<>]') then
      return '`[command sanitized]`'
    end
    return match
  end)

  -- Remove script tags (if somehow present)
  content = content:gsub('<script[^>]*>.*</script>', '')

  return content
end

---Validate diff format
---@param diff_text string
---@return boolean valid
---@return string|nil error
---@return string|nil fixed_diff
function M.validate_diff(diff_text)
  if not diff_text or type(diff_text) ~= 'string' then
    return false, "Invalid diff format", nil
  end

  local lines = vim.split(diff_text, '\n')
  local fixed_lines = {}
  local has_header = false
  local errors = {}

  for i, line in ipairs(lines) do
    -- Check for diff header
    if line:match('^@@%s*%-(%d+)') then
      has_header = true
      table.insert(fixed_lines, line)
    elseif line:match('^%+') or line:match('^%-') or line:match('^%s') then
      -- Valid diff line
      table.insert(fixed_lines, line)
    elseif line == '' then
      -- Empty line is ok
      table.insert(fixed_lines, line)
    else
      -- Invalid line, try to fix
      if has_header then
        -- Assume it's context and add space prefix
        table.insert(fixed_lines, ' ' .. line)
        table.insert(errors, string.format("Line %d: added missing context prefix", i))
      else
        table.insert(fixed_lines, line)
      end
    end
  end

  if not has_header then
    return false, "Missing diff header", nil
  end

  if #errors > 0 then
    local fixed_diff = table.concat(fixed_lines, '\n')
    return false, table.concat(errors, '\n'), fixed_diff
  end

  return true, nil, diff_text
end

---Validate JSON response from LLM
---@param json_str string
---@return boolean valid
---@return any|nil data
---@return string|nil error
function M.validate_json(json_str)
  if not json_str or type(json_str) ~= 'string' then
    return false, nil, "Invalid JSON string"
  end

  -- Remove markdown code blocks if present
  json_str = json_str:gsub('^```json?\n', ''):gsub('\n```$', '')

  -- Try to parse
  local ok, result = pcall(vim.fn.json_decode, json_str)
  if not ok then
    -- Try to fix common issues
    local fixed = json_str

    -- Fix trailing commas
    fixed = fixed:gsub(',(%s*[}%]])', '%1')

    -- Fix single quotes
    fixed = fixed:gsub("'", '"')

    -- Try again
    ok, result = pcall(vim.fn.json_decode, fixed)
    if not ok then
      return false, nil, "Invalid JSON: " .. tostring(result)
    end
  end

  return true, result, nil
end

---Create validation error prompt for LLM
---@param original_prompt string
---@param validation_errors string
---@param attempt number
---@return string
function M.create_retry_prompt(original_prompt, validation_errors, attempt)
  return string.format([[
Your previous response had validation errors that need to be fixed.

VALIDATION ERRORS (Attempt %d/%d):
%s

ORIGINAL REQUEST:
%s

Please provide a corrected response that addresses these validation errors.
Make sure to:
1. Use valid line numbers (starting from 1)
2. Ensure start_line <= end_line
3. Provide valid code strings
4. Include all required fields

Respond with the corrected changes in the same format.]],
    attempt, M.max_retries, validation_errors, original_prompt)
end

---Validate and potentially retry LLM request
---@param provider table
---@param messages table
---@param config table
---@param callback function
function M.validated_request(provider, messages, config, callback)
  local attempt = 1
  local original_messages = vim.deepcopy(messages)

  local function make_request()
    provider.chat_async(messages, config, function(response, error)
      if error then
        callback(nil, error)
        return
      end

      -- Validate response
      local valid, err, cleaned = M.validate_chat_response(response)

      if valid then
        -- Success
        callback(cleaned, nil)
      elseif attempt < M.max_retries and cleaned then
        -- Validation failed but we have a cleaned version, try to use it
        callback(cleaned, "Validation failed but auto-fixed: " .. err)
      elseif attempt < M.max_retries then
        -- Retry with error feedback
        attempt = attempt + 1

        -- Add validation error to messages
        local retry_messages = vim.deepcopy(original_messages)
        table.insert(retry_messages, {
          role = 'system',
          content = M.create_retry_prompt(
            messages[#messages].content or "",
            err or "Invalid response format",
            attempt
          )
        })

        messages = retry_messages
        vim.defer_fn(make_request, 1000)  -- Wait 1 second before retry
      else
        -- Max retries reached
        callback(nil, string.format("Validation failed after %d attempts: %s", attempt, err))
      end
    end)
  end

  make_request()
end

---Validate file path
---@param path string
---@return boolean valid
---@return string|nil sanitized_path
function M.validate_file_path(path)
  if not path or type(path) ~= 'string' then
    return false, nil
  end

  -- Remove dangerous characters
  local sanitized = path:gsub('%.%./', '')  -- Remove directory traversal
  sanitized = sanitized:gsub('^/', '')       -- Remove absolute paths
  sanitized = sanitized:gsub('[<>:"|?*]', '') -- Remove invalid characters

  -- Check length
  if #sanitized > 255 then
    return false, nil
  end

  -- Ensure it's within project directory
  local cwd = vim.fn.getcwd()
  local full_path = cwd .. '/' .. sanitized

  -- Validate it's under cwd
  if not vim.startswith(full_path, cwd) then
    return false, nil
  end

  return true, sanitized
end

---Validate buffer operations
---@param bufnr number
---@param start_line number
---@param end_line number
---@return boolean valid
---@return string|nil error
function M.validate_buffer_operation(bufnr, start_line, end_line)
  -- Validate buffer
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Invalid buffer"
  end

  -- Get line count
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Validate line numbers
  if start_line < 1 then
    return false, "start_line must be >= 1"
  end

  if end_line > line_count then
    return false, string.format("end_line (%d) exceeds buffer lines (%d)", end_line, line_count)
  end

  if start_line > end_line then
    return false, "start_line > end_line"
  end

  return true, nil
end

---Register custom validator
---@param name string
---@param validator function
function M.register_validator(name, validator)
  M.validators[name] = validator
end

---Run custom validators
---@param name string
---@param data any
---@return boolean valid
---@return string|nil error
function M.run_validator(name, data)
  local validator = M.validators[name]
  if not validator then
    return true, nil  -- No validator registered, assume valid
  end

  return validator(data)
end

return M