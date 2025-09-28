-- Comprehensive test for header display in visual diff
local diff_native = require('todo-ai.diff_native')
local diff_formatter = require('todo-ai.diff_formatter')
local logger = require('todo-ai.logger')

print("=== Testing Header Display ===\n")

-- Test 1: Create a simple change and verify header
local function test_header_display()
  print("Test 1: Basic header display")

  -- Create test buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'def hello():',
    '    print("Hello, World")',
    '    return True'
  })

  -- Mock response with a single change
  local response = {
    changes = {{
      search = 'def hello():\n    print("Hello, World")\n    return True',
      replace = 'def hello():\n    """Simple hello world program."""\n    print("Hello, World!")\n    return True',
      description = "Add docstring per TODO request"
    }},
    explanation = "Added docstring to function"
  }

  -- Initialize state
  diff_native.state = {
    target_buf = buf,
    original_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    response = response,
    hunks = {},
    rejected_diffs = {},
    accepted_diffs = {}
  }

  -- Process the change to create hunks
  for i, change in ipairs(response.changes) do
    table.insert(diff_native.state.hunks, {
      change_index = i,
      search = change.search,
      replace = change.replace,
      description = change.description,
      start_line = 1,
      end_line = 3,
      display_start = 1,
      display_end = 4  -- One more line due to docstring
    })
  end

  -- Create namespace
  local ns_id = vim.api.nvim_create_namespace('test_header')

  -- Set buffer to display content
  local display_lines = {
    'def hello():',
    '    """Simple hello world program."""',
    '    print("Hello, World!")',
    '    return True'
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  -- Apply formatting
  print("  Applying formatting...")
  diff_formatter.apply_formatting(buf, diff_native.state.hunks, diff_native.state, ns_id)

  -- Check for extmarks
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  print("  Found " .. #extmarks .. " extmarks")

  local found_header = false
  local found_virt_lines = false

  for _, mark in ipairs(extmarks) do
    local row, col, details = mark[2], mark[3], mark[4]
    print(string.format("  Extmark at row %d, col %d", row, col))

    if details.virt_lines_above then
      found_virt_lines = true
      print("    -> Has virt_lines_above: YES")
      for i, virt_line in ipairs(details.virt_lines) do
        local text = ""
        for _, chunk in ipairs(virt_line) do
          text = text .. chunk[1]
        end
        print("       Line " .. i .. ": " .. text)
      end
    end

    if details.virt_lines then
      found_header = true
      print("    -> Has virt_lines: " .. #details.virt_lines .. " lines")
    end

    if details.line_hl_group then
      print("    -> Line highlight: " .. details.line_hl_group)
    end

    if details.sign_text then
      print("    -> Sign text: " .. details.sign_text)
    end
  end

  print("\n  Results:")
  print("    Header found: " .. tostring(found_header or found_virt_lines))
  print("    Buffer line count: " .. vim.api.nvim_buf_line_count(buf))

  -- Cleanup
  vim.api.nvim_buf_delete(buf, {force = true})

  return found_header or found_virt_lines
end

-- Test 2: Test with actual diff_native.show_response
local function test_show_response()
  print("\nTest 2: Full show_response flow")

  -- Create test buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'def main():',
    '    print("Hello")',
    '    return 0'
  })

  -- Make it current
  vim.api.nvim_set_current_buf(buf)

  -- Mock response
  local response = {
    changes = {{
      search = 'def main():\n    print("Hello")\n    return 0',
      replace = 'def main():\n    """Main function."""\n    print("Hello, World!")\n    return 0',
      description = "Update main function per TODO"
    }},
    explanation = "Updated main function"
  }

  -- Call show_response
  print("  Calling diff_native.show_response...")
  diff_native.show_response(buf, response)

  -- Wait for scheduled operations
  vim.wait(100, function() return false end)

  -- Check results
  local ns_id = diff_native.state.ns_id
  if ns_id then
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
    print("  Extmarks found: " .. #extmarks)

    for i, mark in ipairs(extmarks) do
      local details = mark[4]
      if details.virt_lines_above or details.virt_lines then
        print("  ✓ Virtual text found at line " .. mark[2])
        return true
      end
    end
  else
    print("  ✗ No namespace created")
  end

  print("  ✗ No virtual text found")
  return false
end

-- Test 3: Direct extmark test
local function test_direct_extmark()
  print("\nTest 3: Direct extmark placement")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'line1', 'line2', 'line3'})

  local ns_id = vim.api.nvim_create_namespace('direct_test')

  -- Try setting extmark directly
  print("  Setting extmark at line 0 with virt_lines_above...")
  local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
    virt_lines_above = true,
    virt_lines = {
      {{'=== HEADER TEST ===', 'Title'}},
      {{'This should appear above line 1', 'Normal'}}
    }
  })

  print("  Mark ID: " .. mark_id)

  -- Verify it was set
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  print("  Extmarks found: " .. #marks)

  if #marks > 0 then
    print("  ✓ Direct extmark test passed")
    vim.api.nvim_buf_delete(buf, {force = true})
    return true
  else
    print("  ✗ Direct extmark test failed")
    vim.api.nvim_buf_delete(buf, {force = true})
    return false
  end
end

-- Run tests
local results = {}
results[1] = test_header_display()
results[2] = test_show_response()
results[3] = test_direct_extmark()

-- Summary
print("\n=== Test Summary ===")
print("Test 1 (Basic header): " .. (results[1] and "PASS" or "FAIL"))
print("Test 2 (Full flow): " .. (results[2] and "PASS" or "FAIL"))
print("Test 3 (Direct extmark): " .. (results[3] and "PASS" or "FAIL"))

if not results[1] or not results[2] then
  print("\nHeader display is broken. Investigating...")

  -- Additional diagnostics
  print("\nDiagnostics:")
  print("  diff_native.state.hunks: " .. vim.inspect(diff_native.state.hunks))
  if diff_native.state.ns_id then
    print("  Namespace ID: " .. diff_native.state.ns_id)
  end
end

print("\nTest complete!")
vim.cmd('qall!')