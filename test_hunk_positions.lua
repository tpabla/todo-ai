-- Test hunk positions in SEARCH/REPLACE display
vim.opt.runtimepath:append('/Users/taran/Projects/todo-ai')

local diff = require('todo-ai.diff_native')

-- Create test buffer
local test_buf = vim.api.nvim_create_buf(false, true)

-- Original content
local original_content = {
  "import sys",
  "",
  "# TODO: @ai add hello world function",
  "",
  "def main():",
  '    print("Starting program")',
}

-- Set original content
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, original_content)

-- Test response
local response = {
  changes = {
    {
      search = "# TODO: @ai add hello world function",
      replace = "def hello():\n    print('Hello')",
      description = "Add hello function"
    }
  },
  language = "python",
  explanation = "Added hello function"
}

-- Show diff
diff.show_response(test_buf, response)

-- Check state
print("Hunks in state: " .. #diff.state.hunks)
if #diff.state.hunks > 0 then
  local hunk = diff.state.hunks[1]
  print("Hunk 1 start_line: " .. (hunk.start_line or "nil"))
  print("Hunk 1 end_line: " .. (hunk.end_line or "nil"))
end

-- Check buffer lines
local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
print("Buffer line count: " .. #lines)
for i = 1, math.min(10, #lines) do
  print(string.format("Line %d: %s", i, lines[i]))
end

-- Cleanup
vim.api.nvim_buf_delete(test_buf, {force = true})