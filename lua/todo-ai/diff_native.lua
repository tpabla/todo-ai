-- Native Neovim diff display with accept/reject
local M = {}
local search_replace = require('todo-ai.search_replace')
local formatter = require('todo-ai.diff_formatter')

M.state = {
  target_buf = nil,
  response = nil,
  hunks = {},
  original_lines = nil,
  modified_lines = nil,
  ns_id = nil,
  diff_showing = false,
  accepted_diffs = {}, -- Track which diffs are accepted (by index)
  rejected_diffs = {}, -- Track which diffs are rejected (by index)
  has_padding = false, -- Track if we added padding line
  diagnostics_disabled = false, -- Track if we disabled diagnostics for this buffer
}

-- Disable diagnostics for cleaner diff view
function M.disable_diagnostics(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Use the newer API for disabling diagnostics
  -- First try the newer vim.diagnostic.enable/disable API
  local ok, _ = pcall(function()
    vim.diagnostic.enable(false, { bufnr = buf })
  end)

  if not ok then
    -- Fallback to older API if newer one doesn't exist
    pcall(vim.diagnostic.disable, buf)
  end

  M.state.diagnostics_disabled = true
end

-- Re-enable diagnostics when diff is cleared
function M.restore_diagnostics(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if M.state.diagnostics_disabled then
    -- Use the newer API for enabling diagnostics
    local ok, _ = pcall(function()
      vim.diagnostic.enable(true, { bufnr = buf })
    end)

    if not ok then
      -- Fallback to older API if newer one doesn't exist
      pcall(vim.diagnostic.enable, buf)
    end

    M.state.diagnostics_disabled = false
  end
end

-- Build visual display applying accepted changes
function M.build_search_replace_display(original_lines, changes)
  -- Use search_replace module for display building
  local display_lines = search_replace.build_display(original_lines, changes, M.state.rejected_diffs)

  -- Track regions for navigation
  local regions = search_replace.track_change_regions(original_lines, changes, M.state.rejected_diffs)

  -- Track where each change appears in the DISPLAY buffer
  -- This is simpler: since display_lines already has the replacements applied,
  -- we just need to find where each replacement text appears
  for i, change in ipairs(changes) do
    if not M.state.rejected_diffs[i] then
      -- Find the hunk that matches this change index
      for h, hunk in ipairs(M.state.hunks) do
        if hunk.change_index == i then
          -- For display positions, find where the replacement appears in display_lines
          local display_text = table.concat(display_lines, '\n')
          local replace_start = display_text:find(change.replace, 1, true)

          if replace_start then
            -- Calculate line number from character position
            local before_replace = display_text:sub(1, replace_start - 1)
            local display_line = select(2, before_replace:gsub('\n', '\n')) + 1
            local replace_lines = vim.split(change.replace, '\n', { plain = true })

            -- Set display positions
            M.state.hunks[h].display_start = display_line
            M.state.hunks[h].display_end = display_line + #replace_lines - 1
            M.state.hunks[h].search_text = change.search
            M.state.hunks[h].replace_text = change.replace
            M.state.hunks[h].description = change.description or ""
            -- todo_text is already set in the hunk from earlier

            -- Log for debugging
            local logger = require('todo-ai.logger')
            logger.info('diff_native', string.format('Hunk %d: display_start=%d, display_end=%d',
              h, M.state.hunks[h].display_start, M.state.hunks[h].display_end))
          end
          break
        end
      end
    end
  end

  return display_lines
end


-- Show SEARCH/REPLACE changes with awesome visual highlighting
function M.show_response(target_buf, response, todo_text)
  local logger = require('todo-ai.logger')
  logger.info('diff_native', 'show_response called')

  -- Validate inputs
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    logger.error('diff_native', 'Invalid buffer')
    vim.api.nvim_echo({{'Invalid buffer', 'ErrorMsg'}}, false, {})
    return
  end

  -- CRITICAL: Never modify the chat buffer
  local buf_name = vim.api.nvim_buf_get_name(target_buf)
  if buf_name:match('Todo%-AI Chat') then
    logger.error('diff_native', 'Attempted to modify chat buffer - aborting')
    vim.api.nvim_echo({{'Cannot modify chat buffer!', 'ErrorMsg'}}, false, {})
    return
  end

  M.state.target_buf = target_buf
  M.state.response = response
  M.state.hunks = {}

  -- Disable diagnostics for cleaner diff view
  M.disable_diagnostics(target_buf)

  -- Get current buffer content (original)
  local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)
  M.state.processed_todos = {} -- Reset TODO tracking

  -- Handle changes array (SEARCH/REPLACE format)
  M.state.hunks = {}
  M.state.accepted_diffs = {}
  M.state.rejected_diffs = {}

  if not response.changes then
    logger.error('diff_native', 'Response must contain "changes" array')
    vim.api.nvim_echo({{'Response must contain "changes" array', 'ErrorMsg'}}, false, {})
    return
  end

  logger.info('diff_native', string.format('Processing %d changes', #response.changes))

  -- Store each change as a hunk with its index
  for i, change in ipairs(response.changes) do
    if change.search and change.replace then
      -- Find where this change would be in the file
      local content = table.concat(lines, '\n')
      local start_pos, end_pos = content:find(change.search, 1, true)

      local start_line = 1
      local end_line = #lines

      if start_pos then
        -- Calculate line numbers for this change
        local before = content:sub(1, start_pos - 1)
        start_line = select(2, before:gsub('\n', '\n')) + 1
        local search_content = content:sub(start_pos, end_pos)
        local search_lines = select(2, search_content:gsub('\n', '\n'))
        end_line = start_line + search_lines
      end

      -- Store hunk info for individual accept/reject
      table.insert(M.state.hunks, {
        change_index = i,
        search = change.search,
        replace = change.replace,
        description = change.description or ("Change " .. i),
        todo_text = todo_text or "",  -- Store the raw TODO text
        type = 'search_replace',
        language = response.language or vim.bo[target_buf].filetype or 'text',
        start_line = start_line,
        end_line = end_line,
        found = start_pos ~= nil
      })
    end
  end

  -- Build the visual SEARCH/REPLACE display
  local display_lines = M.build_search_replace_display(lines, response.changes)

  -- Check if we need to add an empty line at the start for header placement
  local needs_padding = false
  for _, hunk in ipairs(M.state.hunks) do
    if hunk.display_start == 1 or hunk.start_line == 1 then
      needs_padding = true
      break
    end
  end

  -- Add empty line at start if needed for proper header placement
  M.state.has_padding = needs_padding
  if needs_padding then
    logger.info('diff_native', 'Adding empty line at start for header placement')
    table.insert(display_lines, 1, '')

    -- Adjust all hunk positions by 1
    for _, hunk in ipairs(M.state.hunks) do
      if hunk.display_start then
        hunk.display_start = hunk.display_start + 1
      end
      if hunk.display_end then
        hunk.display_end = hunk.display_end + 1
      end
      -- start_line and end_line remain unchanged as they refer to original positions
    end
  end

  -- Store the lines we'll apply when accepting changes
  M.state.modified_lines = M.apply_unified_changes()

  -- Create and setup the diff view (use schedule only in async contexts)
  local in_async = vim.in_fast_event and vim.in_fast_event()
  if in_async then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(target_buf) then
        M.setup_inline_diff_view(target_buf, lines, display_lines, false)

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
    end)
    return
  end

  M.setup_inline_diff_view(target_buf, lines, display_lines, false)

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
function M.setup_inline_diff_view(target_buf, original_lines, display_lines, preserve_cursor)
  -- Save cursor position if requested
  local saved_cursor = nil
  if preserve_cursor then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == target_buf then
        saved_cursor = vim.api.nvim_win_get_cursor(win)
        break
      end
    end
  end

  -- Create namespace for virtual text
  M.state.ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- Debug: log what we're about to set
  local logger = require('todo-ai.logger')
  logger.info('diff_native', string.format('Setting buffer to display content: %d lines', #display_lines))

  -- Set the target buffer to show the SEARCH/REPLACE display
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, display_lines)

  -- Mark as modified to show it's changed
  vim.bo[target_buf].modified = true

  logger.info('diff_native', string.format('Buffer showing SEARCH/REPLACE blocks'))

  -- Use formatter module for visual formatting and cursor positioning
  -- Schedule to ensure buffer is ready for extmarks
  vim.schedule(function()
    logger.info('diff_native', 'Scheduled formatting application starting')

    -- Check if namespace is still valid
    local ns_exists = pcall(vim.api.nvim_get_namespaces)
    logger.info('diff_native', string.format('Namespace check: ns_id=%d, exists=%s', M.state.ns_id, tostring(ns_exists)))

    -- Log window and buffer settings that might affect virtual text display
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == target_buf then
        local conceallevel = vim.wo[win].conceallevel
        local concealcursor = vim.wo[win].concealcursor
        local wrap = vim.wo[win].wrap
        local list = vim.wo[win].list
        logger.info('diff_native', string.format('Window settings: conceallevel=%d, concealcursor=%s, wrap=%s, list=%s',
          conceallevel, concealcursor, tostring(wrap), tostring(list)))
      end
    end

    formatter.apply_formatting(target_buf, M.state.hunks, M.state, M.state.ns_id)

    -- Log extmark count after formatting
    local all_marks = vim.api.nvim_buf_get_extmarks(target_buf, M.state.ns_id, 0, -1, {})
    logger.info('diff_native', string.format('After formatting: %d total extmarks in buffer', #all_marks))

    -- Log details about virtual text marks specifically
    for _, mark in ipairs(all_marks) do
      local details = vim.api.nvim_buf_get_extmark_by_id(target_buf, M.state.ns_id, mark[1], {details = true})
      if #details > 0 and details[3] then
        if details[3].virt_lines_above or details[3].virt_lines then
          logger.info('diff_native', string.format('Virtual text mark at line %d: virt_lines_above=%s, virt_lines=%s',
            details[1], tostring(details[3].virt_lines_above ~= nil), tostring(details[3].virt_lines ~= nil)))
        end
      end
    end

    -- Restore cursor position AFTER formatting is applied
    if saved_cursor then
      -- Restore the saved cursor position
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == target_buf then
          -- Ensure cursor position is within bounds
          local line_count = vim.api.nvim_buf_line_count(target_buf)
          local line = math.min(saved_cursor[1], line_count)
          vim.api.nvim_win_set_cursor(win, {line, saved_cursor[2]})
          break
        end
      end
    elseif #M.state.hunks > 0 and M.state.hunks[1].start_line then
      -- Only jump to first change on initial load
      local first_line = M.state.hunks[1].display_start or M.state.hunks[1].start_line
      -- Adjust for padding if needed
      if M.state.has_padding and first_line == 1 then
        first_line = 2  -- Skip the padding line
      end
      first_line = math.max(1, math.min(first_line, vim.api.nvim_buf_line_count(target_buf)))
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == target_buf then
          vim.api.nvim_win_set_cursor(win, {first_line, 0})
          break
        end
      end
    end
  end)

  M.state.diff_showing = true
end

-- Clear the inline diff display
function M.clear_inline_diff()
  local logger = require('todo-ai.logger')
  logger.info('diff_native', 'clear_inline_diff called')

  -- Clear virtual text and highlights
  if M.state.ns_id and M.state.target_buf then
    logger.info('diff_native', string.format('Clearing namespace %d for buffer %d', M.state.ns_id, M.state.target_buf))
    vim.api.nvim_buf_clear_namespace(M.state.target_buf, M.state.ns_id, 0, -1)
  end

  M.state.diff_showing = false
end

-- Build and apply unified SEARCH/REPLACE changes from accepted changes
function M.apply_unified_changes()
  if not M.state.original_lines or not M.state.response then
    return M.state.original_lines
  end

  -- Start with original content
  local result = vim.deepcopy(M.state.original_lines)

  -- Apply only accepted changes using SEARCH/REPLACE
  local changes_to_apply = {}
  for i, change in ipairs(M.state.response.changes) do
    if not M.state.rejected_diffs[i] then
      -- This change is accepted (not explicitly rejected)
      table.insert(changes_to_apply, change)
    end
  end

  -- Apply the changes
  if #changes_to_apply > 0 then
    local new_lines, applied_count, errors = search_replace.apply_changes(result, changes_to_apply)
    if errors then
      vim.api.nvim_echo({{'Warning: Some changes failed - ' .. errors, 'WarningMsg'}}, false, {})
    end
    return new_lines
  end

  return result
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

-- Navigate to next hunk (alias for goto_next_hunk)
function M.next_hunk(bufnr)
  return M.goto_next_hunk()
end

-- Navigate to previous hunk (alias for goto_prev_hunk)
function M.prev_hunk(bufnr)
  return M.goto_prev_hunk()
end

-- Accept hunk at cursor
function M.accept_hunk(bufnr)
  return M.accept_at_cursor()
end

-- Reject hunk at cursor
function M.reject_hunk(bufnr)
  return M.reject_at_cursor()
end

-- Apply all accepted changes
function M.apply_changes(bufnr)
  return M.apply_all()
end

-- Debug function to check virtual text visibility
function M.debug_headers()
  if not M.state.ns_id or not M.state.target_buf then
    print("No active diff display")
    return
  end

  local buf = M.state.target_buf
  local ns_id = M.state.ns_id

  -- Get all extmarks
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {details = true})
  local virt_count = 0
  local header_lines = {}

  for _, mark in ipairs(marks) do
    local row, col, details = mark[2], mark[3], mark[4]
    if details.virt_lines_above or details.virt_lines then
      virt_count = virt_count + 1
      table.insert(header_lines, row + 1)  -- Convert 0-based to 1-based

      -- Extract first line of virtual text for display
      local virt_text = ""
      local virt_lines = details.virt_lines or {}
      if #virt_lines > 0 then
        for _, chunk in ipairs(virt_lines[1] or {}) do
          virt_text = virt_text .. chunk[1]
        end
      end

      print(string.format("Header %d at line %d: %s", virt_count, row + 1, virt_text:sub(1, 40)))
    end
  end

  if virt_count == 0 then
    print("No virtual text headers found!")
    print(string.format("Total extmarks: %d", #marks))
  else
    print(string.format("\n%d headers found at lines: %s", virt_count, table.concat(header_lines, ", ")))
    print("\nIf you don't see these headers visually, check:")
    print("  - Terminal/font support for Unicode characters")
    print("  - Color scheme compatibility")
    print("  - Window settings (conceallevel, wrap, etc.)")
  end
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

  -- Restore diagnostics
  if M.state.target_buf then
    M.restore_diagnostics(M.state.target_buf)
  end

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
    accepted_diffs = {},
    rejected_diffs = {},
    has_padding = false,
    diagnostics_disabled = false,
  }
end

-- Accept all changes
function M.accept(todo)
  if not M.state.target_buf or not M.state.response then
    vim.api.nvim_echo({{'No pending changes to accept', 'WarningMsg'}}, false, {})
    return
  end

  local logger = require('todo-ai.logger')
  logger.info('diff_native', 'Accept all called')

  -- Mark all changes as accepted (clear rejected list)
  M.state.rejected_diffs = {}

  -- Apply the SEARCH/REPLACE changes
  local final_lines = M.apply_unified_changes()

  -- Set the buffer to the final result
  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, final_lines)

  logger.info('diff_native', string.format('Applied SEARCH/REPLACE changes: %d lines', #final_lines))

  -- Check if this was a full replacement
  local is_full_replacement = M.state.response and M.state.response.replace_buffer
  logger.info('diff_native', string.format('Is full replacement: %s', tostring(is_full_replacement)))

  -- Remove entire TODO lines for processed TODOs (only for partial changes)
  if not is_full_replacement and next(M.state.processed_todos) then
    logger.info('diff_native', 'Processing TODO cleanup')
    local final_lines = vim.api.nvim_buf_get_lines(M.state.target_buf, 0, -1, false)
    logger.info('diff_native', string.format('Lines before TODO cleanup: %d', #final_lines))
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

  -- Restore original buffer content (including TODO)
  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.original_lines)

  M.clear_diff()
  vim.api.nvim_echo({{"✗ Changes rejected - TODO preserved", "WarningMsg"}}, false, {})
end

-- Accept change at cursor
function M.accept_at_cursor()
  if not M.state.target_buf or not M.state.hunks then
    vim.api.nvim_echo({{'No pending changes', 'WarningMsg'}}, false, {})
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local found_diff = nil
  local found_hunk = nil

  -- Find which change this cursor position belongs to based on line ranges
  for _, hunk in ipairs(M.state.hunks) do
    -- Check if cursor is within this hunk's line range
    if cursor_line >= hunk.start_line and cursor_line <= hunk.end_line then
      if not M.state.rejected_diffs[hunk.change_index] then
        found_diff = hunk.change_index
        found_hunk = hunk
        break
      end
    end
  end

  -- If not found by position, find the nearest non-rejected change
  if not found_diff then
    local min_dist = math.huge
    for _, hunk in ipairs(M.state.hunks) do
      if not M.state.rejected_diffs[hunk.change_index] then
        local dist = math.min(
          math.abs(cursor_line - hunk.start_line),
          math.abs(cursor_line - hunk.end_line)
        )
        if dist < min_dist then
          min_dist = dist
          found_diff = hunk.change_index
          found_hunk = hunk
        end
      end
    end
  end

  if not found_diff then
    vim.api.nvim_echo({{'No pending changes to accept', 'WarningMsg'}}, false, {})
    return
  end

  -- Mark as accepted by removing from rejected list
  M.state.rejected_diffs[found_diff] = nil
  -- Also explicitly track as accepted
  M.state.accepted_diffs[found_diff] = true

  -- Count remaining non-rejected changes and check if all are decided
  local active_count = 0
  local undecided_count = 0
  for i = 1, #M.state.response.changes do
    if not M.state.rejected_diffs[i] then
      active_count = active_count + 1
    end
    if not M.state.accepted_diffs[i] and not M.state.rejected_diffs[i] then
      undecided_count = undecided_count + 1
    end
  end

  -- Check if all changes have been explicitly decided (either accepted or rejected)
  local all_decided = true
  for i = 1, #M.state.response.changes do
    if not M.state.accepted_diffs[i] and not M.state.rejected_diffs[i] then
      all_decided = false
      break
    end
  end

  if all_decided and active_count > 0 then
    -- All diffs decided and at least one accepted - apply the unified diff
    local final_lines = M.apply_unified_changes()
    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, final_lines)
    M.clear_diff()
    vim.api.nvim_echo({{
      string.format('✓ All changes decided - %d changes applied', active_count), 'String'
    }}, false, {})
  else
    -- Still have undecided changes or need to rebuild
    local pending_count = 0
    for i = 1, #M.state.response.changes do
      if not M.state.accepted_diffs[i] and not M.state.rejected_diffs[i] then
        pending_count = pending_count + 1
      end
    end

    vim.api.nvim_echo({{
      string.format('✓ Accepted: %s (%d pending, %d to apply)',
        found_hunk.description, pending_count, active_count), 'String'
    }}, false, {})

    -- Rebuild the display to show updated status
    M.update_diff_display()
  end
end

-- Reject change at cursor
function M.reject_at_cursor()
  if not M.state.hunks or #M.state.hunks == 0 then
    vim.api.nvim_echo({{'No pending changes', 'WarningMsg'}}, false, {})
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local found_diff = nil
  local found_hunk = nil

  -- Find which change this cursor position belongs to based on line ranges
  for _, hunk in ipairs(M.state.hunks) do
    -- Check if cursor is within this hunk's line range
    if cursor_line >= hunk.start_line and cursor_line <= hunk.end_line then
      if not M.state.rejected_diffs[hunk.change_index] then
        found_diff = hunk.change_index
        found_hunk = hunk
        break
      end
    end
  end

  -- If not found by position, find the nearest non-rejected change
  if not found_diff then
    local min_dist = math.huge
    for _, hunk in ipairs(M.state.hunks) do
      if not M.state.rejected_diffs[hunk.change_index] then
        local dist = math.min(
          math.abs(cursor_line - hunk.start_line),
          math.abs(cursor_line - hunk.end_line)
        )
        if dist < min_dist then
          min_dist = dist
          found_diff = hunk.change_index
          found_hunk = hunk
        end
      end
    end
  end

  if not found_diff then
    vim.api.nvim_echo({{'No pending changes to reject', 'WarningMsg'}}, false, {})
    return
  end

  -- Mark this diff as rejected
  M.state.rejected_diffs[found_diff] = true
  -- Remove from accepted if it was there
  M.state.accepted_diffs[found_diff] = nil

  -- Count remaining active changes and undecided
  local active_count = 0
  local undecided_count = 0
  for i = 1, #M.state.response.changes do
    if not M.state.rejected_diffs[i] then
      active_count = active_count + 1
    end
    if not M.state.accepted_diffs[i] and not M.state.rejected_diffs[i] then
      undecided_count = undecided_count + 1
    end
  end

  -- Check if all diffs have been explicitly decided
  local all_decided = true
  for i = 1, #M.state.response.changes do
    if not M.state.accepted_diffs[i] and not M.state.rejected_diffs[i] then
      all_decided = false
      break
    end
  end

  if active_count == 0 then
    -- All changes rejected - restore original
    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.original_lines)
    M.clear_diff()
    vim.api.nvim_echo({{'✗ All changes rejected - TODO preserved', 'String'}}, false, {})
  elseif all_decided and active_count > 0 then
    -- All diffs decided with some accepted - apply the unified diff
    local final_lines = M.apply_unified_changes()
    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, final_lines)
    M.clear_diff()
    vim.api.nvim_echo({{
      string.format('✓ All changes decided - %d changes applied', active_count), 'String'
    }}, false, {})
  else
    -- Still have undecided diffs
    local pending_count = 0
    for i = 1, #M.state.response.changes do
      if not M.state.accepted_diffs[i] and not M.state.rejected_diffs[i] then
        pending_count = pending_count + 1
      end
    end

    vim.api.nvim_echo({{
      string.format('✗ Rejected: %s (%d pending, %d to apply)',
        found_hunk.description, pending_count, active_count), 'String'
    }}, false, {})

    -- Rebuild the display
    M.update_diff_display()
  end
end

-- Update diff display after accepting/rejecting individual hunks
function M.update_diff_display()
  if not M.state.target_buf then
    M.clear_diff()
    return
  end

  -- Build the unified diff from accepted changes
  local new_lines = M.apply_unified_changes()

  -- Check if anything is left
  local has_accepted = false
  for i = 1, #M.state.response.changes do
    if not M.state.rejected_diffs[i] then
      has_accepted = true
      break
    end
  end

  if not has_accepted then
    -- All rejected, restore original
    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.original_lines)
    M.clear_diff()
    return
  end

  -- Refresh the display with the new unified result
  M.clear_inline_diff()
  M.setup_inline_diff_view(M.state.target_buf, M.state.original_lines, new_lines, true)
end

return M