-- Test that simulates the actual TODO workflow
local diff_native = require('todo-ai.diff_native')
local diff_formatter = require('todo-ai.diff_formatter')
local logger = require('todo-ai.logger')

print("=== Testing Actual TODO Workflow ===\n")

-- Test function that simulates what happens when user runs AI on a TODO
local function test_todo_workflow()
  print("Simulating actual TODO workflow...")

  -- Create and setup buffer like in real usage
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)

  -- Set initial content (like a real file with a TODO)
  local initial_content = {
    '-- TODO: Add error handling to this function',
    'function process_data(data)',
    '    local result = data * 2',
    '    return result',
    'end'
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_content)

  -- Simulate AI response
  local response = {
    changes = {{
      search = 'function process_data(data)\n    local result = data * 2\n    return result\nend',
      replace = 'function process_data(data)\n    -- Check for nil input\n    if not data then\n        return nil, "Data cannot be nil"\n    end\n    \n    -- Process the data\n    local result = data * 2\n    return result\nend',
      description = "Add error handling per TODO request"
    }},
    explanation = "Added nil check with error return"
  }

  -- Call show_response like the real workflow does
  print("  Calling show_response...")
  diff_native.show_response(buf, response)

  -- Wait for scheduled operations to complete
  vim.wait(200, function() return false end)

  -- Check for extmarks
  if diff_native.state.ns_id then
    local all_marks = vim.api.nvim_buf_get_extmarks(buf, diff_native.state.ns_id, 0, -1, {details = true})
    print("  Total extmarks after show_response: " .. #all_marks)

    -- Look for virtual text headers
    local found_header = false
    for i, mark in ipairs(all_marks) do
      local details = mark[4]
      if details.virt_lines_above or details.virt_lines then
        found_header = true
        print("  ✓ Found virtual text header at line " .. mark[2])

        -- Print what's in the virtual text
        local virt_content = details.virt_lines or {}
        if details.virt_lines_above and details.virt_lines then
          virt_content = details.virt_lines
        end

        for j, virt_line in ipairs(virt_content) do
          local text = ""
          for _, chunk in ipairs(virt_line) do
            text = text .. chunk[1]
          end
          print("    Virtual line " .. j .. ": " .. text:sub(1, 50) .. "...")
        end
      end
    end

    if not found_header then
      print("  ✗ No virtual text headers found")

      -- Additional debugging
      print("\n  Debug info:")
      print("    Buffer line count: " .. vim.api.nvim_buf_line_count(buf))
      print("    Namespace ID: " .. diff_native.state.ns_id)
      print("    Hunks: " .. vim.inspect(diff_native.state.hunks))

      -- Check if clear was called
      print("\n  Checking logs for clear_inline_diff calls...")
      -- The logs would show if clear was called
    end

    return found_header
  else
    print("  ✗ No namespace created")
    return false
  end
end

-- Test with multiple schedules to catch timing issues
local function test_with_delays()
  print("\nTesting with various delays...")

  local delays = {0, 50, 100, 200, 500}

  for _, delay in ipairs(delays) do
    print(string.format("  Testing with %dms delay...", delay))

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'line1', 'line2', 'line3'})

    local response = {
      changes = {{
        search = 'line1\nline2\nline3',
        replace = 'line1\nmodified line2\nline3',
        description = "Test change"
      }},
      explanation = "Test"
    }

    diff_native.show_response(buf, response)

    vim.wait(delay, function() return false end)

    if diff_native.state.ns_id then
      local marks = vim.api.nvim_buf_get_extmarks(buf, diff_native.state.ns_id, 0, -1, {details = true})
      local has_virt = false

      for _, mark in ipairs(marks) do
        if mark[4].virt_lines_above or mark[4].virt_lines then
          has_virt = true
          break
        end
      end

      print(string.format("    -> %s (found %d extmarks, virtual text: %s)",
        has_virt and "PASS" or "FAIL",
        #marks,
        tostring(has_virt)))
    end

    -- Cleanup
    vim.api.nvim_buf_delete(buf, {force = true})
  end
end

-- Check for autocmd interference
local function check_autocmds()
  print("\nChecking for autocmd interference...")

  -- Get all autocmds that might affect buffers
  local autocmds = vim.api.nvim_get_autocmds({})
  local suspicious = {}

  local events_to_check = {
    'BufEnter', 'BufLeave', 'BufWinEnter', 'BufWinLeave',
    'WinEnter', 'WinLeave', 'TextChanged', 'TextChangedI',
    'CursorMoved', 'CursorMovedI'
  }

  for _, autocmd in ipairs(autocmds) do
    for _, event in ipairs(events_to_check) do
      if autocmd.event == event then
        table.insert(suspicious, {
          event = autocmd.event,
          group = autocmd.group_name or "unnamed",
          desc = autocmd.desc or "no description"
        })
      end
    end
  end

  print("  Found " .. #suspicious .. " potentially interfering autocmds")
  for i, ac in ipairs(suspicious) do
    if i <= 5 then -- Only show first 5
      print(string.format("    - %s in group '%s': %s", ac.event, ac.group, ac.desc))
    end
  end
end

-- Run all tests
print("\n1. Main workflow test:")
local result1 = test_todo_workflow()

print("\n2. Timing tests:")
test_with_delays()

print("\n3. Autocmd check:")
check_autocmds()

-- Summary
print("\n=== Summary ===")
print("Main workflow test: " .. (result1 and "PASS" or "FAIL"))

if not result1 then
  print("\nThe header display is NOT working in the actual workflow.")
  print("This confirms the issue persists despite the basic tests passing.")
  print("\nPossible causes:")
  print("1. Race condition with buffer updates")
  print("2. Autocmd interference")
  print("3. Namespace being cleared unexpectedly")
  print("4. Virtual text limitations with certain buffer settings")
end

print("\nTest complete!")
vim.cmd('qall!')