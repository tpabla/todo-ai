local M = {}

-- JSON Schema for AI responses
M.response_schema = {
  type = "object",
  properties = {
    -- Array of code changes (for multiple edits in one response)
    changes = {
      type = "array",
      description = "Array of code changes to apply to the buffer",
      items = {
        type = "object",
        required = {"start_line", "end_line", "code"},
        properties = {
          start_line = {
            type = "integer",
            description = "Starting line number to replace (1-indexed)"
          },
          end_line = {
            type = "integer",
            description = "Ending line number to replace (inclusive)"
          },
          code = {
            type = "string",
            description = "The replacement code"
          },
          description = {
            type = "string",
            description = "Brief description of this specific change"
          }
        }
      }
    },
    -- Code snippet for informational display only
    code_snippet = {
      type = "string",
      description = "Code example to display in chat (informational only, not for buffer changes)"
    },
    -- Overall explanation
    explanation = {
      type = "string",
      description = "Overall explanation of all changes or answer to the question"
    },
    -- File operations
    new_file = {
      type = "string",
      description = "Path for a new file to create"
    },
    replace_buffer = {
      type = "boolean",
      description = "If true, replace entire buffer content with changes"
    }
  }
}

-- Convert schema to readable format for prompts
function M.get_schema_description()
  return [[
{
  // For making changes to the buffer:
  "changes": [
    {
      "start_line": number,  // Line to start replacing (1-indexed)
      "end_line": number,    // Line to end replacing (inclusive)
      "code": string,        // Replacement code
      "description": string  // What this change does
    }
    // ... more changes
  ],

  // For showing code examples in chat (no buffer changes):
  "code_snippet": string,   // Example code to display

  // Common fields:
  "explanation": string,    // Overall explanation or answer

  // Optional file operations:
  "new_file": string,       // Path for new file creation
  "replace_buffer": boolean // Replace entire buffer with changes
}]]
end

-- Example responses for different scenarios
M.examples = {
  -- Multiple changes to buffer
  multiple_changes = [[{
  "changes": [
    {
      "start_line": 10,
      "end_line": 15,
      "code": "function validate(data) {\n    return data != null;\n}",
      "description": "Simplified validation function"
    },
    {
      "start_line": 25,
      "end_line": 25,
      "code": "const result = validate(input);",
      "description": "Updated function call"
    }
  ],
  "explanation": "Refactored validation logic and updated usage"
}]],

  -- Informational code snippet
  info_snippet = [[{
  "code_snippet": "// Example of async/await\nasync function fetchData() {\n    const response = await fetch('/api/data');\n    return response.json();\n}",
  "explanation": "Here's how to use async/await for fetching data"
}]],

  -- New file creation
  new_file = [[{
  "new_file": "utils/helpers.js",
  "changes": [
    {
      "start_line": 1,
      "end_line": 1,
      "code": "export function formatDate(date) {\n    return date.toISOString();\n}\n\nexport function parseDate(str) {\n    return new Date(str);\n}"
    }
  ],
  "explanation": "Created new helper utilities file with date functions"
}]],

  -- Full buffer replacement
  full_replacement = [[{
  "replace_buffer": true,
  "changes": [
    {
      "start_line": 1,
      "end_line": 999999,
      "code": "// Cleaned and refactored code\nfunction main() {\n    console.log('Hello');\n}"
    }
  ],
  "explanation": "Cleaned up and refactored entire file"
}]],

  -- Visual selection replacement
  visual_selection = [[{
  "changes": [
    {
      "start_line": 5,
      "end_line": 8,
      "code": "// Improved implementation\nfunction calculate() {\n    return 42;\n}",
      "description": "Replaced selected code with improved version"
    }
  ],
  "explanation": "Updated the selected function with a better implementation"
}]]
}

return M