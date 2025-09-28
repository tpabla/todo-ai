-- Test different virtual text placement strategies
local diff_formatter = require('todo-ai.diff_formatter')

print("=== Testing Virtual Text Placement ===\n")

-- Test 1: virt_lines_above at line 0
local function test_virt_above_line0()
  print("Test 1: virt_lines_above at line 0")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'line1', 'line2', 'line3'})

  local ns_id = vim.api.nvim_create_namespace('test1')

  -- Try at line 0
  local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
    virt_lines_above = true,
    virt_lines = {{{'HEADER AT LINE 0', 'Title'}}}
  })

  -- Verify
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  print("  Mark created: " .. tostring(mark_id > 0))
  print("  Marks found: " .. #marks)

  -- Open in window to see visual result
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = 40,
    height = 5,
    row = 1,
    col = 1,
    border = 'single'
  })

  vim.wait(1000, function() return false end)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, {force = true})

  return mark_id > 0
end

-- Test 2: virt_lines (not above) at end of line
local function test_virt_lines_end()
  print("\nTest 2: virt_lines at end of line")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'line1', 'line2', 'line3'})

  local ns_id = vim.api.nvim_create_namespace('test2')

  -- Try regular virt_lines (appears after the line)
  local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
    virt_lines = {{{'HEADER AFTER LINE 1', 'Title'}}}
  })

  -- Verify
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  print("  Mark created: " .. tostring(mark_id > 0))
  print("  Marks found: " .. #marks)

  -- Open in window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = 40,
    height = 5,
    row = 7,
    col = 1,
    border = 'single'
  })

  vim.wait(1000, function() return false end)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, {force = true})

  return mark_id > 0
end

-- Test 3: Try different line positions
local function test_different_positions()
  print("\nTest 3: Headers at different positions")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'line1',
    'line2',
    'line3',
    'line4',
    'line5'
  })

  local ns_id = vim.api.nvim_create_namespace('test3')

  -- Place headers at different positions
  local positions = {0, 1, 2}
  for _, pos in ipairs(positions) do
    vim.api.nvim_buf_set_extmark(buf, ns_id, pos, 0, {
      virt_lines_above = true,
      virt_lines = {{{'HEADER AT LINE ' .. (pos + 1), 'Title'}}}
    })
  end

  -- Check all marks
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  print("  Created " .. #marks .. " headers")

  for _, mark in ipairs(marks) do
    local row = mark[2]
    local details = mark[4]
    if details.virt_lines then
      print("    Header at row " .. row)
    end
  end

  -- Open in window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = 40,
    height = 10,
    row = 13,
    col = 1,
    border = 'single'
  })

  vim.wait(1000, function() return false end)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, {force = true})

  return #marks == 3
end

-- Test 4: Test with actual diff_formatter
local function test_with_formatter()
  print("\nTest 4: Using actual diff_formatter")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'function test()',
    '    -- Modified line',
    '    print("hello")',
    'end'
  })

  local ns_id = vim.api.nvim_create_namespace('test4')

  local state = {
    accepted_diffs = {},
    rejected_diffs = {}
  }

  local hunks = {{
    change_index = 1,
    start_line = 1,
    end_line = 4,
    display_start = 1,
    display_end = 4,
    description = "Test change",
    search_text = "function test()\n    print(\"hello\")\nend"
  }}

  -- Apply formatting
  diff_formatter.apply_formatting(buf, hunks, state, ns_id)

  -- Check marks
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  print("  Marks created: " .. #marks)

  local found_header = false
  for _, mark in ipairs(marks) do
    if mark[4].virt_lines_above or mark[4].virt_lines then
      found_header = true
      print("  ✓ Found header at line " .. mark[2])
    end
  end

  if not found_header then
    print("  ✗ No header found")
  end

  -- Open in window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = 50,
    height = 8,
    row = 1,
    col = 45,
    border = 'single'
  })

  vim.wait(1000, function() return false end)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, {force = true})

  return found_header
end

-- Run all tests
print("\nRunning placement tests...")
local results = {
  test_virt_above_line0(),
  test_virt_lines_end(),
  test_different_positions(),
  test_with_formatter()
}

-- Summary
print("\n=== Summary ===")
print("Test 1 (virt_lines_above at 0): " .. (results[1] and "PASS" or "FAIL"))
print("Test 2 (virt_lines at end): " .. (results[2] and "PASS" or "FAIL"))
print("Test 3 (multiple positions): " .. (results[3] and "PASS" or "FAIL"))
print("Test 4 (with formatter): " .. (results[4] and "PASS" or "FAIL"))

print("\nNote: Windows were opened to visually inspect placement.")
print("If headers weren't visible in windows, there's a rendering issue.")

vim.wait(2000, function() return false end)
vim.cmd('qall!')