-- Simplified diff display for SEARCH/REPLACE style changes with visual formatting
local M = {}
local search_replace = require('todo-ai.search_replace')

M.state = {
  target_buf = nil,
  response = nil,
  original_lines = nil,
  ns_id = nil,
  showing = false,
  accepted = {}, -- Set of accepted change indices
  rejected = {}, -- Set of rejected change indices
  diagnostics_disabled = false,
  has_padding = false, -- Track if we added padding for row 0 workaround
  change_locations = {}, -- Track where each change appears in the buffer
  new_files = {}, -- Track new files to be created
}

-- Visual formatting configuration
local visual_config = {
  indicators = {
    pending = "🤔 PENDING",
    accepted = "✅ ACCEPTED",
    rejected = "🔥 REJECTED"
  },
  colors = {
    pending = "DiagnosticWarn",
    accepted = "DiagnosticOk",
    rejected = "DiagnosticError",
    separator = "Special",
    add = "DiffAdd",
    delete = "DiffDelete",
    comment = "Keyword",
    description = "Title"
  },
  separator_width = 80
}

-- Create header for a change
local function create_header(change, status)
  local indicator = visual_config.indicators[status]
  local color = visual_config.colors[status]
  local line_width = visual_config.separator_width
  local header_lines = {}

  -- Status line with controls
  local status_text = string.format("%s | <leader>ta ✅ Accept | <leader>tr 🔥 Reject",
    indicator)
  local padding = math.max(3, (line_width - vim.fn.strdisplaywidth(status_text)) / 2)

  table.insert(header_lines, {
    {string.rep("─", padding), visual_config.colors.separator},
    {" " .. status_text .. " ", color},
    {string.rep("─", padding), visual_config.colors.separator},
  })

  -- Description line
  if change.description then
    local desc_text = " " .. change.description .. " "
    local desc_padding = math.max(3, (line_width - vim.fn.strdisplaywidth(desc_text)) / 2)
    table.insert(header_lines, {
      {string.rep("━", desc_padding), visual_config.colors.separator},
      {desc_text, visual_config.colors.description},
      {string.rep("━", desc_padding), visual_config.colors.separator},
    })
  end

  -- Final separator
  table.insert(header_lines, {{string.rep("━", line_width), visual_config.colors.separator}})

  return header_lines
end

-- Create footer
local function create_footer()
  return {{{string.rep("━", visual_config.separator_width), visual_config.colors.separator}}}
end

-- Show removed lines as virtual text
local function create_removed_display(search_text)
  local removed_lines = {}
  for _, line in ipairs(vim.split(search_text, '\n', { plain = true })) do
    table.insert(removed_lines, {
      {"- ", visual_config.colors.delete},
      {line, visual_config.colors.delete}
    })
  end
  return removed_lines
end

-- Disable diagnostics for cleaner view
local function disable_diagnostics(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  pcall(function()
    vim.diagnostic.enable(false, { bufnr = buf })
  end)
  M.state.diagnostics_disabled = true
end

-- Re-enable diagnostics
local function restore_diagnostics(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if M.state.diagnostics_disabled then
    pcall(function()
      vim.diagnostic.enable(true, { bufnr = buf })
    end)
    M.state.diagnostics_disabled = false
  end
end

-- Find which change the cursor is on
local function get_change_at_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Adjust for padding
  if M.state.has_padding then
    cursor_line = cursor_line - 1
  end

  -- Find which change contains this line
  for idx, loc in pairs(M.state.change_locations) do
    if cursor_line >= loc.start_line and cursor_line <= loc.end_line then
      return idx
    end
  end

  -- If not directly on a change, find the nearest one
  local nearest_idx = nil
  local nearest_distance = math.huge

  for idx, loc in pairs(M.state.change_locations) do
    local distance = math.min(
      math.abs(cursor_line - loc.start_line),
      math.abs(cursor_line - loc.end_line)
    )
    if distance < nearest_distance then
      nearest_distance = distance
      nearest_idx = idx
    end
  end

  return nearest_idx
end

-- Jump to a specific change
local function jump_to_change(idx)
  if not M.state.change_locations[idx] then
    return false
  end

  local line = M.state.change_locations[idx].start_line
  if M.state.has_padding then
    line = line + 1
  end

  -- Validate line is within buffer bounds
  local buf = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line < 1 or line > line_count then
    vim.notify(string.format("Cannot jump to line %d (buffer has %d lines)", line, line_count), vim.log.levels.WARN)
    return false
  end

  local ok, err = pcall(vim.api.nvim_win_set_cursor, 0, {line, 0})
  if not ok then
    vim.notify(string.format("Failed to set cursor position: %s", err), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Find next pending change
local function find_next_pending(current_idx)
  if not M.state.response or not M.state.response.changes then
    return nil
  end

  -- Look forward from current position
  for i = current_idx + 1, #M.state.response.changes do
    if not M.state.accepted[i] and not M.state.rejected[i] then
      return i
    end
  end

  -- Wrap around to beginning
  for i = 1, math.min(current_idx - 1, #M.state.response.changes) do
    if not M.state.accepted[i] and not M.state.rejected[i] then
      return i
    end
  end

  return nil
end

-- Show SEARCH/REPLACE changes
function M.show(target_buf, response)
  local logger = require('todo-ai.logger')
  logger.debug('diff.show called with target_buf: ' .. tostring(target_buf))
  logger.debug('diff.show response.filename: ' .. tostring(response.filename))
  logger.debug('diff.show response.new_file: ' .. tostring(response.new_file))

  -- Never modify chat buffer
  local buf_name = vim.api.nvim_buf_get_name(target_buf)
  logger.debug('diff.show buffer name: ' .. buf_name)

  if buf_name:match('Todo%-AI Chat') then
    vim.api.nvim_echo({{'Cannot modify chat buffer!', 'ErrorMsg'}}, false, {})
    return
  end

  -- Find or create a window for the target buffer (not the chat window!)
  local current_win = vim.api.nvim_get_current_win()
  local current_buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(current_win))

  if current_buf_name:match('Todo%-AI Chat') then
    -- We're in chat window - need to find/create another window
    logger.debug('In chat window, finding code window')

    -- Try to find an existing non-chat window
    local found_window = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      local win_buf_name = vim.api.nvim_buf_get_name(win_buf)
      if not win_buf_name:match('Todo%-AI Chat') then
        found_window = win
        break
      end
    end

    if found_window then
      -- Use existing window
      vim.api.nvim_set_current_win(found_window)
      vim.api.nvim_win_set_buf(found_window, target_buf)
    else
      -- Create new window (split)
      vim.cmd('vsplit')
      vim.api.nvim_set_current_buf(target_buf)
    end
  else
    -- Not in chat window, safe to switch buffer
    vim.api.nvim_set_current_buf(target_buf)
  end

  logger.debug('Switched to buffer: ' .. tostring(target_buf))

  -- Check if this is a new file creation (empty search means new file)
  if response.new_file then
    -- Store that this is a new file
    M.state.new_files[response.filename or buf_name] = true

    vim.api.nvim_echo({{'📝 New file: ' .. (response.filename or 'untitled') .. ' - Review changes and :w to save', 'WarningMsg'}}, false, {})
  end

  M.state.target_buf = target_buf
  M.state.response = response
  M.state.original_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
  M.state.accepted = {}
  M.state.rejected = {}
  M.state.change_locations = {}

  -- Create namespace for highlights
  M.state.ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- Switch to the target buffer if not already visible
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= target_buf then
    -- Find if buffer is in any window
    local buf_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == target_buf then
        buf_win = win
        break
      end
    end

    if buf_win then
      -- Buffer is visible in a window, switch to it
      vim.api.nvim_set_current_win(buf_win)
    else
      -- Buffer not visible, switch current window to show it
      vim.api.nvim_set_current_buf(target_buf)
    end
  end

  -- Disable diagnostics
  disable_diagnostics(target_buf)

  -- Check if we need padding for row 0 display issue
  M.state.has_padding = false
  if #response.changes > 0 then
    local needs_padding = false

    if response.new_file then
      -- New files always start at line 0, so always need padding
      needs_padding = true
    else
      -- Check if first change starts at line 1
      local first_change = response.changes[1]
      local content = table.concat(M.state.original_lines, '\n')
      local pos = content:find(first_change.search, 1, true)
      needs_padding = pos and pos == 1
    end

    if needs_padding then
      -- Add padding line as workaround for Neovim's row 0 display issue
      table.insert(M.state.original_lines, 1, "")
      vim.api.nvim_buf_set_lines(target_buf, 0, 0, false, {""})
      M.state.has_padding = true
    end
  end

  -- Show the preview
  M.refresh_display()

  -- Setup keymaps
  M.setup_keymaps(target_buf)

  -- Populate quickfix list with changes
  M.populate_quickfix()

  -- Show help message
  vim.api.nvim_echo({
    {"📝 ", "Special"},
    {string.format("%d changes ready. ", #response.changes), "Normal"},
    {"<leader>ta", "Special"},
    {" accept, ", "Normal"},
    {"<leader>tr", "Special"},
    {" reject, ", "Normal"},
    {":cnext/:cprev", "Special"},
    {" navigate", "Normal"}
  }, false, {})

  M.state.showing = true
end

-- Populate quickfix list with change locations
function M.populate_quickfix()
  if not M.state.target_buf or not M.state.response then
    return
  end

  local qf_list = {}
  local buf_name = vim.api.nvim_buf_get_name(M.state.target_buf)

  for i, change in ipairs(M.state.response.changes) do
    local location = M.state.change_locations[i]
    if location then
      local status = M.state.accepted[i] and "✅ ACCEPTED" or
                     M.state.rejected[i] and "🔥 REJECTED" or
                     "🤔 PENDING"

      local text = string.format("[%d/%d] %s: %s",
        i, #M.state.response.changes,
        status,
        change.description or "Change")

      table.insert(qf_list, {
        bufnr = M.state.target_buf,
        filename = buf_name,
        lnum = location.start_line + 1, -- Convert to 1-based
        col = 1,
        text = text,
        type = M.state.accepted[i] and "I" or M.state.rejected[i] and "E" or "W"
      })
    end
  end

  vim.fn.setqflist(qf_list, 'r')

  -- Switch to target buffer before opening quickfix to avoid chat window
  local current_win = vim.api.nvim_get_current_win()
  local current_buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(current_win))

  if current_buf_name:match('Todo%-AI Chat') then
    -- Find a non-chat window to open quickfix in
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      local win_buf_name = vim.api.nvim_buf_get_name(win_buf)
      if not win_buf_name:match('Todo%-AI Chat') then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end

  vim.cmd('copen')
end

-- Refresh the display based on current accepted/rejected state
function M.refresh_display()
  if not M.state.target_buf or not vim.api.nvim_buf_is_valid(M.state.target_buf) then
    return
  end

  -- Clear existing marks and locations
  vim.api.nvim_buf_clear_namespace(M.state.target_buf, M.state.ns_id, 0, -1)
  M.state.change_locations = {}

  -- Build list of changes to apply
  local changes_to_apply = {}
  for i, change in ipairs(M.state.response.changes) do
    if not M.state.rejected[i] then
      table.insert(changes_to_apply, change)
    end
  end

  -- Apply accepted changes
  local new_lines = vim.deepcopy(M.state.original_lines)
  if #changes_to_apply > 0 then
    if M.state.response.new_file then
      -- For new files, the replace content IS the entire file
      new_lines = vim.split(changes_to_apply[1].replace, '\n')
    else
      new_lines = search_replace.apply_changes(new_lines, changes_to_apply)
    end
  end

  -- Update buffer with new content
  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, new_lines)

  -- Add visual indicators for each change
  for i, change in ipairs(M.state.response.changes) do
    local status = "pending"
    if M.state.accepted[i] then
      status = "accepted"
    elseif M.state.rejected[i] then
      status = "rejected"
    end

    if not M.state.rejected[i] then
      local line_num, replace_lines

      if M.state.response.new_file then
        -- For new files, the entire content is the replacement
        line_num = 0
        replace_lines = vim.split(change.replace, '\n', { plain = true })
      else
        -- Find where this replacement text appears
        local content = table.concat(new_lines, '\n')
        local pos = content:find(change.replace, 1, true)
        if not pos then
          goto continue_change  -- Skip if we can't find the replacement
        end
        -- Calculate line number
        local before = content:sub(1, pos - 1)
        line_num = select(2, before:gsub('\n', '\n'))
        replace_lines = vim.split(change.replace, '\n', { plain = true })
      end

      -- Store location for cursor-based operations (before padding adjustment)
      M.state.change_locations[i] = {
        start_line = line_num,
        end_line = line_num + #replace_lines - 1
      }

      -- Adjust for padding if present
      if M.state.has_padding then
        line_num = line_num + 1
      end

      -- Add header with removed lines
      local header_lines = create_header(change, status)
      local removed_lines = {}
      if change.search and change.search ~= "" then
        removed_lines = create_removed_display(change.search)
      end

      -- Combine header and removed display
      local virt_lines = {}
      for _, line in ipairs(header_lines) do
        table.insert(virt_lines, line)
      end
      for _, line in ipairs(removed_lines) do
        table.insert(virt_lines, line)
      end

      -- Place header above the change
      -- For new files with padding: line 0 is padding, line 1+ is content
      -- We want header to appear at the top, so use line 0 with virt_lines_above = false
      local header_line
      if M.state.response.new_file then
        -- Place header AT the padding line (line 0), not above it
        header_line = 0
        vim.api.nvim_buf_set_extmark(M.state.target_buf, M.state.ns_id, header_line, 0, {
          virt_lines = virt_lines,
          virt_lines_above = false,  -- Place AT line 0, not above it
          priority = 100
        })
      else
        header_line = math.max(1, line_num)
        vim.api.nvim_buf_set_extmark(M.state.target_buf, M.state.ns_id, header_line, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
          priority = 100
        })
      end

      -- Highlight replacement lines based on status
      local highlight_group = status == "accepted" and 'DiffAdd' or 'DiffText'
      for j = 0, #replace_lines - 1 do
        if line_num + j < vim.api.nvim_buf_line_count(M.state.target_buf) then
          vim.api.nvim_buf_add_highlight(M.state.target_buf, M.state.ns_id,
            highlight_group, line_num + j, 0, -1)

          -- Add + sign in gutter
          vim.api.nvim_buf_set_extmark(M.state.target_buf, M.state.ns_id, line_num + j, 0, {
            sign_text = "+",
            sign_hl_group = visual_config.colors.add,
          })
        end
      end

      -- Add footer after the change
      local footer_line = math.min(line_num + #replace_lines - 1,
        vim.api.nvim_buf_line_count(M.state.target_buf) - 1)
      vim.api.nvim_buf_set_extmark(M.state.target_buf, M.state.ns_id, footer_line, 0, {
        virt_lines = create_footer(),
        virt_lines_above = false,
        priority = 100
      })
    end

    ::continue_change::
  end

  -- Check if all changes have been decided
  local all_decided = true
  local has_accepted = false
  for i = 1, #M.state.response.changes do
    if not M.state.accepted[i] and not M.state.rejected[i] then
      all_decided = false
    end
    if M.state.accepted[i] then
      has_accepted = true
    end
  end

  -- If all decided, apply and clear
  if all_decided then
    if has_accepted then
      M.apply_accepted()
    else
      M.restore_original()
    end
  end
end

-- Accept change at cursor
function M.accept_at_cursor()
  if not M.state.showing then
    return
  end

  local idx = get_change_at_cursor()
  if not idx then
    vim.api.nvim_echo({{'No change at cursor position', 'WarningMsg'}}, false, {})
    return
  end

  -- Skip if already decided
  if M.state.accepted[idx] or M.state.rejected[idx] then
    vim.api.nvim_echo({{'Change already decided', 'WarningMsg'}}, false, {})
    -- Try to advance to next pending
    local next_idx = find_next_pending(idx)
    if next_idx then
      jump_to_change(next_idx)
    end
    return
  end

  -- Mark as accepted
  M.state.accepted[idx] = true
  M.state.rejected[idx] = nil

  -- Update quickfix list
  M.populate_quickfix()

  -- Count remaining
  local pending = 0
  for i = 1, #M.state.response.changes do
    if not M.state.accepted[i] and not M.state.rejected[i] then
      pending = pending + 1
    end
  end

  vim.api.nvim_echo({{
    string.format('✅ Accepted change %d (%d pending)', idx, pending), 'String'
  }}, false, {})

  M.refresh_display()

  -- Auto-advance to next pending change
  local next_idx = find_next_pending(idx)
  if next_idx then
    vim.defer_fn(function()
      jump_to_change(next_idx)
    end, 100)
  end
end

-- Reject change at cursor
function M.reject_at_cursor()
  if not M.state.showing then
    return
  end

  local idx = get_change_at_cursor()
  if not idx then
    vim.api.nvim_echo({{'No change at cursor position', 'WarningMsg'}}, false, {})
    return
  end

  -- Skip if already decided
  if M.state.accepted[idx] or M.state.rejected[idx] then
    vim.api.nvim_echo({{'Change already decided', 'WarningMsg'}}, false, {})
    -- Try to advance to next pending
    local next_idx = find_next_pending(idx)
    if next_idx then
      jump_to_change(next_idx)
    end
    return
  end

  -- Mark as rejected
  M.state.rejected[idx] = true
  M.state.accepted[idx] = nil

  -- Update quickfix list
  M.populate_quickfix()

  -- Count remaining
  local pending = 0
  for i = 1, #M.state.response.changes do
    if not M.state.accepted[i] and not M.state.rejected[i] then
      pending = pending + 1
    end
  end

  vim.api.nvim_echo({{
    string.format('🔥 Rejected change %d (%d pending)', idx, pending), 'String'
  }}, false, {})

  M.refresh_display()

  -- Auto-advance to next pending change
  local next_idx = find_next_pending(idx)
  if next_idx then
    vim.defer_fn(function()
      jump_to_change(next_idx)
    end, 100)
  end
end

-- Apply accepted changes
function M.apply_accepted()
  -- Build list of accepted changes
  local accepted_changes = {}
  for i, change in ipairs(M.state.response.changes) do
    if M.state.accepted[i] then
      table.insert(accepted_changes, change)
    end
  end

  -- Apply changes
  local final_lines = M.state.original_lines
  if #accepted_changes > 0 then
    if M.state.response.new_file then
      -- For new files, use the replace content as the entire file
      final_lines = vim.split(accepted_changes[1].replace, '\n')
    else
      final_lines = search_replace.apply_changes(M.state.original_lines, accepted_changes)
    end
  end

  -- Remove padding line if we added one
  if M.state.has_padding then
    table.remove(final_lines, 1)
  end

  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, final_lines)

  -- Mark buffer as modified if it's a new file
  if M.state.response.new_file then
    vim.bo[M.state.target_buf].modified = true
  end

  M.clear()
  vim.api.nvim_echo({{
    string.format('✓ Applied %d changes', #accepted_changes), 'String'
  }}, false, {})
end

-- Restore original content
function M.restore_original()
  if not M.state.target_buf or not M.state.original_lines then
    M.clear()
    return
  end

  -- If this was a new file, just clear it (user can :q! if they want)
  if M.state.response and M.state.response.new_file then
    vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, {})
    M.clear()
    vim.api.nvim_echo({{'✗ New file cleared - use :q! to close without saving', 'String'}}, false, {})
    return
  end

  -- Restore original (without padding if we added it)
  local lines_to_restore = M.state.original_lines
  if M.state.has_padding then
    lines_to_restore = vim.list_slice(M.state.original_lines, 2)
  end

  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, lines_to_restore)

  M.clear()
  vim.api.nvim_echo({{'✗ All changes rejected', 'String'}}, false, {})
end

-- Clear diff display
function M.clear()
  if M.state.ns_id and M.state.target_buf then
    vim.api.nvim_buf_clear_namespace(M.state.target_buf, M.state.ns_id, 0, -1)
  end

  restore_diagnostics(M.state.target_buf)

  M.state = {
    target_buf = nil,
    response = nil,
    original_lines = nil,
    ns_id = nil,
    showing = false,
    accepted = {},
    rejected = {},
    diagnostics_disabled = false,
    has_padding = false,
    change_locations = {},
    new_files = {},
  }
end

-- Navigate to next change
function M.next_change()
  if not M.state.showing then
    return
  end

  local idx = get_change_at_cursor()
  if not idx then
    idx = 0
  end

  -- Find next non-rejected change
  for i = idx + 1, #M.state.response.changes do
    if not M.state.rejected[i] then
      if jump_to_change(i) then
        return
      end
    end
  end

  -- Wrap to beginning
  for i = 1, math.min(idx, #M.state.response.changes) do
    if not M.state.rejected[i] then
      if jump_to_change(i) then
        return
      end
    end
  end

  vim.api.nvim_echo({{'No more changes', 'WarningMsg'}}, false, {})
end

-- Navigate to previous change
function M.prev_change()
  if not M.state.showing then
    return
  end

  local idx = get_change_at_cursor()
  if not idx then
    idx = #M.state.response.changes + 1
  end

  -- Find previous non-rejected change
  for i = idx - 1, 1, -1 do
    if not M.state.rejected[i] then
      if jump_to_change(i) then
        return
      end
    end
  end

  -- Wrap to end
  for i = #M.state.response.changes, math.max(idx, 1), -1 do
    if not M.state.rejected[i] then
      if jump_to_change(i) then
        return
      end
    end
  end

  vim.api.nvim_echo({{'No more changes', 'WarningMsg'}}, false, {})
end

-- Setup keymaps
function M.setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true }

  -- Accept/Reject at cursor
  vim.keymap.set('n', '<leader>ta', M.accept_at_cursor,
    vim.tbl_extend('force', opts, { desc = 'Accept change at cursor' }))
  vim.keymap.set('n', '<leader>tr', M.reject_at_cursor,
    vim.tbl_extend('force', opts, { desc = 'Reject change at cursor' }))

  -- Navigation with ]c and [c
  vim.keymap.set('n', ']c', M.next_change,
    vim.tbl_extend('force', opts, { desc = 'Next change' }))
  vim.keymap.set('n', '[c', M.prev_change,
    vim.tbl_extend('force', opts, { desc = 'Previous change' }))

  -- Also support ]] and [[
  vim.keymap.set('n', ']]', M.next_change,
    vim.tbl_extend('force', opts, { desc = 'Next change' }))
  vim.keymap.set('n', '[[', M.prev_change,
    vim.tbl_extend('force', opts, { desc = 'Previous change' }))
end

-- Legacy compatibility aliases
M.show_response = M.show
M.accept = M.accept_at_cursor
M.reject = M.reject_at_cursor
M.accept_all = M.apply_accepted
M.reject_all = M.restore_original
M.clear_diff = M.clear

return M