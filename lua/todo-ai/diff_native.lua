-- Native Neovim diff display with accept/reject
local M = {}
local schema = require('todo-ai.schema')

M.state = {
  target_buf = nil,
  response = nil,
  hunks = {},
  original_lines = nil,
  modified_lines = nil,
  processed_todos = {}, -- Track TODO texts that were processed (as a set)
  ns_id = nil,
  diff_showing = false,
}

-- Show changes using Neovim's native diff functionality
function M.show_response(target_buf, response)
  M.state.target_buf = target_buf
  M.state.response = response
  M.state.hunks = {}

  -- Get current buffer content (original)
  local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)
  M.state.processed_todos = {} -- Reset TODO tracking

  -- Calculate what the buffer would look like after changes
  local new_lines
  if response.changes then
    new_lines = schema.apply_changes(lines, response.changes)
    -- Store hunks for individual operations
    for _, change in ipairs(response.changes) do
      -- Track the TODO text if provided
      if change.todo_text then
        M.state.processed_todos[change.todo_text] = true
      end

      table.insert(M.state.hunks, {
        start_line = change.start_line,
        end_line = change.end_line,
        change = change,
        type = 'change',
        todo_text = change.todo_text
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

  M.state.modified_lines = new_lines

  -- Create and setup the diff view
  M.setup_inline_diff_view(target_buf, lines, new_lines)

  -- Show notification
  local num_changes = #M.state.hunks
  vim.api.nvim_echo({
    {"📝 ", "Special"},
    {string.format("%d changes ready. ", num_changes), "Normal"},
    {"<leader>tA", "Special"},
    {" accept all, ", "Normal"},
    {"<leader>tR", "Special"},
    {" reject all", "Normal"}
  }, false, {})

  -- Setup buffer-local keymaps
  M.setup_keymaps(target_buf)
end

-- Setup inline diff view showing changes in the original buffer
function M.setup_inline_diff_view(target_buf, original_lines, new_lines)
  -- Create namespace for virtual text
  M.state.ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- Store the modified lines for accept operation
  M.state.modified_lines = new_lines

  -- Set the target buffer to show the new content temporarily
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, new_lines)

  -- Mark the buffer as modified to show diff highlights
  vim.bo[target_buf].modified = true

  -- Display each hunk with virtual text showing the changes
  for idx, hunk in ipairs(M.state.hunks) do
    -- Calculate actual positions in the new buffer
    local new_start = hunk.start_line - 1
    local new_end = new_start

    if hunk.change then
      if hunk.change.lines then
        new_end = new_start + #hunk.change.lines - 1
      elseif hunk.change.code then
        local lines = vim.split(hunk.change.code, '\n', { plain = true })
        new_end = new_start + #lines - 1
      end
    end

    -- Highlight the changed lines with diff colors
    for line_idx = new_start, new_end do
      local line = vim.api.nvim_buf_get_lines(target_buf, line_idx, line_idx + 1, false)[1] or ""
      vim.api.nvim_buf_set_extmark(target_buf, M.state.ns_id, line_idx, 0, {
        end_row = line_idx + 1,
        end_col = 0,
        hl_group = "DiffAdd",
        hl_eol = true,
        priority = 10
      })
    end

    -- Single-line colorful header with cyberpunk aesthetic
    local header_parts = {
      {string.rep("━", 8), "DiagnosticVirtualText"},  -- Bright solid line start
      {" [", "Normal"},
      {"ta", "String"},  -- Neon green
      {"]", "Normal"},
      {" accept ", "Comment"},
      {"[", "Normal"},
      {"tr", "ErrorMsg"},  -- Neon red
      {"]", "Normal"},
      {" reject ", "Comment"},
    }

    if hunk.todo_text then
      table.insert(header_parts, {" • ", "Comment"})
      table.insert(header_parts, {"TODO: " .. hunk.todo_text, "Todo"})
    end

    table.insert(header_parts, {" ", "Normal"})
    -- Fill rest of line with bright separator
    table.insert(header_parts, {string.rep("━", 50), "DiagnosticVirtualText"})

    -- Add header before the change
    vim.api.nvim_buf_set_extmark(target_buf, M.state.ns_id, new_start, 0, {
      virt_lines_above = true,
      virt_lines = { header_parts }
    })

    -- Show what was removed as virtual text
    local removed_lines = {}
    for i = hunk.start_line, hunk.end_line do
      if i <= #original_lines then
        table.insert(removed_lines, {
          {original_lines[i], "DiffDelete"}
        })
      end
    end

    -- Add removed lines as virtual text if they differ from new content
    if #removed_lines > 0 then
      vim.api.nvim_buf_set_extmark(target_buf, M.state.ns_id, new_start, 0, {
        virt_lines_above = true,
        virt_lines = removed_lines,
        priority = 5
      })
    end

    -- Footer with description if available (matching cyberpunk aesthetic)
    if hunk.change and hunk.change.description then
      local footer_lines = {}
      local desc_lines = vim.split(hunk.change.description, '\n', { plain = true })

      for _, desc_line in ipairs(desc_lines) do
        table.insert(footer_lines, {
          {"  ▎ ", "DiagnosticVirtualText"},  -- Neon bar
          {desc_line, "Comment"}
        })
      end

      -- Add closing bar matching header aesthetic
      table.insert(footer_lines, {
        {string.rep("━", 60), "DiagnosticVirtualText"}  -- Bright solid line
      })

      -- Add footer after the changes
      vim.api.nvim_buf_set_extmark(target_buf, M.state.ns_id, hunk.end_line - 1, 0, {
        virt_lines = footer_lines,
        virt_lines_above = false
      })
    end
  end

  -- Jump to first change
  if #M.state.hunks > 0 then
    vim.api.nvim_win_set_cursor(0, {M.state.hunks[1].start_line, 0})
  end

  M.state.diff_showing = true
end

-- Clear the inline diff display
function M.clear_inline_diff()
  -- Clear virtual text
  if M.state.ns_id and M.state.target_buf then
    vim.api.nvim_buf_clear_namespace(M.state.target_buf, M.state.ns_id, 0, -1)
  end

  M.state.diff_showing = false
end

-- Setup keymaps for the buffer
function M.setup_keymaps(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Navigation between hunks
  vim.keymap.set('n', ']]', function() M.goto_next_hunk() end,
    vim.tbl_extend('force', opts, { desc = 'Go to next change' }))
  vim.keymap.set('n', '[[', function() M.goto_prev_hunk() end,
    vim.tbl_extend('force', opts, { desc = 'Go to previous change' }))

  -- Accept/Reject all changes
  vim.keymap.set('n', '<leader>tA', function() M.accept() end,
    vim.tbl_extend('force', opts, { desc = 'Accept ALL changes' }))
  vim.keymap.set('n', '<leader>tR', function() M.reject() end,
    vim.tbl_extend('force', opts, { desc = 'Reject ALL changes' }))

  -- Per-hunk operations
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

  -- Find nearest
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
  local next_hunk_idx = nil

  for idx, hunk in ipairs(M.state.hunks) do
    if hunk.start_line > cursor_line then
      vim.api.nvim_win_set_cursor(0, {hunk.start_line, 0})
      next_hunk_idx = idx
      break
    end
  end

  -- Wrap to first
  if not next_hunk_idx then
    vim.api.nvim_win_set_cursor(0, {M.state.hunks[1].start_line, 0})
    next_hunk_idx = 1
  end
end

-- Navigate to previous hunk
function M.goto_prev_hunk()
  if not M.state.hunks or #M.state.hunks == 0 then
    vim.api.nvim_echo({{'No changes to navigate', 'WarningMsg'}}, false, {})
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local prev_hunk_idx = nil

  for i = #M.state.hunks, 1, -1 do
    local hunk = M.state.hunks[i]
    if hunk.end_line < cursor_line then
      vim.api.nvim_win_set_cursor(0, {hunk.start_line, 0})
      prev_hunk_idx = i
      break
    end
  end

  -- Wrap to last
  if not prev_hunk_idx then
    local last_hunk = M.state.hunks[#M.state.hunks]
    vim.api.nvim_win_set_cursor(0, {last_hunk.start_line, 0})
    prev_hunk_idx = #M.state.hunks
  end
end

-- Clear diff display
function M.clear_diff()
  -- Clear inline diff
  M.clear_inline_diff()

  -- Clear keymaps
  if M.state.target_buf then
    pcall(vim.keymap.del, 'n', ']]', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '[[', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>tA', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>tR', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>ta', { buffer = M.state.target_buf })
    pcall(vim.keymap.del, 'n', '<leader>tr', { buffer = M.state.target_buf })
  end

  M.state = {
    target_buf = nil,
    response = nil,
    hunks = {},
    original_lines = nil,
    modified_lines = nil,
    processed_todos = {},
    ns_id = nil,
    diff_showing = false,
  }
end

-- Accept all changes
function M.accept(todo)
  if not M.state.target_buf or not M.state.modified_lines then
    vim.api.nvim_echo({{'No pending changes to accept', 'WarningMsg'}}, false, {})
    return
  end

  -- Apply the modified lines to the buffer
  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.modified_lines)

  -- Remove entire TODO lines for processed TODOs
  if next(M.state.processed_todos) then
    local final_lines = vim.api.nvim_buf_get_lines(M.state.target_buf, 0, -1, false)
    local lines_to_remove = {}

    -- Detect comment string for the file type
    local comment_string = vim.bo[M.state.target_buf].commentstring or '// %s'
    local comment_start = comment_string:match('^(.-)%s*%%s') or '//'
    comment_start = comment_start:gsub('%s+$', '')  -- Trim trailing spaces

    -- For each processed TODO, find and mark lines for removal
    for todo_text, _ in pairs(M.state.processed_todos) do
      -- Find lines that contain this TODO
      for i = 1, #final_lines do
        local line = final_lines[i]

        -- Check if this line contains the TODO with @ai marker and matches our text
        if line:match("@ai%s+") then
          local instruction = line:match("@ai%s+(.+)$")
          if instruction then
            instruction = instruction:gsub('^%s+', ''):gsub('%s+$', '')

            -- Check if this TODO text matches what we processed
            if instruction == todo_text or todo_text:find("^" .. vim.pesc(instruction)) then
              -- Mark this entire line for removal
              lines_to_remove[i] = true

              -- Also check for multi-line continuation
              local indent = line:match('^(%s*)')
              local j = i + 1

              -- Look for continuation lines with same indent
              while j <= #final_lines do
                local next_line = final_lines[j]
                local next_indent = next_line:match('^(%s*)')

                -- If same indent and is a comment line (but not a new TODO)
                if next_indent == indent and next_line:match('^%s*' .. vim.pesc(comment_start)) then
                  if not next_line:match('TODO') and not next_line:match('@ai') then
                    lines_to_remove[j] = true
                    j = j + 1
                  else
                    break  -- Found another TODO or @ai marker
                  end
                else
                  break  -- Different indentation or not a comment
                end
              end

              break  -- Found and marked this TODO
            end
          end
        end
      end
    end

    -- Build new buffer without removed lines
    if next(lines_to_remove) then
      local new_lines = {}
      for i, line in ipairs(final_lines) do
        if not lines_to_remove[i] then
          table.insert(new_lines, line)
        end
      end
      vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, new_lines)
    end
  end

  M.clear_diff()
  vim.api.nvim_echo({{"✓ Changes accepted", "String"}}, false, {})
end

-- Reject all changes
function M.reject()
  if not M.state.target_buf or not M.state.original_lines then
    vim.api.nvim_echo({{"No pending changes to reject", "WarningMsg"}}, false, {})
    return
  end

  -- Restore original buffer content
  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.original_lines)

  M.clear_diff()
  vim.api.nvim_echo({{"✗ Changes rejected", "WarningMsg"}}, false, {})
end

-- Accept change at cursor
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
    local new_lines = {}
    -- Lines before change
    for i = 1, hunk.start_line - 1 do
      table.insert(new_lines, lines[i])
    end

    -- New content
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

  -- Remove this hunk
  table.remove(M.state.hunks, idx)

  if #M.state.hunks == 0 then
    -- All hunks processed - remove @ai markers for processed TODOs
    if next(M.state.processed_todos) then
      local final_lines = vim.api.nvim_buf_get_lines(M.state.target_buf, 0, -1, false)
      local modified = false

      for i, line in ipairs(final_lines) do
        -- Check if this line contains any of our processed TODOs
        for todo_text, _ in pairs(M.state.processed_todos) do
          -- Look for this TODO text with @ai marker
          if line:match("@ai%s+" .. vim.pesc(todo_text)) then
            -- Remove just the @ai marker, keeping the rest of the comment
            final_lines[i] = line:gsub("@ai%s+", "")
            modified = true
            break
          end
        end
      end

      if modified then
        vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, final_lines)
      end
    end

    M.clear_diff()
    vim.api.nvim_echo({{'✓ All changes accepted', 'String'}}, false, {})
  else
    -- Refresh diff display
    M.update_diff_display()
    vim.api.nvim_echo({{string.format('✓ Change accepted (%d remaining)', #M.state.hunks), 'String'}}, false, {})
  end
end

-- Reject change at cursor
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

  -- Remove this hunk
  table.remove(M.state.hunks, idx)

  if #M.state.hunks == 0 then
    M.clear_diff()
    vim.api.nvim_echo({{'✗ All changes rejected', 'String'}}, false, {})
  else
    -- Update modified lines without this hunk
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

  -- Recalculate modified lines with remaining hunks
  local remaining_changes = {}
  local remaining_edits = {}

  for _, hunk in ipairs(M.state.hunks) do
    if hunk.type == 'change' then
      table.insert(remaining_changes, hunk.change)
    elseif hunk.type == 'edit' then
      remaining_edits[tostring(hunk.start_line)] = hunk.new_content
    end
  end

  -- Apply remaining changes
  local lines = vim.api.nvim_buf_get_lines(M.state.target_buf, 0, -1, false)
  local new_lines

  if #remaining_changes > 0 then
    new_lines = schema.apply_changes(lines, remaining_changes)
  elseif next(remaining_edits) then
    new_lines = schema.apply_edits(lines, remaining_edits)
  else
    new_lines = lines
  end

  M.state.modified_lines = new_lines

  -- Refresh the diff view
  M.setup_inline_diff_view(M.state.target_buf, lines, new_lines)
end

-- Legacy compatibility (redirect to new module)
M.show_changes = M.show_response

return M