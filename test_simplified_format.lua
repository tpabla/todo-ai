-- Test simplified diff-only format
vim.opt.runtimepath:append('/Users/taran/Projects/todo-ai')

local diff = require('todo-ai.diff_native')

-- Create test buffer
local test_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_option(test_buf, 'filetype', 'python')

-- Original content
local original_content = {
  "import sys",
  "",
  "#TODO: @ai add hello world function",
  "",
  "def main():",
  '    print("Old version")',
  "",
  'if __name__ == "__main__":',
  "    main()"
}

-- Set original content
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, original_content)

print("=== Testing Simplified Diff Format ===")

-- Test new unified format
local response = {
  diff = [[
@@ -1,9 +1,11 @@
 import sys

-#TODO: @ai add hello world function
+def hello_world():
+    print("Hello, World!")

 def main():
-    print("Old version")
+    hello_world()
+    print("New version")

 if __name__ == "__main__":
     main()
]],
  language = "python",
  explanation = "Added hello_world function and updated main to call it"
}

print("Testing diff format:")
diff.show_response(test_buf, response)

local after_diff = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
print("Lines after diff: " .. #after_diff)

-- Check if TODO was replaced
local has_todo = false
local has_hello = false
for _, line in ipairs(after_diff) do
  if line:match("TODO") then
    has_todo = true
  end
  if line:match("hello_world") then
    has_hello = true
  end
end

if not has_todo and has_hello then
  print("✓ Diff format works (TODO removed, hello_world added)")
else
  print("❌ Diff format failed")
  print("Has TODO: " .. tostring(has_todo))
  print("Has hello_world: " .. tostring(has_hello))
end

-- Test cleanup
vim.api.nvim_buf_delete(test_buf, {force = true})
print("\n=== Test Complete ===")