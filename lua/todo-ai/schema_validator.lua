-- Schema validation for LLM responses
-- Delegates to Rust backend (required)
local M = {}

local bridge = require('todo-ai.bridge')

-- Validate response against expected schema
function M.validate_response(response)
  if not response then
    return false, {"Response is nil or empty"}
  end

  local result, err = bridge.call_sync('validate_response', {response = response})
  if err then
    error('schema_validator.validate_response failed: ' .. err)
  end

  if result.valid then
    return true, nil
  else
    return false, result.errors or {}
  end
end

-- Create a detailed error message for display
function M.format_validation_errors(errors)
  local lines = {
    "## LLM Response Schema Validation Failed",
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
