local M = {}

-- JSON Schema for AI responses (SEARCH/REPLACE format)
M.response_schema = {
  type = "object",
  properties = {
    -- Array of SEARCH/REPLACE blocks (required)
    changes = {
      type = "array",
      description = "Array of SEARCH/REPLACE changes",
      items = {
        type = "object",
        properties = {
          search = {
            type = "string",
            description = "Exact text to search for (must match exactly)"
          },
          replace = {
            type = "string",
            description = "Text to replace the search match with"
          },
          description = {
            type = "string",
            description = "Brief description of this specific change"
          }
        },
        required = { "search", "replace" }
      }
    },
    -- Auto-detected language for proper formatting
    language = {
      type = "string",
      description = "File language/type (python, javascript, json, etc.)"
    },
    -- Required explanation
    explanation = {
      type = "string",
      description = "Overall explanation of all changes"
    }
  },
  required = { "changes", "explanation" }
}

-- Use centralized prompt configuration
local prompt_config = require('todo-ai.prompt_config')

-- Convert schema to readable format for prompts
function M.get_schema_description()
  return prompt_config.get_schema_description()
end

-- Delegate to search_replace module for consistency
local search_replace = require('todo-ai.search_replace')

-- Apply a single SEARCH/REPLACE change to buffer lines (backwards compatibility)
function M.apply_search_replace(lines, search_text, replace_text)
  local content = table.concat(lines, '\n')
  local result, err = search_replace.apply_single(content, search_text, replace_text)

  if not result then
    return nil, err
  end

  return vim.split(result, '\n', { plain = true }), nil
end

-- Apply multiple SEARCH/REPLACE changes sequentially
function M.apply_changes(lines, changes)
  return search_replace.apply_changes(lines, changes)
end



return M