local M = {}

-- Markdown formatting requirements for chat responses
M.markdown_format = {
  code_blocks = "Use triple backticks with language identifier: ```lua, ```python, etc.",
  inline_code = "Use single backticks for inline code: `variable_name`",
  headers = "Use ## for main sections, ### for subsections",
  lists = "Use - or * for unordered lists, 1. 2. 3. for ordered lists",
  emphasis = "Use **bold** for important terms, *italic* for emphasis",
  links = "Use [text](url) format for links",
  tables = "Use | for table columns with |---|---| separator"
}

-- JSON Schema for AI responses (SEARCH/REPLACE format or chat-only)
M.response_schema = {
  type = "object",
  properties = {
    -- Mode indicator - either "changes" or "chat"
    mode = {
      type = "string",
      enum = { "changes", "chat" },
      description = "Response mode: 'changes' for code modifications, 'chat' for conversational response"
    },
    -- Array of SEARCH/REPLACE blocks (required only for mode="changes")
    changes = {
      type = "array",
      description = "Array of SEARCH/REPLACE changes (only when mode='changes')",
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
    -- For mode="changes": explanation of changes
    -- For mode="chat": the conversational response
    explanation = {
      type = "string",
      description = "For changes mode: explanation of changes. For chat mode: the response message formatted as proper markdown with code blocks, lists, headers, etc."
    }
  },
  required = { "mode", "explanation" }
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