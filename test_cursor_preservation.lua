-- Test cursor preservation when accepting diffs
local diff = require('todo-ai.diff_native')

-- Create test buffer
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'line1', 'line2', 'line3', 'line4', 'line5'})

-- Make it current and set cursor to line 3
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_cursor(0, {3, 0})
print('Initial cursor at line', vim.api.nvim_win_get_cursor(0)[1])

-- Setup state as if we accepted a change
diff.state = {
  target_buf = buf,
  original_lines = {'line1', 'line2', 'line3', 'line4', 'line5'},
  response = {
    changes = {{
      search = 'line1',
      replace = 'modified_line1'
    }}
  },
  rejected_diffs = {},
  accepted_diffs = {[1] = true},
  hunks = {{
    change_index = 1,
    start_line = 1,
    end_line = 1,
    search_text = 'line1',
    replace_text = 'modified_line1'
  }}
}

-- Simulate accepting changes and refreshing display
local new_lines = {'modified_line1', 'line2', 'line3', 'line4', 'line5'}
diff.refresh_display()

-- Check cursor position
local final_cursor = vim.api.nvim_win_get_cursor(0)[1]
print('Cursor after accept at line', final_cursor)

if final_cursor == 3 then
  print('SUCCESS: Cursor preserved at line 3!')
else
  print('FAILURE: Cursor jumped to line', final_cursor)
end

vim.cmd('qall!')