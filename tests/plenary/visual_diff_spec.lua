local diff_native = require('todo-ai.diff_native')
local diff_formatter = require('todo-ai.diff_formatter')

describe("Visual diff display", function()
  local test_buf
  local ns_id
  
  before_each(function()
    -- Create test buffer
    test_buf = vim.api.nvim_create_buf(false, true)
    ns_id = vim.api.nvim_create_namespace('test_diff')
    
    -- Reset state with all required fields
    diff_native.state = {
      hunks = {},
      rejected_diffs = {},
      accepted_diffs = {},  -- This was missing
      target_buf = test_buf,
      ns_id = ns_id
    }
  end)
  
  after_each(function()
    if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, {force = true})
    end
  end)
  
  it("highlights replacement lines with green", function()
    local original = {"def old():", "  return 1", "end"}
    local changes = {{
      search = "def old():\n  return 1\nend",
      replace = "def new():\n  return 2\nend",
      description = "Update function per TODO"
    }}
    
    -- Set up hunks
    diff_native.state.hunks = {{
      change_index = 1,
      start_line = 1,
      end_line = 3,
      search_text = changes[1].search,
      replace_text = changes[1].replace,
      display_start = 1,  -- These should be set by build_search_replace_display
      display_end = 3
    }}
    
    -- Apply the display
    local display_lines = {"def new():", "  return 2", "end"}
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, display_lines)
    
    -- Apply formatting
    diff_formatter.apply_formatting(test_buf, diff_native.state.hunks, diff_native.state, ns_id)
    
    -- Check for green highlighting extmarks
    local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, ns_id, 0, -1, {details = true})
    
    local found_green_highlight = false
    local found_gutter_sign = false
    
    for _, mark in ipairs(extmarks) do
      local details = mark[4]
      if details.hl_group == "String" or details.hl_group == "DiffAdd" then
        found_green_highlight = true
      end
      if details.sign_text == "▸" then
        found_gutter_sign = true
      end
    end
    
    assert.is_true(found_green_highlight, "Should have green highlighting on replacement lines")
    assert.is_true(found_gutter_sign, "Should have ▸ sign in gutter for additions")
  end)
  
  it("shows removed lines as red virtual text", function()
    local removed_lines = {"def old():", "  return 1"}
    local virtual_lines = diff_formatter.format_removed_lines(removed_lines)
    
    assert.equals(2, #virtual_lines)
    
    -- Check first line has red arrow and content
    assert.equals("◂ ", virtual_lines[1][1][1])
    assert.equals("Error", virtual_lines[1][1][2]) -- Red color
    assert.equals("def old():", virtual_lines[1][2][1])
    assert.equals("Error", virtual_lines[1][2][2]) -- Red color
  end)
  
  it("creates proper header with TODO description", function()
    local header = diff_formatter.create_header("pending", "Convert to martini per TODO request")
    
    assert.is_table(header)
    assert.equals(1, #header) -- Single line header
    
    local header_line = header[1]
    local found_pending = false
    local found_description = false
    
    for _, part in ipairs(header_line) do
      if part[1]:match("PENDING") then
        found_pending = true
      end
      if part[1]:match("Convert to martini") then
        found_description = true
      end
    end
    
    assert.is_true(found_pending, "Should show PENDING status")
    assert.is_true(found_description, "Should show TODO description")
  end)
end)
