-- Schema validation for LLM responses
local M = {}

local logger = require('todo-ai.logger')

-- Validate response against expected schema
function M.validate_response(response)
  local errors = {}

  -- Check if response exists
  if not response then
    table.insert(errors, "Response is nil or empty")
    return false, errors
  end

  -- Check for mode field at root level
  if not response.mode then
    table.insert(errors, "❌ MISSING 'mode' field at root level - LLM must include \"mode\": \"changes\" or \"mode\": \"chat\"")
  elseif response.mode ~= "changes" and response.mode ~= "chat" then
    table.insert(errors, string.format("❌ INVALID mode '%s' - must be either 'changes' or 'chat'", response.mode))
  end

  -- If mode is changes, validate required fields
  if response.mode == "changes" then
    -- Check for filename
    if not response.filename then
      table.insert(errors, "❌ MISSING 'filename' field - LLM must specify which file to create/modify (e.g., \"filename\": \"gin_data.py\")")
    elseif type(response.filename) ~= "string" or response.filename == "" then
      table.insert(errors, "❌ INVALID 'filename' - must be a non-empty string with the target filename")
    end

    -- Check for changes array
    if not response.changes then
      table.insert(errors, "❌ MISSING 'changes' array - LLM must provide array of search/replace operations")
    elseif type(response.changes) ~= "table" then
      table.insert(errors, "❌ INVALID 'changes' - must be an array of change objects")
    elseif #response.changes == 0 then
      table.insert(errors, "❌ EMPTY 'changes' array - must contain at least one search/replace operation")
    else
      -- Validate each change
      for i, change in ipairs(response.changes) do
        if not change.search and change.search ~= "" then
          table.insert(errors, string.format("❌ Change #%d missing 'search' field - must include search string (empty string \"\" for new files)", i))
        end
        if not change.replace then
          table.insert(errors, string.format("❌ Change #%d missing 'replace' field - must include replacement content", i))
        end
      end
    end

    -- Check for explanation
    if not response.explanation then
      table.insert(errors, "⚠️ MISSING 'explanation' field - should explain what changes were made")
    end
  elseif response.mode == "chat" then
    -- For chat mode, just need explanation
    if not response.explanation then
      table.insert(errors, "❌ MISSING 'explanation' field - chat responses must include explanation text")
    end
  end

  -- Check if fields are in wrong place (common error)
  if response.parsed_sections then
    if response.parsed_sections.mode and not response.mode then
      table.insert(errors, "❌ 'mode' found in parsed_sections but NOT at root level - parser error or malformed response")
    end
    if response.parsed_sections.filename and not response.filename then
      table.insert(errors, "❌ 'filename' found in parsed_sections but NOT at root level - parser error or malformed response")
    end
  end

  -- Return validation result
  if #errors > 0 then
    return false, errors
  end

  return true, nil
end

-- Create a detailed error message for display
function M.format_validation_errors(errors)
  local lines = {
    "## ❌ LLM Response Schema Validation Failed",
    "",
    "The LLM's response doesn't match the required schema. This usually means:",
    "1. The LLM didn't follow instructions properly",
    "2. The response JSON is malformed",
    "3. Required fields are missing or in wrong locations",
    "",
    "### Validation Errors:",
    ""
  }

  for _, error in ipairs(errors) do
    table.insert(lines, "- " .. error)
  end

  table.insert(lines, "")
  table.insert(lines, "### Expected Schema for Code Changes:")
  table.insert(lines, "```json")
  table.insert(lines, "{")
  table.insert(lines, '  "mode": "changes",')
  table.insert(lines, '  "filename": "exact_file.py",')
  table.insert(lines, '  "changes": [')
  table.insert(lines, '    {')
  table.insert(lines, '      "search": "",  // empty for new files')
  table.insert(lines, '      "replace": "file content",')
  table.insert(lines, '      "description": "what this does"')
  table.insert(lines, '    }')
  table.insert(lines, '  ],')
  table.insert(lines, '  "explanation": "Summary of changes"')
  table.insert(lines, "}")
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "**Try rephrasing your request or report this issue if it persists.**")

  return table.concat(lines, "\n")
end

return M