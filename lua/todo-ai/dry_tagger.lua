---@class DryTagger
local M = {}

local diff = require('todo-ai.diff_native')
local config = require('todo-ai.config')
local providers = require('todo-ai.providers')

---Scan codebase and suggest DRY tags for reusable functions
function M.suggest_dry_tags()
  local cwd = vim.fn.getcwd()

  -- Find source files to analyze
  local source_patterns = {
    "*.py", "*.js", "*.ts", "*.lua", "*.go", "*.rs", "*.java", "*.cpp", "*.c", "*.rb", "*.php"
  }

  local files_to_analyze = {}
  for _, pattern in ipairs(source_patterns) do
    local cmd = string.format("find %s -name '%s' -type f 2>/dev/null | head -10", cwd, pattern)
    local files = vim.fn.systemlist(cmd)
    for _, file in ipairs(files) do
      if vim.fn.filereadable(file) == 1 then
        table.insert(files_to_analyze, file)
      end
    end
  end

  if #files_to_analyze == 0 then
    vim.notify("No source files found to analyze", vim.log.levels.WARN)
    return
  end

  vim.notify("Analyzing " .. #files_to_analyze .. " files for DRY opportunities...", vim.log.levels.INFO)

  -- Analyze each file
  for _, file_path in ipairs(files_to_analyze) do
    M.analyze_file_for_dry_tags(file_path)
  end
end

---Analyze a single file for DRY tag opportunities
---@param file_path string
function M.analyze_file_for_dry_tags(file_path)
  local content = vim.fn.readfile(file_path)
  if #content == 0 then return end

  local rel_path = vim.fn.fnamemodify(file_path, ':.')

  -- Build context about the file
  local file_context = string.format([[
Analyze this code file for functions that should be tagged for reusability.

File: %s
Content:
```
%s
```

Instructions:
1. Identify functions that are good candidates for reuse (utility functions, helpers, common patterns)
2. Suggest adding these tags ABOVE the function definition:
   - # DRY: [description] - for functions that eliminate duplication
   - # UTIL: [description] - for utility functions
   - # HELPER: [description] - for helper functions
   - # PATTERN: [description] - for reusable patterns
   - # COMMON: [description] - for common functionality

Respond with suggested line insertions in this format:
{
  "suggestions": [
    {
      "line": 5,
      "tag": "# DRY: Input validation helper",
      "function_name": "validate_input",
      "reason": "This function validates user input and could be reused across multiple components"
    }
  ]
}

Only suggest tags for functions that would genuinely benefit from being tagged for reuse.
]], rel_path, table.concat(content, '\n'))

  -- Get provider
  local provider_name = config.get('provider')
  local provider = providers.get(provider_name)

  if not provider then
    vim.notify('Error: Provider ' .. provider_name .. ' not found', vim.log.levels.ERROR)
    return
  end

  -- Request analysis
  provider.complete_async("Analyze this file for DRY tag opportunities", file_context, {
    model = config.get('model'),
    temperature = 0.1  -- Low temperature for consistent analysis
  }, function(response, error)
    if error then
      vim.notify('Error analyzing ' .. rel_path .. ': ' .. error, vim.log.levels.ERROR)
      return
    end

    M.process_dry_suggestions(file_path, response)
  end)
end

---Process and present DRY tag suggestions
---@param file_path string
---@param response table
function M.process_dry_suggestions(file_path, response)
  if not response.suggestions or #response.suggestions == 0 then
    return  -- No suggestions for this file
  end

  local rel_path = vim.fn.fnamemodify(file_path, ':.')

  -- Open the file in a buffer
  local bufnr = vim.fn.bufnr(file_path, true)
  if bufnr == -1 then
    vim.notify("Could not open buffer for " .. rel_path, vim.log.levels.ERROR)
    return
  end

  -- Load file content
  vim.fn.bufload(bufnr)

  -- Process each suggestion
  for _, suggestion in ipairs(response.suggestions) do
    local line_num = suggestion.line or 1
    local tag_line = suggestion.tag or "# DRY: Reusable function"
    local func_name = suggestion.function_name or "unknown"
    local reason = suggestion.reason or "No reason provided"

    -- Show the suggestion as a diff
    local original_lines = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)
    local modified_lines = {tag_line}
    if #original_lines > 0 then
      table.insert(modified_lines, original_lines[1])
    end

    local description = string.format("Add DRY tag for %s(): %s", func_name, reason)

    -- Show diff for this suggestion
    vim.schedule(function()

      vim.notify(string.format("DRY tag suggestion for %s in %s:%d",
        func_name, rel_path, line_num), vim.log.levels.INFO)
    end)

    -- Only show one suggestion at a time to avoid overwhelming the user
    break
  end
end

return M