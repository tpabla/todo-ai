local M = {}

-- JSON Schema for AI responses (optimized for native diff display)
M.response_schema = {
  type = "object",
  properties = {
    -- Unified diff format for native vim diff
    unified_diff = {
      type = "string",
      description = "Unified diff format patch (ideal for native diff)"
    },
    -- OR compact change format for programmatic changes
    changes = {
      type = "array",
      description = "Array of code changes to apply to the buffer",
      items = {
        type = "object",
        required = {"start_line", "end_line"},
        properties = {
          start_line = {
            type = "integer",
            description = "Starting line number to replace (1-indexed)"
          },
          end_line = {
            type = "integer",
            description = "Ending line number to replace (inclusive)"
          },
          lines = {
            type = "array",
            description = "New lines to insert (omit for deletion)",
            items = { type = "string" }
          },
          -- Alternative: single string with embedded newlines
          code = {
            type = "string",
            description = "Alternative to 'lines': code with newlines"
          },
          description = {
            type = "string",
            description = "Brief description of this change"
          },
          todo_text = {
            type = "string",
            description = "The TODO instruction text (without @ai marker) that this change addresses"
          },
          file = {
            type = "string",
            description = "File path for this change (for project-wide scans)"
          }
        }
      }
    },
    -- Compact format for multiple non-contiguous edits
    edits = {
      type = "object",
      description = "Line-by-line edits (more compact for sparse changes)",
      additionalProperties = {
        type = "string",
        description = "Line number as key, new content as value"
      }
    },
    -- Code snippet for informational display only
    code_snippet = {
      type = "string",
      description = "Code example to display in chat (informational only)"
    },
    -- Overall explanation
    explanation = {
      type = "string",
      description = "Overall explanation of all changes or answer"
    },
    -- File operations
    new_file = {
      type = "string",
      description = "Path for a new file to create"
    },
    replace_buffer = {
      type = "boolean",
      description = "If true, replace entire buffer content"
    }
  }
}

-- Convert schema to readable format for prompts
function M.get_schema_description()
  return [[
{
  // OPTION 1: For contiguous changes (most efficient for TODO replacement):
  "changes": [
    {
      "start_line": number,  // Starting line (1-indexed, includes TODO)
      "end_line": number,    // Ending line (inclusive)
      "lines": [string, ...] // New lines array (omit for deletion)
      // OR use "code": string with newlines embedded
      "description": string,  // What this change does
      "todo_text": string    // The TODO instruction (e.g., "add more haikus")
    }
  ],

  // OPTION 2: For sparse single-line edits (efficient for multiple small changes):
  "edits": {
    "10": "new content for line 10",
    "25": "new content for line 25",
    "30": ""  // Empty string = delete line 30
  },

  // For showing examples (no buffer changes):
  "code_snippet": string,

  // Common fields:
  "explanation": string,

  // Special operations:
  "new_file": string,       // Path for new file
  "replace_buffer": boolean // Replace entire buffer
}]]
end

-- Helper to apply changes to buffer lines efficiently
function M.apply_changes(lines, changes)
  local result = {}
  local line_map = {}

  -- Build a map of line changes
  for _, change in ipairs(changes or {}) do
    local new_lines = change.lines
    if not new_lines and change.code then
      new_lines = vim.split(change.code, '\n', { plain = true })
    end

    -- Mark lines for replacement
    for i = change.start_line, change.end_line do
      line_map[i] = false -- Mark for deletion
    end

    -- Store replacement at start line
    if new_lines and #new_lines > 0 then
      line_map[change.start_line] = new_lines
    end
  end

  -- Build result
  for i = 1, #lines do
    local mapping = line_map[i]
    if mapping == nil then
      -- No change, keep original line
      table.insert(result, lines[i])
    elseif mapping then
      -- Replace with new lines
      for _, new_line in ipairs(mapping) do
        table.insert(result, new_line)
      end
    end
    -- If mapping is false, skip (delete line)
  end

  return result
end

-- Helper to apply edits (sparse changes)
function M.apply_edits(lines, edits)
  if not edits then return lines end

  local result = {}
  for i = 1, #lines do
    local new_content = edits[tostring(i)]
    if new_content ~= nil then
      if new_content ~= "" then
        table.insert(result, new_content)
      end
      -- Empty string means delete
    else
      table.insert(result, lines[i])
    end
  end

  -- Handle lines beyond current buffer
  local max_line = #lines
  for line_str, content in pairs(edits) do
    local line_num = tonumber(line_str)
    if line_num and line_num > max_line then
      -- Pad with empty lines if needed
      for i = #result + 1, line_num - 1 do
        table.insert(result, "")
      end
      table.insert(result, content)
      max_line = line_num
    end
  end

  return result
end

-- Convert full code to minimal changes (for responses)
function M.create_minimal_change(start_line, end_line, new_code, description)
  local lines = vim.split(new_code, '\n', { plain = true })

  -- If it's a single line, just return the line
  if #lines == 1 then
    return {
      start_line = start_line,
      end_line = end_line,
      lines = lines,
      description = description
    }
  end

  -- For multi-line, use code field (more compact in JSON)
  return {
    start_line = start_line,
    end_line = end_line,
    code = new_code,
    description = description
  }
end

-- Example responses for different scenarios
M.examples = {
  -- Multiple TODOs in same file (send all at once)
  multiple_changes = [[{
  "changes": [
    {
      "start_line": 10,
      "end_line": 10,
      "lines": ["function validate(data) {", "  return data != null;", "}"],
      "description": "Implement validation"
    },
    {
      "start_line": 25,
      "end_line": 26,
      "lines": ["const result = await fetchData();", "return processResult(result);"],
      "description": "Add async data fetching"
    }
  ],
  "explanation": "Implemented 2 TODOs: validation and data fetching"
}]],

  -- Multiple sparse edits
  sparse_edits = [[{
  "edits": {
    "10": "const result = validate(input);",
    "25": "// Fixed typo",
    "30": ""
  },
  "explanation": "Fixed multiple small issues"
}]],

  -- Delete lines (TODO removal without replacement)
  delete_lines = [[{
  "changes": [{
    "start_line": 10,
    "end_line": 12,
    "description": "Remove obsolete TODO"
  }],
  "explanation": "Removed completed TODO"
}]],

  -- Full buffer replacement (when everything changes)
  full_replacement = [[{
  "replace_buffer": true,
  "changes": [{
    "start_line": 1,
    "end_line": 999999,
    "code": "// Complete new implementation\nfunction main() {\n  console.log('Hello');\n}"
  }],
  "explanation": "Complete rewrite"
}]]
}

return M