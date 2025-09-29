# TODO-AI Design Guidelines for Claude

## Core Principles

### 1. Fail Fast, Fail Loud
- **NO** silent failures or fallbacks
- **NO** trying to recover from errors
- **ALWAYS** error immediately with clear message
- **NEVER** guess or assume what user meant

### 2. Simplicity Over Features
- **MINIMIZE** code - less is more
- **REUSE** existing functions everywhere
- **ONE** way to do things, not multiple paths
- **DELETE** unused code immediately

### 3. Modern APIs Only
- **USE** `vim.api.nvim_*` functions
- **AVOID** `vim.fn.*` unless no alternative
- **NO** deprecated functions like `vim.lsp.get_active_clients()`
- **USE** `vim.lsp.get_clients()` instead

### 4. Single Entry Point
- **ALL** user requests go through `unified_prompt.process()`
- **NO** direct calls to providers from other modules
- **ONE** path: user input → unified_prompt → provider → response
- **EASIER** debugging with single flow

## Code Guidelines

### Buffer Management
```lua
-- GOOD: Simple, direct
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, path)

-- BAD: Complex fallbacks
local buf = vim.fn.bufnr(path)
if buf == -1 then
  -- try this...
  if not that then
    -- try another thing...
  end
end
```

### Error Handling
```lua
-- GOOD: Fail immediately
if not response.mode then
  error("Missing mode field")
end

-- BAD: Try to continue
if not response.mode then
  response.mode = "chat"  -- assume default
end
```

### Chat Buffer Protection
```lua
-- Simple helper used everywhere
local function is_chat_buffer(bufnr)
  if not bufnr then return true end
  return vim.api.nvim_buf_get_name(bufnr):match('Todo%-AI Chat') ~= nil
end

-- Fail if chat buffer
if is_chat_buffer(target_buf) then
  error("Cannot modify chat buffer")
end
```

## Testing Guidelines

1. **Test the critical path** - don't test edge cases that shouldn't happen
2. **Test that failures fail** - ensure errors are thrown when expected
3. **Keep tests simple** - no complex setup or teardown
4. **Use plenary.nvim** - it's already a dependency

## Implementation Details

### SEARCH/REPLACE Style (Aider-style)
- **USE** exact text matching - no line numbers
- **COMBINE** related changes into single blocks
- **SEARCH** must match exactly (whitespace, indentation)
- **REPLACE** contains the complete replacement
- **NO** complex diff algorithms needed

### Visual Diff Display
- **USE** native Neovim highlighting: `DiffAdd`, `DiffDelete`
- **USE** virtual text for removed lines
- **NO** custom syntax highlighting needed
- **SIMPLE** headers with separator lines

## Common Patterns

### JSON Response Validation
- **REQUIRE** exact schema match
- **NO** field guessing or inference
- **FAIL** loudly on missing fields

### File Operations
- **CREATE** buffers with `nvim_create_buf`
- **CHECK** chat buffer with simple pattern match
- **NO** complex path resolution

### LLM Communication
- **ONE** format: JSON with mode field
- **TWO** modes only: "chat" or "changes"
- **STRICT** schema validation

## What NOT to Do

1. **DON'T** add fallback behavior
2. **DON'T** try multiple approaches
3. **DON'T** handle rare edge cases
4. **DON'T** use deprecated APIs
5. **DON'T** create multiple entry points
6. **DON'T** add complex error recovery
7. **DON'T** guess user intent
8. **DON'T** add optional parameters

## Remember

When in doubt:
- Make it simpler
- Delete more code
- Fail faster
- Be more direct

The best code is no code.
The second best code is simple code.
Complex code is a bug waiting to happen.
- remember we are using aider style search and replace for text replacement and visual diffs so you  don't need any complex line number git diff style memory you can just use the blocks to reference the code
- also when we had issues with code highlighting in the visual deff is was resolved by using neovim native diff tooling and highlighting with DiffAdd and DiffDelelte