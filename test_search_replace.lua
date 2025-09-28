-- Test SEARCH/REPLACE format implementation
vim.opt.runtimepath:append('/Users/taran/Projects/todo-ai')

local diff = require('todo-ai.diff_native')
local schema = require('todo-ai.schema')

-- Create test buffer
local test_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_option(test_buf, 'filetype', 'python')

-- Set the buffer as current (needed for navigation)
vim.api.nvim_set_current_buf(test_buf)

-- Original content
local original_content = {
  "import sys",
  "",
  "# TODO: @ai add hello world function",
  "",
  "def main():",
  '    print("Starting program")',
  "    # TODO: @ai call hello function",
  '    print("Ending program")',
  "",
  'if __name__ == "__main__":',
  "    main()"
}

-- Set original content
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, original_content)

print("=== Testing SEARCH/REPLACE Format ===")
print("\nOriginal content:")
for i, line in ipairs(original_content) do
  print(string.format("%2d: %s", i, line))
end

-- Test response with SEARCH/REPLACE changes
local response = {
  changes = {
    {
      search = "# TODO: @ai add hello world function",
      replace = "def hello_world():\n    \"\"\"Say hello to the world.\"\"\"\n    print(\"Hello, World!\")",
      description = "Add hello_world function"
    },
    {
      search = '    print("Starting program")\n    # TODO: @ai call hello function\n    print("Ending program")',
      replace = '    print("Starting program")\n    hello_world()\n    print("Ending program")',
      description = "Replace TODO with hello_world() call"
    }
  },
  language = "python",
  explanation = "Added hello_world function and replaced TODO with function call"
}

print("\n=== Testing Direct Application ===")

-- Test applying changes directly
local lines = vim.deepcopy(original_content)
local applied_lines, count, err = schema.apply_changes(lines, response.changes)

if err then
  print("❌ Error applying changes: " .. err)
else
  print("✅ Successfully applied " .. count .. " changes")
  print("\nResult after direct application:")
  for i, line in ipairs(applied_lines) do
    print(string.format("%2d: %s", i, line))
  end
end

print("\n=== Testing Visual Diff Display ===")

-- Reset buffer for visual test
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, original_content)

-- Show visual diff
diff.show_response(test_buf, response)

-- Get buffer content after showing diff
local after_diff = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
print("\nBuffer after showing visual diff:")
for i, line in ipairs(after_diff) do
  print(string.format("%2d: %s", i, line))
end

-- Check if the visual diff is displayed correctly
local has_search_markers = false
local has_replace_markers = false
for _, line in ipairs(after_diff) do
  if line:match("<<<<<<< SEARCH") then
    has_search_markers = true
  end
  if line:match(">>>>>>> REPLACE") then
    has_replace_markers = true
  end
end

if has_search_markers and has_replace_markers then
  print("\n✅ Visual diff markers are displayed correctly")
else
  print("\n❌ Visual diff markers not found")
end

print("\n=== Testing Navigation and Accept/Reject ===")

-- Test navigation (if hunks exist)
if diff.state and diff.state.hunks then
  local num_hunks = #diff.state.hunks
  print("Number of hunks: " .. num_hunks)

  if num_hunks > 0 then
    print("Hunk 1 start line: " .. (diff.state.hunks[1].start_line or "nil"))
    print("Hunk 1 end line: " .. (diff.state.hunks[1].end_line or "nil"))

    -- Navigate to first hunk
    diff.next_hunk(test_buf)
    print("✅ Navigated to first hunk")

    -- Accept first hunk
    diff.accept_hunk(test_buf)
    print("✅ Accepted first hunk")

    -- Navigate to next hunk if exists
    if num_hunks > 1 then
      diff.next_hunk(test_buf)
      print("✅ Navigated to second hunk")

      -- Reject second hunk
      diff.reject_hunk(test_buf)
      print("✅ Rejected second hunk")
    end

    -- Apply changes
    print("\nApplying changes...")
    diff.apply_changes(test_buf)

    -- Check final content
    local final_content = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    print("\nFinal content after applying:")
    for i, line in ipairs(final_content) do
      print(string.format("%2d: %s", i, line))
    end

    -- Verify no TODOs remain and hello_world was added
    local has_todo = false
    local has_hello = false
    for _, line in ipairs(final_content) do
      if line:match("TODO") then
        has_todo = true
      end
      if line:match("hello_world") then
        has_hello = true
      end
    end

    if not has_todo and has_hello then
      print("\n✅ SEARCH/REPLACE implementation working correctly!")
    else
      print("\n❌ Issues detected:")
      print("  Has TODO: " .. tostring(has_todo))
      print("  Has hello_world: " .. tostring(has_hello))
    end
  end
else
  print("❌ No hunks created from changes")
end

-- Test cleanup
vim.api.nvim_buf_delete(test_buf, {force = true})
print("\n=== Test Complete ===")