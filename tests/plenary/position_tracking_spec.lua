local diff_native = require('todo-ai.diff_native')
local search_replace = require('todo-ai.search_replace')

describe("Position tracking after SEARCH/REPLACE", function()
  
  before_each(function()
    -- Reset state
    diff_native.state = {
      hunks = {},
      rejected_diffs = {}
    }
  end)
  
  it("updates hunk positions to match display buffer", function()
    local original = {"line1", "old_func()", "line3"}
    local changes = {{
      search = "old_func()",
      replace = "new_func()\n  extra_line()"
    }}
    
    -- Set up initial hunks with original positions
    diff_native.state.hunks = {{
      change_index = 1,
      start_line = 2,  -- Original position
      end_line = 2,
      search_text = changes[1].search,
      replace_text = changes[1].replace
    }}
    
    -- Build display (should update positions)
    local display = diff_native.build_search_replace_display(original, changes)
    
    -- Check display is correct
    assert.equals(4, #display)  -- Should be 4 lines now (added one)
    assert.equals("line1", display[1])
    assert.equals("new_func()", display[2])
    assert.equals("  extra_line()", display[3])
    assert.equals("line3", display[4])
    
    -- Check hunk positions were updated to display positions
    local hunk = diff_native.state.hunks[1]
    assert.not_nil(hunk.display_start, "Should have display_start")
    assert.not_nil(hunk.display_end, "Should have display_end")
    
    -- These should point to where the replacement actually is
    assert.equals(2, hunk.display_start, "Replacement starts at line 2")
    assert.equals(3, hunk.display_end, "Replacement ends at line 3 (2 lines)")
  end)
  
  it("handles multiple changes with position shifts", function()
    local original = {"func1()", "func2()", "func3()"}
    local changes = {
      {
        search = "func1()",
        replace = "new_func1()\n  // comment"
      },
      {
        search = "func3()",
        replace = "new_func3()"
      }
    }
    
    -- Set up hunks
    diff_native.state.hunks = {
      {change_index = 1, start_line = 1, end_line = 1},
      {change_index = 2, start_line = 3, end_line = 3}
    }
    
    local display = diff_native.build_search_replace_display(original, changes)
    
    -- First change adds a line, so second change position shifts
    assert.equals(1, diff_native.state.hunks[1].display_start)
    assert.equals(2, diff_native.state.hunks[1].display_end) -- 2 lines
    
    -- Second change should be shifted down by 1
    assert.equals(4, diff_native.state.hunks[2].display_start) -- Was line 3, now 4
    assert.equals(4, diff_native.state.hunks[2].display_end)
  end)
  
  it("handles rejected changes correctly", function()
    local original = {"func1()", "func2()", "func3()"}
    local changes = {
      {search = "func1()", replace = "new1()"},
      {search = "func2()", replace = "new2()"},
      {search = "func3()", replace = "new3()"}
    }
    
    -- Reject the second change
    diff_native.state.rejected_diffs = {[2] = true}
    diff_native.state.hunks = {
      {change_index = 1, start_line = 1, end_line = 1},
      {change_index = 2, start_line = 2, end_line = 2},
      {change_index = 3, start_line = 3, end_line = 3}
    }
    
    local display = diff_native.build_search_replace_display(original, changes)
    
    -- Display should have func2 unchanged
    assert.equals("new1()", display[1])
    assert.equals("func2()", display[2])  -- Unchanged
    assert.equals("new3()", display[3])
    
    -- Positions should reflect this
    assert.equals(1, diff_native.state.hunks[1].display_start)
    assert.equals(3, diff_native.state.hunks[3].display_start)
  end)
end)
