-- Centralized prompt building for all providers
local M = {}

-- Build system prompt that all providers should use
function M.get_system_prompt()
  -- Use prompt_config which has the updated mode detection rules
  local prompt_config = require('todo-ai.prompt_config')
  return prompt_config.get_schema_description()
end

-- Build user prompt based on context
function M.build_user_prompt(instruction, context)
  -- Parse context if it's JSON
  local context_obj = nil
  local ok, parsed = pcall(vim.fn.json_decode, context)
  if ok then
    context_obj = parsed
  end

  -- Visual selection mode
  if context_obj and context_obj.selected_text and context_obj.selected_text ~= '' then
    -- Build context information
    local context_info = ''

    -- Add project context
    if context_obj.cached_context then
      context_info = context_info .. '\n\nProject Context:\n' .. vim.fn.json_encode(context_obj.cached_context)
    end

    -- Add open buffers list
    if context_obj.other_buffers and #context_obj.other_buffers > 0 then
      context_info = context_info .. '\n\nOther Open Files:\n'
      for _, buf in ipairs(context_obj.other_buffers) do
        -- Support both old field names (name/type) and new field names (filename/filetype)
        local name = buf.filename or buf.name or 'unknown'
        local type = buf.filetype or buf.type or 'text'
        context_info = context_info .. string.format('- %s (%s)\n', name, type)
      end
    end

    return string.format([[
File: %s
Language: %s
%s

Full file content:
%s

Selected text (lines %d-%d):
%s

Task: %s

Use SEARCH/REPLACE format where "search" is the selected text and "replace" is the improved version.]],
      context_obj.file_path or 'unknown',
      context_obj.language or 'unknown',
      context_info,
      context_obj.file_content or '',
      context_obj.line_number or 0,
      context_obj.end_line or context_obj.line_number or 0,
      context_obj.selected_text or '',
      instruction)

  -- TODO mode - we know the line number
  elseif context_obj and context_obj.line_number then
    -- Extract the TODO line to analyze indentation
    local todo_line = ''
    local indentation = ''
    if context_obj.surrounding_lines then
      for _, line_info in ipairs(context_obj.surrounding_lines) do
        if line_info.is_target then
          todo_line = line_info.content or ''
          -- Extract leading whitespace (spaces or tabs)
          indentation = todo_line:match('^(%s*)')
          break
        end
      end
    end

    -- Build context information
    local context_info = ''

    -- Add project context
    if context_obj.cached_context then
      context_info = context_info .. '\n\nProject Context:\n' .. vim.fn.json_encode(context_obj.cached_context)
    end

    -- Add open buffers list
    if context_obj.other_buffers and #context_obj.other_buffers > 0 then
      context_info = context_info .. '\n\nOther Open Files:\n'
      for _, buf in ipairs(context_obj.other_buffers) do
        -- Support both old field names (name/type) and new field names (filename/filetype)
        local name = buf.filename or buf.name or 'unknown'
        local type = buf.filetype or buf.type or 'text'
        context_info = context_info .. string.format('- %s (%s)\n', name, type)
      end
    end

    return string.format([[
File: %s
Language: %s
%s

Full file content:
%s

TODO at line %d: %s
Current line indentation: "%s" (%d %s)
Exact TODO line content: %s

Context around TODO:
%s

CRITICAL INSTRUCTIONS FOR SEARCH/REPLACE:
1. OPTIMIZE FOR LOGICAL BLOCKS: Combine related changes into larger, cohesive replacements
2. When multiple functions/sections work together, replace them as ONE logical unit
3. "search": Include ALL related code that forms a logical block (entire functions, classes, or sections)
4. "replace": The complete new implementation for the entire logical block
5. REDUCE DEVELOPER BURDEN: Use fewer, larger changes instead of many small ones
6. For related functions: Combine them in a single SEARCH/REPLACE if they're logically connected
7. For UI/display changes: Group all related UI elements in one change
8. INDENTATION: Copy EXACTLY from the search text - "%s" (%d %s)
9. "description": Describe the logical transformation, not just mechanical changes
10. IMPORTANT: Think in terms of features/components, not individual functions

DIFF OPTIMIZATION GUIDELINES:
- Group related changes logically - what makes sense to review together?
- Include complete context - whole functions, not just individual lines
- Minimize review burden - aim for 2-3 cohesive diffs instead of 5-7 tiny ones
- For related functions (like recipe methods), group them in one diff
- Balance readability with completeness - not too small, not too massive
- Think like a reviewer - what would you want to approve as one unit?

Example for your response - use logical blocks when appropriate:]],
      context_obj.file_path or 'unknown',              -- %s #1
      context_obj.language or 'unknown',              -- %s #2
      context_info,                                    -- %s #3 (new context info)
      context_obj.file_content or '',                  -- %s #4
      context_obj.line_number or 0,                    -- %d #5
      instruction,                                      -- %s #6
      indentation:gsub('\t', '\\t'),                  -- %s #7
      #indentation,                                     -- %d #8
      indentation:match('\t') and 'tabs' or 'spaces',  -- %s #9
      vim.fn.json_encode(todo_line),                  -- %s #10
      vim.fn.json_encode(context_obj.surrounding_lines or {}), -- %s #11
      indentation:gsub('\t', '\\t'),                  -- %s #12
      #indentation,                                     -- %d #13
      indentation:match('\t') and 'tabs' or 'spaces') -- %s #14

  -- Project scan mode
  elseif context_obj and context_obj.mode == 'project_scan' then
    return string.format([[
Task: %s

Project TODOs to process:
%s

CRITICAL INSTRUCTIONS for project-wide SEARCH/REPLACE changes:
1. Process ALL TODOs using SEARCH/REPLACE format
2. Return changes in LOGICAL ORDER for developer review:
   - Group related changes together
   - Order by dependency (foundational changes first)
   - Consider the workflow a developer would follow
3. Each change MUST include:
   - "search": EXACT text to find (including the TODO line)
   - "replace": The new code to replace it with
   - "description": Brief description including file path
4. The "search" text must match EXACTLY including indentation
5. In your "explanation" field, provide reasoning for:
   - Why you ordered the changes this way
   - Any dependencies between changes
   - Which changes could be reviewed together

Example ordering rationale:
- Config/setup files first
- Core functionality before features
- Base classes before implementations
- Independent changes can be grouped]],
      instruction,
      context_obj.project_todos or '')

  -- Chat mode or general query
  else
    return string.format([[
Task: %s

Context:
%s

Provide appropriate response using the JSON schema. Use "code_snippet" for examples, "changes" for file modifications.]],
      instruction,
      context)
  end
end

-- Build simple prompt for providers that don't support system prompts
function M.build_combined_prompt(instruction, context)
  local system = M.get_system_prompt()
  local user = M.build_user_prompt(instruction, context)

  return system .. "\n\n" .. user
end

return M