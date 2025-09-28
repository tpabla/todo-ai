-- Native diff display with per-hunk accept/reject
local M = {}
local schema = require('todo-ai.schema')

M.state = {
  target_buf = nil,
  response = nil,  -- Store full response for applying changes
  hunks = {},      -- Store individual hunks for cursor-based operations
  original_lines = nil,  -- Store original buffer content for reject
}

-- Show all changes at once using mini.diff
function M.show_response(target_buf, response)
  M.state.target_buf = target_buf
  M.state.response = response
  M.state.hunks = {}

  -- Get current buffer content
  local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
  local new_lines

  -- Apply changes based on response format
  if response.changes then
    new_lines = schema.apply_changes(lines, response.changes)
    -- Store hunks for individual operations
    for _, change in ipairs(response.changes) do
      table.insert(M.state.hunks, {
        start_line = change.start_line,
        end_line = change.end_line,
        change = change,
        type = 'change'
      })
    end
  elseif response.edits then
    new_lines = schema.apply_edits(lines, response.edits)
    -- Convert edits to hunks
    for line_str, content in pairs(response.edits) do
      local line_num = tonumber(line_str)
      if line_num then
        table.insert(M.state.hunks, {
          start_line = line_num,
          end_line = line_num,
          new_content = content,
          type = 'edit'
        })
      end
    end
    -- Sort hunks by line number
    table.sort(M.state.hunks, function(a, b) return a.start_line < b.start_line end)
  elseif response.replace_buffer and response.changes and #response.changes > 0 then
    -- Full buffer replacement
    local change = response.changes[1]
    if change.lines then
      new_lines = change.lines
    elseif change.code then
      new_lines = vim.split(change.code, '\n', { plain = true })
    end
    M.state.hunks = {{
      start_line = 1,
      end_line = #lines,
      change = change,
      type = 'replace_all'
    }}
  else
    vim.api.nvim_echo({{'No changes to display', 'WarningMsg'}}, false, {})
    return
  end

  -- Store original content for reject operation
  M.state.original_lines = lines

  -- Apply the changes to the buffer first
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, new_lines)

  -- Ensure signcolumn is visible
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == target_buf then
      vim.wo[win].signcolumn = 'yes'
    end
  end

  -- Try mini.diff first
  local mini_diff_worked = false
  local ok, mini_diff = pcall(require, 'mini.diff')
  if ok then
    -- Ensure mini.diff is setup
    if not mini_diff.config then
      mini_diff.setup({
        view = {
          style = 'sign',
          signs = { add = '+', change = '~', delete = '-' },
        },
      })
    end

    -- Try to enable and set reference
    local success = pcall(function()
      mini_diff.enable(target_buf)
      mini_diff.set_ref_text(target_buf, table.concat(lines, '\n'))
      mini_diff_worked = true
    end)

    if not success then
      -- Try again with delay
      vim.defer_fn(function()
        local retry_success = pcall(function()
          mini_diff.enable(target_buf)
          mini_diff.set_ref_text(target_buf, table.concat(lines, '\n'))
        end)

        if not retry_success then
          -- Use native diff as fallback
          M.show_native_diff(target_buf, lines, new_lines)
          vim.api.nvim_echo({{'Using native diff highlighting', 'Normal'}}, false, {})
        end
      end, 50)
    end
  end

  -- If mini.diff didn't work immediately, use native diff
  if not mini_diff_worked then
    M.show_native_diff(target_buf, lines, new_lines)
  end

  -- Don't toggle overlay - let signs show in the gutter
  -- mini_diff.toggle_overlay(target_buf)

  -- Show a brief inline notification
  local num_changes = #M.state.hunks
  vim.api.nvim_echo({
    {"📝 ", "Special"},
    {string.format("%d changes ready. ", num_changes), "Normal"},
    {"<leader>tA", "Special"},
    {" accept all, ", "Normal"},
    {"<leader>tR", "Special"},
    {" reject all", "Normal"}
  }, false, {})

  -- Setup buffer-local keymaps for navigation
  M.setup_keymaps(target_buf)
end

-- Setup keymaps for the buffer
function M.setup_keymaps(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Navigation between hunks (using ]] and [[ for section-like navigation)
  vim.keymap.set('n', ']]', function() M.goto_next_hunk() end,
    vim.tbl_extend('force', opts, { desc = 'Go to next change' }))
  vim.keymap.set('n', '[[', function() M.goto_prev_hunk() end,
    vim.tbl_extend('force', opts, { desc = 'Go to previous change' }))

  -- Also support ]h and [h for consistency with other diff tools
  vim.keymap.set('n', ']h', function() M.goto_next_hunk() end,
    vim.tbl_extend('force', opts, { desc = 'Go to next change' }))
  vim.keymap.set('n', '[h', function() M.goto_prev_hunk() end,
    vim.tbl_extend('force', opts, { desc = 'Go to previous change' }))

  -- All changes operations (capital letters for ALL)
  vim.keymap.set('n', '<leader>tA', function() M.accept() end,
    vim.tbl_extend('force', opts, { desc = 'Accept ALL changes in buffer' }))
  vim.keymap.set('n', '<leader>tR', function() M.reject() end,
    vim.tbl_extend('force', opts, { desc = 'Reject ALL changes in buffer' }))

  -- Per-hunk operations (lowercase for cursor position)
  vim.keymap.set('n', '<leader>ta', function() M.accept_at_cursor() end,
    vim.tbl_extend('force', opts, { desc = 'Accept change at cursor' }))
  vim.keymap.set('n', '<leader>tr', function() M.reject_at_cursor() end,
    vim.tbl_extend('force', opts, { desc = 'Reject change at cursor' }))
end

-- Find which hunk the cursor is in
function M.get_hunk_at_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for i, hunk in ipairs(M.state.hunks) do
    if cursor_line >= hunk.start_line and cursor_line <= hunk.end_line then
      return i, hunk
    end
  end

  -- If not in a hunk, find nearest
  local nearest_idx, nearest_dist = nil, math.huge
  for i, hunk in ipairs(M.state.hunks) do
    local dist = math.min(
      math.abs(cursor_line - hunk.start_line),
      math.abs(cursor_line - hunk.end_line)
    )
    if dist < nearest_dist then
      nearest_dist = dist
      nearest_idx = i
    end
  end

  return nearest_idx, M.state.hunks[nearest_idx]
end

-- Navigate to next hunk
function M.goto_next_hunk()
  if not M.state.hunks or #M.state.hunks == 0 then
    vim.api.nvim_echo({{'No changes to navigate', 'WarningMsg'}}, false, {})
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for _, hunk in ipairs(M.state.hunks) do
    if hunk.start_line > cursor_line then
      vim.api.nvim_win_set_cursor(0, {hunk.start_line, 0})
      return
    end
  end

  -- Wrap to first hunk
  vim.api.nvim_win_set_cursor(0, {M.state.hunks[1].start_line, 0})
end

-- Navigate to previous hunk
function M.goto_prev_hunk()
  if not M.state.hunks or #M.state.hunks == 0 then
    vim.api.nvim_echo({{'No changes to navigate', 'WarningMsg'}}, false, {})
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for i = #M.state.hunks, 1, -1 do
    local hunk = M.state.hunks[i]
    if hunk.end_line < cursor_line then
      vim.api.nvim_win_set_cursor(0, {hunk.start_line, 0})
      return
    end
  end

  -- Wrap to last hunk
  local last_hunk = M.state.hunks[#M.state.hunks]
  vim.api.nvim_win_set_cursor(0, {last_hunk.start_line, 0})
end

-- Accept change at cursor position
function M.accept_at_cursor()
  if not M.state.target_buf or not M.state.response then
    vim.api.nvim_echo({{'No pending changes', 'WarningMsg'}}, false, {})
    return
  end

  local idx, hunk = M.get_hunk_at_cursor()
  if not hunk then
    vim.api.nvim_echo({{'No change at cursor position', 'WarningMsg'}}, false, {})
    return
  end

  -- Apply just this hunk
  local lines = vim.api.nvim_buf_get_lines(M.state.target_buf, 0, -1, false)

  if hunk.type == 'change' then
    -- Apply single change
    local new_lines = {}

    -- Lines before change
    for i = 1, hunk.start_line - 1 do
      table.insert(new_lines, lines[i])
    end

    -- New content (empty lines array or missing code means deletion)
    if hunk.change.lines and #hunk.change.lines > 0 then
      for _, line in ipairs(hunk.change.lines) do
        table.insert(new_lines, line)
      end
    elseif hunk.change.code and hunk.change.code ~= "" then
      local code_lines = vim.split(hunk.change.code, '\n', { plain = true })
      for _, line in ipairs(code_lines) do
        table.insert(new_lines, line)
      end
    end
    -- If neither lines nor code, it's a deletion - we just don't add anything

    -- Lines after change
    for i = hunk.end_line + 1, #lines do
      table.insert(new_lines, lines[i])
    end

    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, new_lines)

  elseif hunk.type == 'edit' then
    -- Apply single line edit
    if hunk.new_content == "" then
      -- Delete line
      vim.api.nvim_buf_set_lines(M.state.target_buf, hunk.start_line - 1, hunk.end_line, false, {})
    else
      -- Replace line
      vim.api.nvim_buf_set_lines(M.state.target_buf, hunk.start_line - 1, hunk.end_line, false, {hunk.new_content})
    end
  end

  -- Remove this hunk from the list
  table.remove(M.state.hunks, idx)

  -- Update diff display
  if #M.state.hunks == 0 then
    -- All hunks processed
    M.clear_diff()
    vim.api.nvim_echo({{'✓ All changes accepted', 'String'}}, false, {})
  else
    -- Recalculate diff for remaining hunks
    M.update_diff_display()
    vim.api.nvim_echo({{string.format('✓ Change accepted (%d remaining)', #M.state.hunks), 'String'}}, false, {})
  end
end

-- Reject change at cursor position
function M.reject_at_cursor()
  if not M.state.hunks or #M.state.hunks == 0 then
    vim.api.nvim_echo({{'No pending changes', 'WarningMsg'}}, false, {})
    return
  end

  local idx, hunk = M.get_hunk_at_cursor()
  if not hunk then
    vim.api.nvim_echo({{'No change at cursor position', 'WarningMsg'}}, false, {})
    return
  end

  -- Remove this hunk from the list
  table.remove(M.state.hunks, idx)

  if #M.state.hunks == 0 then
    -- All hunks processed
    M.clear_diff()
    vim.api.nvim_echo({{'✗ All changes rejected', 'String'}}, false, {})
  else
    -- Recalculate diff for remaining hunks
    M.update_diff_display()
    vim.api.nvim_echo({{string.format('✗ Change rejected (%d remaining)', #M.state.hunks), 'String'}}, false, {})
  end
end

-- Update diff display after accepting/rejecting individual hunks
function M.update_diff_display()
  if not M.state.target_buf or #M.state.hunks == 0 then
    M.clear_diff()
    return
  end

  -- Reconstruct response with remaining hunks
  local remaining_changes = {}
  local remaining_edits = {}

  for _, hunk in ipairs(M.state.hunks) do
    if hunk.type == 'change' then
      table.insert(remaining_changes, hunk.change)
    elseif hunk.type == 'edit' then
      remaining_edits[tostring(hunk.start_line)] = hunk.new_content
    end
  end

  -- Build new response
  local new_response = {}
  if #remaining_changes > 0 then
    new_response.changes = remaining_changes
  end
  if next(remaining_edits) then
    new_response.edits = remaining_edits
  end

  -- Apply changes to get new lines
  local lines = vim.api.nvim_buf_get_lines(M.state.target_buf, 0, -1, false)
  local new_lines

  if new_response.changes then
    new_lines = schema.apply_changes(lines, new_response.changes)
  elseif new_response.edits then
    new_lines = schema.apply_edits(lines, new_response.edits)
  end

  if new_lines then
    local mini_diff = require('mini.diff')
    mini_diff.set_ref_text(M.state.target_buf, table.concat(new_lines, '\n'))
  end
end

-- Clear diff display
function M.clear_diff()
  if M.state.target_buf then
    -- Clear native highlights if present
    if M.state.diff_ns_id then
      vim.api.nvim_buf_clear_namespace(M.state.target_buf, M.state.diff_ns_id, 0, -1)
      M.state.diff_ns_id = nil
    end

    -- Also try to clear mini.diff
    local ok, mini_diff = pcall(require, 'mini.diff')
    if ok then
      -- Clear the reference text to remove diff signs
      pcall(mini_diff.set_ref_text, M.state.target_buf, nil)
      pcall(mini_diff.disable, M.state.target_buf)
    end
  end

  -- Clear keymaps
  if M.state.target_buf then
    pcall(vim.keymap.del, 'n', ']]', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '[[', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', ']h', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '[h', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>tA', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>tR', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>ta', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>tr', { buffer = M.state.target_buf })
  end

  M.state = {
    target_buf = nil,
    response = nil,
    hunks = {},
    original_lines = nil
  }
end

-- Accept all changes
function M.accept()
  if not M.state.target_buf or not M.state.response then
    vim.api.nvim_echo({{'No pending changes to accept', 'WarningMsg'}}, false, {})
    return
  end

  -- Changes are already applied to the buffer, just clear the diff display
  -- No need to reapply since we applied them in show_response
  M.clear_diff()
  vim.api.nvim_echo({{"✓ Changes accepted", "String"}}, false, {})
end

-- Reject all changes
function M.reject()
  if not M.state.target_buf then
    vim.api.nvim_echo({{"No pending changes to reject", "WarningMsg"}}, false, {})
    return
  end

  -- Revert buffer to original content
  if M.state.original_lines then
    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.original_lines)
  end

  M.clear_diff()
  vim.api.nvim_echo({{"✗ Changes rejected", "WarningMsg"}}, false, {})
end

-- Native vim diff highlighting fallback
function M.show_native_diff(target_buf, original_lines, new_lines)
  -- Create a namespace for our highlights
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- Clear any existing highlights
  vim.api.nvim_buf_clear_namespace(target_buf, ns_id, 0, -1)

  -- Simple line-by-line comparison
  local max_lines = math.max(#original_lines, #new_lines)

  for i = 1, max_lines do
    if i > #original_lines then
      -- Added lines
      vim.api.nvim_buf_set_extmark(target_buf, ns_id, i - 1, 0, {
        sign_text = '+',
        sign_hl_group = 'DiffAdd',
        line_hl_group = 'DiffAdd',
        priority = 100,
      })
    elseif i > #new_lines then
      -- This shouldn't happen as we've already applied changes
      -- But mark as deleted for reference
    elseif original_lines[i] ~= new_lines[i] then
      -- Changed lines
      vim.api.nvim_buf_set_extmark(target_buf, ns_id, i - 1, 0, {
        sign_text = '~',
        sign_hl_group = 'DiffChange',
        line_hl_group = 'DiffChange',
        priority = 100,
      })
    end
  end

  -- Store the namespace for cleanup
  M.state.diff_ns_id = ns_id
end

-- Legacy compatibility
function M.show_changes(target_buf, start_line, end_line, new_code, description)
  local response = {
    changes = {{
      start_line = start_line,
      end_line = end_line,
      code = new_code,
      description = description
    }},
    explanation = description
  }
  M.show_response(target_buf, response)
end

return M