local M = {}

-- Try to load logger (optional)
local ok, logger = pcall(require, 'todo-ai.logger')
if not ok then
  -- Create a dummy logger if not available
  logger = {
    debug = function() end,
    info = function() end,
    error = function() end
  }
end

-- Parse response from LLM
function M.parse(response, hint)
  logger.debug('Parsing response', { hint = hint, response_length = #response })

  local result = {
    raw_response = response,
    format_detected = 'unknown',
    parsed_sections = {},
    thinking = nil
  }

  -- Extract and preserve thinking tags
  local thinking_content = M.extract_thinking_tags(response)
  if thinking_content then
    result.thinking = thinking_content
    result.thinking_formatted = M.format_thinking(thinking_content)
    -- Remove thinking tags from main response for parsing
    response = M.remove_thinking_tags(response)
  end

  -- Extract assistant tags if present
  local assistant_content = response:match('<assistant>(.-)</assistant>')
  if assistant_content then
    response = assistant_content
  end

  -- Detect format
  local format = M.detect_format(response)

  -- Special handling for Claude responses
  if hint and hint:lower():match('claude') then
    -- Try JSON first for Claude since we request it
    if response:match('^%s*{') and response:match('}%s*$') then
      local ok = pcall(vim.fn.json_decode, response)
      if ok then
        format = 'json_response'
        logger.debug('Detected JSON response from Claude')
      end
    elseif format == 'mixed_format' and M.looks_like_code(response) then
      -- Fallback to plain code if not JSON
      format = 'plain_code'
      logger.debug('Detected plain code response from Claude')
    end
  end

  result.format_detected = format

  -- Parse based on format
  if format == 'xml_structured' then
    M.parse_xml_structured(response, result)
  elseif format == 'json_response' then
    M.parse_json_response(response, result)
  elseif format == 'markdown_formatted' then
    M.parse_markdown_formatted(response, result)
  elseif format == 'plain_code' then
    result.code = response:gsub('^%s+', ''):gsub('%s+$', '')
    result.explanation = 'Generated code'
  else
    M.parse_generic(response, result)
  end

  logger.debug('Parse result', {
    format_detected = result.format_detected,
    has_code = result.code ~= nil,
    has_thinking = result.thinking ~= nil
  })

  return result
end

function M.detect_format(response)
  response = response:gsub('^%s+', ''):gsub('%s+$', '')

  -- Check for XML-like structure
  if response:match('<%w+>.-</%w+>') then
    return 'xml_structured'
  end

  -- Check for JSON
  if response:match('^%s*{') and response:match('}%s*$') then
    local ok = pcall(vim.fn.json_decode, response)
    if ok then
      return 'json_response'
    end
  end

  -- Check for markdown code blocks
  if response:match('```') then
    return 'markdown_formatted'
  end

  -- Check if it looks like code
  if M.looks_like_code(response) then
    return 'plain_code'
  end

  return 'mixed_format'
end

function M.looks_like_code(text)
  -- Common code patterns
  local patterns = {
    '^%s*def%s+',          -- Python function
    '^%s*class%s+',        -- Class definition
    '^%s*function%s+',     -- JavaScript/Lua function
    '^%s*const%s+',        -- JavaScript const
    '^%s*let%s+',          -- JavaScript let
    '^%s*var%s+',          -- Variable declaration
    '^%s*import%s+',       -- Import statement
    '^%s*from%s+',         -- Python from import
    '^%s*export%s+',       -- Export statement
    '^%s*if%s*[%(%:]',     -- If statement (Python or other)
    '^%s*for%s+',          -- For loop
    '^%s*while%s+',        -- While loop
    '^%s*return%s+',       -- Return statement
    '^%s*print%(',         -- Print statement
    '^%s*try:',            -- Python try block
    '^%s*except',          -- Python except
    '[{}%;]',              -- Code delimiters
    '=>',                  -- Arrow function
    '%-%>',                -- Arrow operator
    '::',                  -- Scope operator
    '=%s*["\']',           -- String assignment
    '%.%w+%(', -- Method call
  }

  local lines = vim.split(text, '\n')
  local code_lines = 0
  local non_empty_lines = 0

  -- Quick check: if starts with import or def, it's likely code
  local first_line = lines[1] or ""
  if first_line:match('^import%s') or first_line:match('^from%s') or
     first_line:match('^def%s') or first_line:match('^class%s') then
    return true
  end

  for _, line in ipairs(lines) do
    if line:match('%S') then  -- Non-empty line
      non_empty_lines = non_empty_lines + 1
      for _, pattern in ipairs(patterns) do
        if line:match(pattern) then
          code_lines = code_lines + 1
          break
        end
      end
    end
  end

  -- If more than 40% of non-empty lines look like code (lowered threshold)
  if non_empty_lines > 0 then
    return (code_lines / non_empty_lines) > 0.4
  end
  return false
end

function M.extract_thinking_tags(response)
  local thinking_sections = {}

  -- Patterns for various thinking tags
  local patterns = {
    { pattern = '<think>(.-)</think>', name = 'thinking' },
    { pattern = '<thinking>(.-)</thinking>', name = 'thinking' },
    { pattern = '<thought>(.-)</thought>', name = 'thought' },
    { pattern = '<reasoning>(.-)</reasoning>', name = 'reasoning' },
    { pattern = '<analysis>(.-)</analysis>', name = 'analysis' },
    { pattern = '<planning>(.-)</planning>', name = 'planning' },
    { pattern = '<approach>(.-)</approach>', name = 'approach' },
    { pattern = '<strategy>(.-)</strategy>', name = 'strategy' },
    { pattern = '<scratch>(.-)</scratch>', name = 'scratch' },
    { pattern = '<work>(.-)</work>', name = 'work' },
    { pattern = '<internal>(.-)</internal>', name = 'internal' },
  }

  for _, p in ipairs(patterns) do
    for match in response:gmatch(p.pattern) do
      if thinking_sections[p.name] then
        thinking_sections[p.name] = thinking_sections[p.name] .. '\n\n' .. match:gsub('^%s+', ''):gsub('%s+$', '')
      else
        thinking_sections[p.name] = match:gsub('^%s+', ''):gsub('%s+$', '')
      end
    end
  end

  if next(thinking_sections) then
    return thinking_sections
  end
  return nil
end

function M.remove_thinking_tags(response)
  -- Remove all thinking-like tags
  local patterns = {
    '<think>.-</think>',
    '<thinking>.-</thinking>',
    '<thought>.-</thought>',
    '<reasoning>.-</reasoning>',
    '<analysis>.-</analysis>',
    '<planning>.-</planning>',
    '<approach>.-</approach>',
    '<strategy>.-</strategy>',
    '<scratch>.-</scratch>',
    '<work>.-</work>',
    '<internal>.-</internal>',
  }

  for _, pattern in ipairs(patterns) do
    response = response:gsub(pattern, '')
  end

  return response:gsub('^%s+', ''):gsub('%s+$', '')
end

function M.format_thinking(thinking_sections)
  local formatted = {}

  table.insert(formatted, '## 🧠 AI Thinking Process\n')

  -- Map tag types to nice headers
  local tag_display = {
    thinking = { header = '💭 Thinking', content = thinking_sections.thinking },
    thought = { header = '💡 Thoughts', content = thinking_sections.thought },
    reasoning = { header = '🔍 Reasoning', content = thinking_sections.reasoning },
    analysis = { header = '📊 Analysis', content = thinking_sections.analysis },
    planning = { header = '📋 Planning', content = thinking_sections.planning },
    approach = { header = '🎯 Approach', content = thinking_sections.approach },
    strategy = { header = '♟️ Strategy', content = thinking_sections.strategy },
    scratch = { header = '📝 Scratch Work', content = thinking_sections.scratch },
    work = { header = '⚙️ Work', content = thinking_sections.work },
    internal = { header = '🔒 Internal Process', content = thinking_sections.internal },
  }

  for _, tag_data in pairs(tag_display) do
    if tag_data.content then
      table.insert(formatted, string.format('### %s\n', tag_data.header))

      -- Format content nicely
      local lines = vim.split(tag_data.content, '\n')
      for _, line in ipairs(lines) do
        line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if line ~= '' then
          -- Check if it's a list item
          if line:match('^[%-%*%+]%s') or line:match('^%d+%.%s') then
            table.insert(formatted, line)
          else
            table.insert(formatted, line)
          end
        else
          table.insert(formatted, '')
        end
      end

      table.insert(formatted, '') -- Add spacing between sections
    end
  end

  table.insert(formatted, '---\n') -- Separator after thinking
  return table.concat(formatted, '\n')
end

function M.parse_xml_structured(response, result)
  -- Extract code from XML tags
  local code_patterns = {
    '<code>(.-)</code>',
    '<implementation>(.-)</implementation>',
    '<solution>(.-)</solution>',
    '<answer>(.-)</answer>',
  }

  for _, pattern in ipairs(code_patterns) do
    local match = response:match(pattern)
    if match then
      result.code = match:gsub('^%s+', ''):gsub('%s+$', '')
      break
    end
  end

  -- Extract explanation
  local explanation_patterns = {
    '<explanation>(.-)</explanation>',
    '<description>(.-)</description>',
    '<reasoning>(.-)</reasoning>',
    '<context>(.-)</context>',
  }

  for _, pattern in ipairs(explanation_patterns) do
    local match = response:match(pattern)
    if match then
      result.explanation = match:gsub('^%s+', ''):gsub('%s+$', '')
      break
    end
  end

  -- Parse all XML tags into sections
  for tag, content in response:gmatch('<(%w+)>(.-)</%1>') do
    result.parsed_sections[tag] = content:gsub('^%s+', ''):gsub('%s+$', '')
  end
end

function M.parse_json_response(response, result)
  -- Check if JSON looks complete first
  if not response:match('}%s*$') then
    logger.error('Incomplete JSON response - missing closing brace')
    result.parse_error = "JSON response appears incomplete (no closing }). Response may have been cut off due to length or timeout."
    return
  end

  local ok, data = pcall(vim.fn.json_decode, response)
  if not ok then
    logger.error('Failed to parse JSON response', { error = data })
    -- Return the raw error - don't try to recover
    result.parse_error = "JSON parsing failed: " .. tostring(data)
    return
  end

  -- DIRECT ASSIGNMENT - No guessing, just copy what's there
  -- The validator will check if required fields are present

  result.mode = data.mode
  result.filename = data.filename
  result.changes = data.changes
  result.language = data.language
  result.explanation = data.explanation

  -- Store raw data for debugging
  result.raw_json = data

  logger.debug('JSON response parsed - fields extracted directly')
end

function M.parse_markdown_formatted(response, result)
  -- Extract ALL code blocks and combine them
  local code_blocks = {}
  local all_code = {}

  for lang, code in response:gmatch('```(%w*)%s*\n(.-)\n```') do
    -- Special case: if it's JSON code block with our expected schema, parse it as JSON
    if lang == 'json' or (lang == '' and code:match('^%s*{.*"changes"%s*:.*}%s*$')) then
      local ok, data = pcall(vim.fn.json_decode, code)
      if ok and data.changes then
        -- This is our expected SEARCH/REPLACE format but wrapped in markdown
        logger.info('Parser warning: AI wrapped JSON in markdown code block - should return raw JSON')
        result.changes = data.changes
        result.language = data.language
        result.explanation = data.explanation or 'Generated changes'
        result.format_detected = 'json_response'
        result.warning = "JSON was wrapped in ```json``` - AI should return raw JSON only"
        return
      end
    end

    table.insert(code_blocks, {lang = lang, code = code})
    table.insert(all_code, code)
  end

  -- Extract explanation (text outside code blocks)
  local explanation_text = response:gsub('```%w*%s*\n.-\n```', ''):gsub('^%s+', ''):gsub('%s+$', '')

  -- Special handling for Claude's broken responses where function bodies are in explanation
  if #code_blocks > 0 then
    local first_code = code_blocks[1].code

    -- Check if the code block contains only function signatures (no bodies)
    local has_only_signatures = false
    if first_code:match('def%s+%w+%([^)]*%):%s*$') or
       first_code:match('def%s+%w+%([^)]*%):\n?$') then
      -- Count actual function implementations
      local impl_count = 0
      for line in first_code:gmatch('[^\n]+') do
        if line:match('^%s+') and not line:match('^%s*def%s') then
          impl_count = impl_count + 1
        end
      end
      has_only_signatures = impl_count < 3
    end

    -- If we have incomplete code and the explanation looks like it has the full implementation
    if has_only_signatures and explanation_text and M.looks_like_code(explanation_text) then
      -- Try to reconstruct the full code
      local full_code = {}

      -- Parse the explanation to extract the complete code
      local in_func = false
      local current_indent = 0

      for line in explanation_text:gmatch('[^\n]*') do
        -- Check if this looks like function implementation
        if line:match('^%s*def%s+') or line:match('^class%s+') or
           line:match('^%s+[%w_]+%s*=') or line:match('^%s+return%s') or
           line:match('^%s+for%s') or line:match('^%s+if%s') or
           line:match('^%s+while%s') or line:match('^%s+print%(') or
           line:match('^%s+"""') or line:match("^%s+'") then
          table.insert(full_code, line)
          in_func = true
        elseif in_func and (line:match('^%s+') or line == '') then
          table.insert(full_code, line)
        elseif line:match('^import%s') or line:match('^from%s') then
          table.insert(full_code, line)
        end
      end

      if #full_code > #vim.split(first_code, '\n') then
        result.code = table.concat(full_code, '\n')
        result.explanation = 'Code reconstructed from response'
      else
        result.code = first_code:gsub('^%s+', ''):gsub('%s+$', '')
      end
    else
      -- Use the code block as-is
      result.code = first_code:gsub('^%s+', ''):gsub('%s+$', '')
    end

    result.code_language = code_blocks[1].lang ~= '' and code_blocks[1].lang or 'python'

    -- Only use explanation if it doesn't look like code
    if not M.looks_like_code(explanation_text) then
      result.explanation = explanation_text
    end
  elseif M.looks_like_code(explanation_text) then
    -- No code blocks but explanation is code
    result.code = explanation_text
    result.explanation = 'Generated code'
  else
    result.explanation = explanation_text
  end

  -- Log for debugging
  logger.debug('Markdown parsing', {
    code_blocks_found = #code_blocks,
    code_length = result.code and #result.code or 0,
    has_explanation = result.explanation ~= nil,
    looks_like_truncated = result.code and result.code:match('def%s+%w+%([^)]*%):%s*\n?$') ~= nil
  })
end

function M.parse_generic(response, result)
  -- Try to extract code blocks first
  for lang, code in response:gmatch('```(%w*)%s*\n(.-)\n```') do
    result.code = code:gsub('^%s+', ''):gsub('%s+$', '')
    return
  end

  -- If it looks like code, treat it as plain code
  if M.looks_like_code(response) then
    result.code = response:gsub('^%s+', ''):gsub('%s+$', '')
    result.explanation = 'Generated code'
    return
  end

  -- Try to separate code from explanation
  local lines = vim.split(response, '\n')
  local code_lines = {}
  local explanation_lines = {}
  local in_code = false

  for _, line in ipairs(lines) do
    if M.looks_like_code(line) then
      in_code = true
      table.insert(code_lines, line)
    elseif in_code and line:gsub('^%s+', ''):gsub('%s+$', '') == '' then
      table.insert(code_lines, line)
    else
      in_code = false
      table.insert(explanation_lines, line)
    end
  end

  if #code_lines > 0 then
    result.code = table.concat(code_lines, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
  end
  if #explanation_lines > 0 then
    result.explanation = table.concat(explanation_lines, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
  end
end

return M