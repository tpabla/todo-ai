-- Test the debug headers command
local diff_native = require('todo-ai.diff_native')

print("=== Testing TodoAIDebugHeaders Command ===\n")

-- Create test buffer with diff display
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)

-- Set initial content
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'function test()',
  '    print("hello")',
  'end'
})

-- Mock response
local response = {
  changes = {{
    search = 'function test()\n    print("hello")\nend',
    replace = 'function test()\n    -- Add comment\n    print("hello, world!")\nend',
    description = "Update function per TODO"
  }},
  explanation = "Added comment and updated message"
}

-- Show the response to create diff display
print("Setting up diff display...")
diff_native.show_response(buf, response)

-- Wait for scheduled operations
vim.wait(200, function() return false end)

-- Test the debug command
print("\nRunning debug_headers()...")
print("=" .. string.rep("=", 50))
diff_native.debug_headers()
print("=" .. string.rep("=", 50))

-- Also test via command
print("\nTesting :TodoAIDebugHeaders command...")
vim.cmd('TodoAIDebugHeaders')

print("\nTest complete!")
vim.cmd('qall!')