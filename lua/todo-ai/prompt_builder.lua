-- Centralized prompt building for all providers
local M = {}

-- Build system prompt that all providers should use
function M.get_system_prompt()
  local schema = require('todo-ai.schema')
  return string.format([[
You are a code assistant integrated into Neovim. You must ALWAYS respond with valid JSON following this schema:

%s

Rules:
1. ALWAYS use the "changes" array for any code modifications to files
2. Use "code_snippet" ONLY for showing example code in chat (won't modify files)
3. For each change, specify exact start_line and end_line (1-indexed)
4. The "code" field in changes should contain ONLY the replacement code (see schema)
5. Include "description" for each change explaining what it does
6. Include overall "explanation" summarizing all changes
7. CRITICAL: Preserve EXACT indentation from the original code - count spaces/tabs carefully
8. When replacing indented code, ensure the replacement has the SAME indentation level
9. Escape all quotes properly for valid JSON
10. NEVER include markdown formatting in JSON values
11. For new files, use "new_file" with path and single change starting at line 1

Examples (use minimal data format):
%s

For multiple changes in the same file, send them all at once for efficient review.]],
    schema.get_schema_description(),
    vim.fn.json_encode(schema.examples.multiple_changes))
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
    return string.format([[
File: %s
Language: %s

Full file content:
%s

Selected text (lines %d-%d):
%s

Task: %s

Replace the selected lines %d-%d with the improved version.]],
      context_obj.file_path or 'unknown',
      context_obj.language or 'unknown',
      context_obj.file_content or '',
      context_obj.line_number or 0,
      context_obj.end_line or context_obj.line_number or 0,
      context_obj.selected_text or '',
      instruction,
      context_obj.line_number or 0,
      context_obj.end_line or context_obj.line_number or 0)

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

    return string.format([[
File: %s
Language: %s

Full file content:
%s

TODO at line %d: %s
Current line indentation: "%s" (%d %s)
Exact TODO line content: %s

Context around TODO:
%s

CRITICAL INSTRUCTIONS:
1. If TODO is a placeholder: Replace line %d with your implementation
2. If TODO is a comment: Add implementation after it (keep TODO line)
3. INDENTATION: Every line MUST start with EXACTLY "%s" (%d %s)
4. Only send the NEW/replacement code, not existing surrounding lines
5. Set appropriate start_line and end_line for your change
6. IMPORTANT: Include "todo_text": "%s" with the COMPLETE TODO instruction text
   - For multi-line TODOs, include ALL lines of the instruction as a single string
   - This allows us to properly clean up multi-line TODO comments after accepting changes
7. Do NOT create separate changes to remove TODOs - we handle @ai cleanup automatically

Create a single "changes" array entry with properly indented code at line %d.]],
      context_obj.file_path or 'unknown',  -- %s
      context_obj.language or 'unknown',  -- %s
      context_obj.file_content or '',  -- %s
      context_obj.line_number or 0,  -- %d at line 90
      instruction,  -- %s at line 90
      indentation:gsub('\t', '\\t'),  -- %s at line 91 (indentation string)
      #indentation,  -- %d at line 91
      indentation:match('\t') and 'tabs' or 'spaces',  -- %s at line 91
      vim.fn.json_encode(todo_line),  -- %s at line 92
      vim.fn.json_encode(context_obj.surrounding_lines or {}),  -- %s at line 95
      context_obj.line_number or 0,  -- %d at line 98
      vim.fn.json_encode(indentation),  -- %s at line 100
      #indentation,  -- %d at line 100
      indentation:match('\t') and 'tabs' or 'spaces',  -- %s at line 100
      instruction,  -- %s at line 103 (todo_text)
      context_obj.line_number or 0)  -- %d at line 108

  -- Project scan mode
  elseif context_obj and context_obj.mode == 'project_scan' then
    return string.format([[
Task: %s

Project TODOs to process:
%s

CRITICAL INSTRUCTIONS for project-wide changes:
1. Process ALL TODOs found in the project
2. Return changes in LOGICAL ORDER for developer review:
   - Group related changes together
   - Order by dependency (foundational changes first)
   - Consider the workflow a developer would follow
3. Each change MUST include:
   - "file": absolute or relative path to the file
   - "description": include the file path and what the change does
   - "todo_text": the complete TODO instruction text for cleanup
4. In your "explanation" field, provide reasoning for:
   - Why you ordered the changes this way
   - Any dependencies between changes
   - Which changes could be reviewed together
5. Format each hunk's explanation to be shown as footer text

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