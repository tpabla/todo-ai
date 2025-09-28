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

-- Convert schema to readable format for prompts
function M.get_schema_description()
  return [[
RESPONSE FORMAT: You MUST respond with ONLY valid JSON that follows this exact schema:

{
  "changes": [                         // REQUIRED array of SEARCH/REPLACE changes
    {
      "search": "string (REQUIRED)",   // EXACT text to search for in the file
      "replace": "string (REQUIRED)",  // Text to replace the search match with
      "description": "string"           // Optional brief description of this change
    }
  ],
  "language": "string (auto-detected)", // File language/type (e.g. "python", "javascript", "json", "text")
  "explanation": "string (REQUIRED)"    // Overall explanation of all changes
}

IMPORTANT RULES FOR SEARCH/REPLACE:
1. LOGICAL BLOCKS: Combine related changes into fewer, larger replacements
2. When functions work together (e.g., getter/setter, UI components), replace them as ONE block
3. Include the ENTIRE logical unit in "search" - full functions, classes, or feature sections
4. The "replace" should be the COMPLETE new implementation of that logical unit
5. REDUCE APPROVALS: Minimize developer burden with fewer, smarter changes
6. Example logical blocks:
   - All recipe functions together if converting cocktail types
   - Entire UI section for theme changes
   - Complete feature module for functionality updates
7. Changes are applied sequentially - order them logically
8. "language" should be auto-detected
9. "explanation" should describe the HIGH-LEVEL transformation, not line-by-line changes
10. No markdown in the JSON - ONLY the JSON object
11. Unless TODO specifically asks for granular changes, PREFER larger logical blocks

EXAMPLE (Logical Block Replacement - Cocktail Recipe Transformation):
{
  "changes": [
    {
      "search": "# TODO: @ai convert to negroni recipe\ndef get_margarita_ingredients():\n    return {\n        \"tequila\": \"2 oz\",\n        \"lime\": \"1 oz\"\n    }\n\ndef make_margarita():\n    ingredients = get_margarita_ingredients()\n    return \"Shake with ice\"\n\ndef display_margarita_menu():\n    print(\"Margarita Menu\")\n    print(\"1. Classic\")\n    print(\"2. Frozen\")",
      "replace": "def get_negroni_ingredients():\n    return {\n        \"gin\": \"1 oz\",\n        \"campari\": \"1 oz\",\n        \"vermouth\": \"1 oz\"\n    }\n\ndef make_negroni():\n    ingredients = get_negroni_ingredients()\n    return \"Stir with ice\"\n\ndef display_negroni_menu():\n    print(\"Negroni Menu\")\n    print(\"1. Classic\")\n    print(\"2. Boulevardier\")",
      "description": "Transform entire margarita recipe module to negroni - all related functions as one logical block"
    }
  ],
  "language": "python",
  "explanation": "Transformed complete cocktail recipe from margarita to negroni, updating all related functions (ingredients, preparation, menu) in a single logical change to minimize developer review burden"
}]]
end

-- Apply a single SEARCH/REPLACE change to buffer lines
function M.apply_search_replace(lines, search_text, replace_text)
  -- Convert lines to a single string for searching
  local content = table.concat(lines, '\n')

  -- Find the search text in the content
  local start_pos, end_pos = content:find(search_text, 1, true) -- true for plain text search

  if not start_pos then
    return nil, "Search text not found"
  end

  -- Replace the first occurrence only
  local new_content = content:sub(1, start_pos - 1) .. replace_text .. content:sub(end_pos + 1)

  -- Split back into lines
  local new_lines = vim.split(new_content, '\n', { plain = true })

  return new_lines, nil
end

-- Apply multiple SEARCH/REPLACE changes sequentially
function M.apply_changes(lines, changes)
  local result = vim.deepcopy(lines)
  local applied_count = 0
  local errors = {}

  for i, change in ipairs(changes) do
    if change.search and change.replace then
      local new_lines, err = M.apply_search_replace(result, change.search, change.replace)
      if new_lines then
        result = new_lines
        applied_count = applied_count + 1
      else
        table.insert(errors, string.format("Change %d: %s", i, err or "Failed to apply"))
      end
    end
  end

  if #errors > 0 then
    return result, applied_count, table.concat(errors, "; ")
  end

  return result, applied_count, nil
end



return M