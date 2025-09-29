-- Centralized prompt and schema configuration
-- Single source of truth for all prompt instructions and response schemas
local M = {}

-- Core SEARCH/REPLACE rules (shared between schema and prompt_builder)
M.search_replace_rules = {
  "🚨 CRITICAL: Maximum 1-3 changes per response - NEVER exceed this limit!",
  "🚨 If task requires more than 3 changes, do a SUBSET and explain what's next",
  "⚠️ When user says 'continue', pick up from where you left off",
  "⚠️ Break large tasks into logical chunks (e.g. first 3 methods, then next 3)",
  "Bias towards combining continuous/adjacent changes into one diff",
  "Group related changes logically - each diff should be one cohesive unit",
  "Include complete context - if changing a function, include the whole function",
  "The 'search' must match EXACTLY what's in the file (indentation, whitespace)",
  "The 'replace' should be the complete replacement for that logical section",
  "Continuous changes should usually be combined unless they're unrelated concerns",
  "**'description' MUST reference the specific TODO** - e.g. 'Convert to martini per TODO request'",
  "NEVER use generic descriptions like 'Change 1', 'Update function 2' - be specific!",
  "Changes are applied sequentially in the order provided",
  "Related functions (get_X, make_X, display_X) should be ONE change, not three",
  "ORDER changes in logical progression - dependencies first, then dependent code",
  "When changing multiple files, order by: 1) core/library files, 2) implementation files, 3) tests",
  "Each change block should be self-contained and reviewable as a logical unit"
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
🚨 CRITICAL: Respond with ONLY pure JSON - no markdown wrapping around the JSON itself!

🚨 MANDATORY: Your response MUST start with { and end with }

🚨 REQUIRED: Every response MUST include "mode" field at the root level

FIRST, DETERMINE THE RESPONSE MODE BY UNDERSTANDING USER INTENT:

Ask yourself: "Does the user want me to CHANGE their code or just UNDERSTAND it?"

Use mode="changes" when the user wants code to be different:
- They use words like "create", "make", "build", "generate", "write", "add", "implement"
- They say "create the missing files" or "generate the functions"
- They describe a problem that needs fixing
- They want new functionality added
- They're asking for improvements or optimizations
- They want something to work differently
- They're describing desired behavior that doesn't exist yet
- They reference missing imports or undefined functions that need to be created

Use mode="chat" when the user wants understanding:
- They use words like "what", "why", "how", "explain", "tell me about"
- They're asking what their code does
- They want to know how something works
- They're asking why something happens
- They want concepts explained
- They're debugging and need to understand current behavior
- They're asking about their code without implying changes

CRITICAL: When in doubt about file creation, if the user mentions "create", "make", or "generate" in relation to files or code, ALWAYS use mode="changes". Users expect action when they request creation.

RESPONSE FORMAT: Raw JSON object with ONE of these two structures:

FOR CODE CHANGES (mode="changes"):
{
  "mode": "changes",              // REQUIRED: Must be exactly "changes"
  "filename": "string (REQUIRED)", // REQUIRED: Exact filename to create/modify (e.g., "test.py", "gin_data.py")
  "changes": [                     // REQUIRED: Array of SEARCH/REPLACE changes
    {
      "search": "string (REQUIRED)",   // For NEW files: use empty string ""
      "replace": "string (REQUIRED)",  // For NEW files: entire file content
      "description": "string"           // Brief description of the change
    }
  ],
  "language": "string (auto-detected)", // File language/type
  "explanation": "string (REQUIRED)"    // Overall transformation summary
}

CRITICAL FILE HANDLING RULES:
- The "filename" field is ABSOLUTELY REQUIRED for mode="changes"
- The "mode" field MUST be included at the root level of your JSON
- Always specify the EXACT filename when making code changes (e.g., "gin_data.py" not "test.py")
- For NEW FILE creation: use empty string "" for search, full content for replace
- ⚠️ ONLY ONE FILE PER RESPONSE - This is MANDATORY
- NEVER combine multiple files in one response
- NEVER add content to the wrong file - check the filename carefully

MULTIPLE FILE WORKFLOW:
- When user requests multiple files, create them ALL automatically in sequence
- Do NOT ask for approval between files - create them one after another
- Start with the first file immediately using mode="changes"
- Each response creates ONE file, system will prompt for the next automatically
- Continue until all requested files are complete

🚨 SCOPED CHANGES - CRITICAL LIMITS:
- MAXIMUM 1-3 changes per response - this prevents token limits
- If task needs more changes, do a logical subset and explain what's next
- Example: "Converted first 3 methods to static. Say 'continue' for the remaining 4 methods."
- When user says "continue", pick up exactly where you left off
- Break large refactors into chunks: methods 1-3, then 4-6, then 7-9, etc.

🚨 CRITICAL JSON STRUCTURE:
Your response MUST have this EXACT structure at the root level:

EXAMPLE FOR CODE CHANGES:
{
  "mode": "changes",
  "filename": "exact_file.py",
  "changes": [...],
  "explanation": "..."
}

EXAMPLE FOR CHAT:
{
  "mode": "chat",
  "explanation": "..."
}

⚠️ THE "mode" FIELD IS ABSOLUTELY MANDATORY - NO EXCEPTIONS!

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

CONTEXT PROVIDED:
You will receive comprehensive context including:
- File content and surrounding code
- LSP diagnostics (errors, warnings) for current file AND all open buffers
- Code symbols and structure from language servers
- Type information and documentation on hover
- Project structure and other open files
- Cross-file error tracking to understand project-wide issues

Use the LSP diagnostics to:
- Understand existing issues in the current file
- Be aware of errors in related files that might be affected by your changes
- Ensure your changes don't introduce new errors or break other files
- Consider the symbol structure when making changes to maintain consistency

IMPORTANT RULES:
%s

GOOD EXAMPLE (Large task - do subset first):
{
  "mode": "changes",
  "filename": "game_ui.py",
  "changes": [
    {
      "search": "def show_welcome(self):\n        \"\"\"Display welcome message and game introduction.\"\"\"\n        print(\"\\n\" + \"=\"*50)",
      "replace": "@staticmethod\n    def show_welcome():\n        \"\"\"Display welcome message and game introduction.\"\"\"\n        print(\"\\n\" + \"=\"*50)",
      "description": "Convert show_welcome method to static method"
    },
    {
      "search": "def get_player_name(self) -> str:\n        \"\"\"Get player name input.\"\"\"\n        return input(\"What's your name, aspiring bartender? \")",
      "replace": "@staticmethod\n    def get_player_name() -> str:\n        \"\"\"Get player name input.\"\"\"\n        return input(\"What's your name, aspiring bartender? \")",
      "description": "Convert get_player_name method to static method"
    }
  ],
  "language": "python",
  "explanation": "Converted first 2 methods to static methods. The class has 8 more methods to convert. Say 'continue' to convert the next batch of methods."
}

GOOD EXAMPLE (Modifying existing file):
{
  "mode": "changes",
  "filename": "test.py",
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

BAD EXAMPLE (Multiple files in one response - NEVER DO THIS):
{
  "mode": "changes",
  "filename": "multiple_files.py",
  "changes": [
    {
      "search": "",
      "replace": "# gin_data.py content\nGIN_DATA = {...}\n\n# martini_recipes.py content\nRECIPES = {...}\n\n# main.py content\nclass Game: ..."
    }
  ]
}
^ WRONG! Never put multiple files in one response!

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