-- Centralized prompt configuration
-- Single source of truth for all prompt instructions
local M = {}

-- Core SEARCH/REPLACE rules (shared between schema and prompt_builder)
M.search_replace_rules = {
  "⚠️ STOP! If you're generating 4+ changes, you're doing it WRONG! Combine them!",
  "Bias towards combining continuous/adjacent changes into one diff",
  "Group related changes logically - each diff should be one cohesive unit",
  "Include complete context - if changing a function, include the whole function",
  "Minimize approval burden - aim for 1-3 diffs maximum, not 5-7",
  "The 'search' must match EXACTLY what's in the file (indentation, whitespace)",
  "The 'replace' should be the complete replacement for that logical section",
  "Continuous changes should usually be combined unless they're unrelated concerns",
  "**'description' MUST reference the specific TODO** - e.g. 'Convert to martini per TODO request'",
  "NEVER use generic descriptions like 'Change 1', 'Update function 2' - be specific!",
  "Changes are applied sequentially in the order provided",
  "Related functions (get_X, make_X, display_X) should be ONE change, not three"
}


-- JSON schema format
M.json_format = {
  changes = {
    type = "array",
    required = true,
    description = "Array of SEARCH/REPLACE changes",
    items = {
      search = {type = "string", required = true, description = "EXACT text to find"},
      replace = {type = "string", required = true, description = "Complete replacement"},
      description = {type = "string", required = false, description = "Change summary"}
    }
  },
  language = {
    type = "string",
    required = false,
    description = "Auto-detected file language"
  },
  explanation = {
    type = "string",
    required = true,
    description = "HIGH-LEVEL transformation summary"
  }
}

-- Build the complete schema description
function M.get_schema_description()
  local rules = {}
  for i, rule in ipairs(M.search_replace_rules) do
    table.insert(rules, string.format("%d. %s", i, rule))
  end

  return string.format([[
CRITICAL: Respond with ONLY pure JSON - no markdown, no backticks, no code blocks!

**MANDATORY RULE**: Minimize the number of changes! If you're making 5+ changes, you're doing it wrong!
- Combine ALL continuous/adjacent changes into ONE diff
- Group related functions (like recipe methods) into ONE diff
- Target 1-3 changes MAXIMUM, not 5-7

RESPONSE FORMAT: Raw JSON object following this EXACT schema:

{
  "changes": [                         // REQUIRED array of SEARCH/REPLACE changes
    {
      "search": "string (REQUIRED)",   // EXACT text to search for in the file
      "replace": "string (REQUIRED)",  // Complete replacement text
      "description": "string"           // Optional brief description
    }
  ],
  "language": "string (auto-detected)", // File language/type
  "explanation": "string (REQUIRED)"    // Overall transformation summary
}

DO NOT wrap the JSON in ```json``` or any other markdown formatting!
Return ONLY the raw JSON object with "changes", "language", and "explanation" fields.

IMPORTANT RULES:
%s

GOOD EXAMPLE (Logical grouping of related changes):
{
  "changes": [
    {
      "search": "def get_margarita_ingredients():\n    return {'tequila': '2 oz', 'lime': '1 oz'}\n\ndef make_margarita():\n    return 'Shake with ice'",
      "replace": "def get_negroni_ingredients():\n    return {'gin': '1 oz', 'campari': '1 oz', 'vermouth': '1 oz'}\n\ndef make_negroni():\n    return 'Stir with ice'",
      "description": "Convert cocktail recipe functions from margarita to negroni"
    }
  ],
  "language": "python",
  "explanation": "Updated the cocktail recipe by grouping the related ingredient and preparation functions together"
}

BAD EXAMPLE (Too granular - creates review burden):
{
  "changes": [
    {"search": "def get_margarita", "replace": "def get_negroni"},
    {"search": "tequila", "replace": "gin"},
    {"search": "lime", "replace": "campari"},
    {"search": "Shake", "replace": "Stir"}
  ]
}
^ Too many tiny changes! Group logically for easier review.]], table.concat(rules, "\n"))
end


return M