-- Test script to verify hanging issues are fixed
vim.opt.runtimepath:append('/Users/taran/Projects/todo-ai')

local diff_native = require('todo-ai.diff_native')
local schema = require('todo-ai.schema')

print("=== Testing Hanging Fixes ===\n")

-- Test 1: Large file performance
print("Test 1: Large file handling...")
local large_lines = {}
for i = 1, 1000 do
  table.insert(large_lines, "line " .. i)
end

local start = vim.loop.now()
local result = schema.apply_changes(large_lines, {
  {search = "line 500", replace = "MODIFIED LINE"}
})
local elapsed = vim.loop.now() - start

if elapsed < 1000 then
  print("✅ Large file processed in " .. elapsed .. "ms")
else
  print("❌ Large file took too long: " .. elapsed .. "ms")
end

-- Test 2: Infinite loop protection
print("\nTest 2: Infinite loop protection...")
local test_lines = {"a", "b", "c"}
local circular_changes = {
  {search = "a", replace = "b"},
  {search = "b", replace = "a"}
}

local ok, err = pcall(function()
  return schema.apply_changes(test_lines, circular_changes)
end)

if ok then
  print("✅ Circular references handled without hanging")
else
  print("❌ Error with circular references: " .. tostring(err))
end

-- Test 3: Calculate diff hunks with problematic input
print("\nTest 3: Diff calculation with edge cases...")
local original = {"line1", "line2", "line3"}
local modified = {"line1", "line2", "line3"} -- Same content

local start2 = vim.loop.now()
local hunks = diff_native.calculate_diff_hunks(original, modified)
local elapsed2 = vim.loop.now() - start2

if elapsed2 < 100 and #hunks == 0 then
  print("✅ Identical files handled correctly in " .. elapsed2 .. "ms")
else
  print("❌ Issue with identical files: " .. elapsed2 .. "ms, " .. #hunks .. " hunks")
end

-- Test 4: Empty buffer handling
print("\nTest 4: Empty buffer handling...")
local empty_ok = pcall(function()
  diff_native.clear_diff()
  diff_native.state.response = {changes = {{search = "test", replace = "new"}}}
  diff_native.state.hunks = {}
  diff_native.state.rejected_diffs = {}

  local display = diff_native.build_search_replace_display({}, diff_native.state.response.changes)
  return display
end)

if empty_ok then
  print("✅ Empty buffer handled gracefully")
else
  print("❌ Empty buffer caused error")
end

-- Test 5: Very long lines
print("\nTest 5: Very long lines...")
local long_line = string.rep("x", 10000)
local long_lines = {long_line, "normal", long_line}

local start3 = vim.loop.now()
local long_result = schema.apply_changes(long_lines, {
  {search = "normal", replace = "CHANGED"}
})
local elapsed3 = vim.loop.now() - start3

if elapsed3 < 500 then
  print("✅ Long lines processed in " .. elapsed3 .. "ms")
else
  print("❌ Long lines took too long: " .. elapsed3 .. "ms")
end

print("\n=== All Tests Complete ===")
print("The hanging issues should be fixed. If any test hangs, press Ctrl+C to interrupt.")