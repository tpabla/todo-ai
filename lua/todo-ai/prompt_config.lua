-- Centralized prompt and schema configuration
-- Single source of truth for all prompt instructions and response schemas
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

-- Markdown formatting requirements for chat mode
M.markdown_requirements = {
  "Format all code examples in fenced code blocks with language tags",
  "Use proper markdown headers (##, ###) for structure",
  "Create lists with - or * for bullets, 1. 2. for numbered items",
  "Emphasize key terms with **bold** and *italic*",
  "Use `backticks` for inline code references",
  "Structure responses with clear sections and formatting"
}

-- Build the complete schema description
function M.get_schema_description()
  local rules = {}
  for i, rule in ipairs(M.search_replace_rules) do
    table.insert(rules, string.format("%d. %s", i, rule))
  end

  return string.format([[
CRITICAL: Respond with ONLY pure JSON - no markdown wrapping around the JSON itself!

FIRST, DETERMINE THE RESPONSE MODE BY UNDERSTANDING USER INTENT:

Ask yourself: "Does the user want me to CHANGE their code or just UNDERSTAND it?"

Use mode="changes" when the user wants code to be different:
- They describe a problem that needs fixing
- They want new functionality added
- They're asking for improvements or optimizations
- They want something to work differently
- They're describing desired behavior that doesn't exist yet

Use mode="chat" when the user wants understanding:
- They're asking what their code does
- They want to know how something works
- They're asking why something happens
- They want concepts explained
- They're debugging and need to understand current behavior
- They're asking about their code without implying changes

INFERENCE RULE: Look for intent to modify vs intent to understand. If they're describing how things SHOULD be (future state) → use mode="changes". If they're asking about how things ARE (current state) → use mode="chat".

RESPONSE FORMAT: Raw JSON object with ONE of these two structures:

FOR CODE CHANGES (mode="changes"):
{
  "mode": "changes",
  "filename": "string (OPTIONAL)",      // Target filename (e.g., "test.py", "main.lua")
  "changes": [                         // REQUIRED array of SEARCH/REPLACE changes
    {
      "search": "string (REQUIRED)",   // EXACT text to search for in the file
      "replace": "string (REQUIRED)",  // Complete replacement text
      "description": "string"           // Brief description referencing the TODO
    }
  ],
  "language": "string (auto-detected)", // File language/type
  "explanation": "string (REQUIRED)"    // Overall transformation summary
}

IMPORTANT: Include "filename" when you know which file to modify (you'll usually see it in the context)

FOR CONVERSATIONAL RESPONSES (mode="chat"):
{
  "mode": "chat",
  "explanation": "string (REQUIRED)"    // Your response in PROPER MARKDOWN format:
                                        // MUST include when relevant:
                                        // - Fenced code blocks: ```lua\ncode here\n```
                                        // - Headers: ## Section Name
                                        // - Lists: - item or 1. item
                                        // - Emphasis: **bold**, *italic*
                                        // - Inline code: `code`
                                        // The content MUST be valid markdown that renders properly
}

DO NOT wrap the JSON in ```json``` or any other markdown formatting!
Return ONLY the raw JSON object.

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


-- Markdown formatting requirements for chat mode
M.markdown_format = {
  code_blocks = "Use triple backticks with language identifier: ```lua, ```python, etc.",
  inline_code = "Use single backticks for inline code: `variable_name`",
  headers = "Use ## for main sections, ### for subsections",
  lists = "Use - or * for unordered lists, 1. 2. 3. for ordered lists",
  emphasis = "Use **bold** for important terms, *italic* for emphasis",
  links = "Use [text](url) format for links",
  tables = "Use | for table columns with |---|---| separator"
}


return M