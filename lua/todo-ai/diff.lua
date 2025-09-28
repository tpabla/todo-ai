local M = {}

M.state = {
  original_lines = {},
  new_lines = {},
  diff_buf = nil,
  target_buf = nil,
  target_line = nil
}

-- Define git-style color scheme
function M.setup_highlights()
  -- Check if background is dark or light
  local is_dark = vim.o.background == 'dark'

  if is_dark then
    -- Dark theme colors (Claude Code style)
    -- Green for additions
    vim.api.nvim_set_hl(0, 'TodoAIDiffAdd', { fg = '#22c55e' })
    vim.api.nvim_set_hl(0, 'TodoAIDiffAddLine', { fg = '#22c55e', bg = '#0f2e1d' })

    -- Red for deletions
    vim.api.nvim_set_hl(0, 'TodoAIDiffDelete', { fg = '#ef4444' })
    vim.api.nvim_set_hl(0, 'TodoAIDiffDeleteLine', { fg = '#ef4444', bg = '#3f1f1f' })

    -- Blue/Cyan for headers
    vim.api.nvim_set_hl(0, 'TodoAIDiffHeader', { fg = '#60a5fa', bold = true })

    -- Gray for context
    vim.api.nvim_set_hl(0, 'TodoAIDiffContext', { fg = '#6b7280' })
  else
    -- Light theme colors (Claude Code style)
    -- Green for additions
    vim.api.nvim_set_hl(0, 'TodoAIDiffAdd', { fg = '#16a34a' })
    vim.api.nvim_set_hl(0, 'TodoAIDiffAddLine', { fg = '#16a34a', bg = '#dcfce7' })

    -- Red for deletions
    vim.api.nvim_set_hl(0, 'TodoAIDiffDelete', { fg = '#dc2626' })
    vim.api.nvim_set_hl(0, 'TodoAIDiffDeleteLine', { fg = '#dc2626', bg = '#fee2e2' })

    -- Blue for headers
    vim.api.nvim_set_hl(0, 'TodoAIDiffHeader', { fg = '#0366d6', bold = true })

    -- Gray for context
    vim.api.nvim_set_hl(0, 'TodoAIDiffContext', { fg = '#6a737d' })
  end
end

function M.show(bufnr, line_num, new_code, explanation)
  M.state.target_buf = bufnr
  M.state.target_line = line_num

  local config = require('todo-ai.config')
  local style = config.get('diff_style')

  if style == 'inline' then
    M.show_inline(bufnr, line_num, new_code)
  else
    M.show_split(bufnr, line_num, new_code)
  end
end

function M.show_inline(bufnr, line_num, new_code)
  -- Setup minimalist highlights
  M.setup_highlights()

  -- Store original lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)

  -- Clean markdown formatting if present
  new_code = M.clean_code_block(new_code)

  -- Parse new code into lines
  local new_lines = vim.split(new_code, '\n')

  -- Calculate the range to replace
  local todo_line = lines[line_num]
  local indent = todo_line:match('^(%s*)') or ''
  local indent_len = #indent

  -- Determine the filetype for language-specific handling
  local filetype = vim.bo[bufnr].filetype

  -- Find the end of the block to replace
  local end_line = line_num

  -- Check if there's actual code after the TODO that needs replacing
  local has_code_after = false
  for i = line_num + 1, #lines do
    local line = lines[i]
    if not line:match('^%s*$') then  -- Non-empty line
      has_code_after = true
      break
    end
  end

  if has_code_after then
    -- Find the logical end of the code block to replace
    for i = line_num + 1, #lines do
      local line = lines[i]
      local line_indent = line:match('^(%s*)') or ''
      local line_indent_len = #line_indent

      -- Stop conditions (language-agnostic)
      if line:match('TODO:') or line:match('@ai') then
        -- Another TODO found
        break
      elseif line:match('^%s*$') then
        -- Empty line - include it but keep looking
        end_line = i
      elseif line_indent_len < indent_len and not line:match('^%s*$') then
        -- Line with less indentation (end of block)
        break
      elseif M.is_block_start(line, filetype) and line_indent_len <= indent_len then
        -- Start of a new function/class/method at same or less indentation
        break
      else
        -- Include this line in the replacement
        end_line = i
      end
    end
  end

  -- Build the new buffer content with minimal diff display
  local new_buffer_lines = {}

  -- Add lines before the diff
  for i = 1, line_num - 1 do
    table.insert(new_buffer_lines, lines[i])
  end

  -- Add a simple header
  table.insert(new_buffer_lines, string.format('%s@@ -%d,%d +%d,%d @@',
    indent,
    line_num, end_line - line_num + 1,
    line_num, #new_lines))

  -- Show removed lines (original code)
  for i = line_num, end_line do
    table.insert(new_buffer_lines, '-' .. lines[i])
  end

  -- Show added lines (new code)
  for _, line in ipairs(new_lines) do
    table.insert(new_buffer_lines, '+' .. indent .. line)
  end

  -- Add the rest of the file
  for i = end_line + 1, #lines do
    table.insert(new_buffer_lines, lines[i])
  end

  -- Apply the diff display to the buffer without adding to undo history
  -- Save current cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  -- Use undojoin to combine with previous change to avoid polluting undo
  vim.cmd('noautocmd silent! undojoin')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_buffer_lines)

  -- Mark this as a temporary change that shouldn't be in undo
  vim.bo[bufnr].modified = false

  -- Apply git-style highlighting
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  -- The header (@@ line) is now at position line_num (1-indexed)
  local header_line = line_num

  -- Highlight header (@@ line)
  if header_line <= total_lines then
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffHeader', header_line - 1, 0, -1)
  end

  -- Removed lines start right after the header
  local removed_start = header_line + 1
  for i = 0, (end_line - line_num) do
    local line_idx = removed_start + i - 1
    if line_idx < total_lines then
      -- Apply highlighting to the diff marker
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDelete', line_idx, 0, 1)
      -- Apply whole line background color after the marker
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDeleteLine', line_idx, 1, -1)
    end
  end

  -- Added lines start after all removed lines
  local added_start = removed_start + (end_line - line_num + 1)
  for i = 0, #new_lines - 1 do
    local line_idx = added_start + i - 1
    if line_idx < total_lines then
      -- Apply highlighting to the diff marker
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAdd', line_idx, 0, 1)
      -- Apply whole line background color after the marker
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAddLine', line_idx, 1, -1)
    end
  end

  -- Note: Context lines highlighting removed since we're showing inline diff
  -- The lines after the diff remain unchanged and don't need special highlighting

  -- Add simple virtual text for accept/reject
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
    virt_text = {{' [<leader>ta: accept, <leader>tr: reject]', 'Comment'}},
    virt_text_pos = 'eol',
  })

  -- Store the new lines for later application
  M.state.new_lines = {}
  for i = 1, line_num - 1 do
    table.insert(M.state.new_lines, lines[i])
  end
  for _, line in ipairs(new_lines) do
    table.insert(M.state.new_lines, line)
  end
  for i = end_line + 1, #lines do
    table.insert(M.state.new_lines, lines[i])
  end
end

function M.show_split(bufnr, line_num, new_code)
  -- Create a new buffer for diff view
  M.state.diff_buf = vim.api.nvim_create_buf(false, true)

  -- Open in a split
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, M.state.diff_buf)

  -- Set up the diff
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)

  -- Clean code
  new_code = M.clean_code_block(new_code)

  -- Show simple diff
  local diff_lines = {'--- Original', ''}
  local context_start = math.max(1, line_num - 5)
  local context_end = math.min(#lines, line_num + 5)

  for i = context_start, context_end do
    local prefix = i == line_num and '> ' or '  '
    table.insert(diff_lines, prefix .. lines[i])
  end

  table.insert(diff_lines, '')
  table.insert(diff_lines, '+++ Proposed')
  table.insert(diff_lines, '')

  -- Show new code
  local new_lines = vim.split(new_code, '\n')
  for _, line in ipairs(new_lines) do
    table.insert(diff_lines, '+ ' .. line)
  end

  vim.api.nvim_buf_set_lines(M.state.diff_buf, 0, -1, false, diff_lines)
  vim.bo[M.state.diff_buf].filetype = 'diff'
  vim.bo[M.state.diff_buf].modifiable = false

  -- Store the new lines for later application
  M.state.new_lines = {}
  for i = 1, line_num - 1 do
    table.insert(M.state.new_lines, lines[i])
  end
  for _, line in ipairs(new_lines) do
    table.insert(M.state.new_lines, line)
  end

  -- Find the end of the block to replace
  local end_line = line_num
  local indent = lines[line_num]:match('^(%s*)') or ''
  local indent_len = #indent
  local filetype = vim.bo[bufnr].filetype

  for i = line_num + 1, #lines do
    local line = lines[i]
    local line_indent = line:match('^(%s*)') or ''
    local line_indent_len = #line_indent

    if line:match('TODO:') or line:match('@ai') then
      break
    elseif line:match('^%s*$') then
      end_line = i
    elseif line_indent_len < indent_len and not line:match('^%s*$') then
      break
    elseif M.is_block_start(line, filetype) and line_indent_len <= indent_len then
      break
    else
      end_line = i
    end
  end

  for i = end_line + 1, #lines do
    table.insert(M.state.new_lines, lines[i])
  end
end

function M.accept(todo)
  if not M.state.new_lines or #M.state.new_lines == 0 then
    return false
  end

  -- Clear the diff display first
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')
  vim.api.nvim_buf_clear_namespace(M.state.target_buf, ns_id, 0, -1)

  -- Apply the actual code changes (this should be the only undo point)
  vim.cmd('normal! u')  -- Undo the diff display
  vim.api.nvim_buf_set_lines(M.state.target_buf, 0, -1, false, M.state.new_lines)

  -- Mark as modified since we made real changes
  vim.bo[M.state.target_buf].modified = true

  -- Close diff buffer if in split mode
  if M.state.diff_buf and vim.api.nvim_buf_is_valid(M.state.diff_buf) then
    vim.api.nvim_buf_delete(M.state.diff_buf, { force = true })
  end

  -- Clear state
  M.state = {
    original_lines = {},
    new_lines = {},
    diff_buf = nil,
    target_buf = nil,
    target_line = nil
  }

  vim.notify('✓ Changes accepted', vim.log.levels.INFO)
  return true
end

-- Show diff for specific line range
function M.show_range(bufnr, start_line, end_line, new_code, explanation)
  M.state.target_buf = bufnr
  M.state.target_start_line = start_line
  M.state.target_end_line = end_line
  M.state.is_range = true

  -- Setup highlights
  M.setup_highlights()

  -- Store original lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)

  -- Clean code
  new_code = M.clean_code_block(new_code)

  -- Parse new code into lines
  local new_lines = vim.split(new_code, '\n')

  -- Get indent from first line
  local indent = ''
  if start_line > 0 and start_line <= #lines then
    indent = lines[start_line]:match('^(%s*)') or ''
  end

  -- Build new buffer content with diff display
  local new_buffer_lines = {}

  -- Add lines before the change
  for i = 1, start_line - 1 do
    table.insert(new_buffer_lines, lines[i])
  end

  -- Add diff header
  table.insert(new_buffer_lines, string.format('%s@@ -%d,%d +%d,%d @@ %s',
    indent,
    start_line, end_line - start_line + 1,
    start_line, #new_lines,
    explanation or ''))

  -- Show removed lines
  for i = start_line, math.min(end_line, #lines) do
    table.insert(new_buffer_lines, '-' .. lines[i])
  end

  -- Show added lines
  for _, line in ipairs(new_lines) do
    table.insert(new_buffer_lines, '+' .. indent .. line)
  end

  -- Add remaining lines
  for i = end_line + 1, #lines do
    table.insert(new_buffer_lines, lines[i])
  end

  -- Apply to buffer
  vim.cmd('noautocmd silent! undojoin')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_buffer_lines)
  vim.bo[bufnr].modified = false

  -- Apply highlighting (account for 0-based indexing in Neovim)
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- The header is now at line start_line (1-based) in the modified buffer
  -- Convert to 0-based for highlight API
  local header_line_idx = start_line - 1

  -- Highlight header
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffHeader', header_line_idx, 0, -1)

  -- Highlight removed lines (they start right after header in 1-based indexing)
  local removed_start = start_line + 1
  for i = 0, (end_line - start_line) do
    local line_idx = removed_start + i - 1
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDelete', line_idx, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDeleteLine', line_idx, 1, -1)
  end

  -- Highlight added lines
  local added_start = removed_start + (end_line - start_line + 1)
  for i = 0, #new_lines - 1 do
    local line_idx = added_start + i - 1
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAdd', line_idx, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAddLine', line_idx, 1, -1)
  end

  -- Add accept/reject hint
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, header_line_idx, 0, {
    virt_text = {{' [<leader>ta: accept, <leader>tr: reject]', 'Comment'}},
    virt_text_pos = 'eol',
  })

  -- Store new lines for accept
  M.state.new_lines = {}
  for i = 1, start_line - 1 do
    table.insert(M.state.new_lines, lines[i])
  end
  for _, line in ipairs(new_lines) do
    table.insert(M.state.new_lines, indent .. line)
  end
  for i = end_line + 1, #lines do
    table.insert(M.state.new_lines, lines[i])
  end
end

-- Show multiple changes at once
function M.show_multi_changes(bufnr, changes, explanation)
  -- TODO: Implement multi-change diff view
  -- For now, just show the first change
  if #changes > 0 then
    local change = changes[1]
    M.show_range(bufnr, change.start_line, change.end_line, change.code, change.description or explanation)
  end
end

-- Show diff for entire buffer replacement
function M.show_full_buffer(bufnr, new_code, explanation)
  M.state.target_buf = bufnr
  M.state.is_full_buffer = true

  -- Setup minimalist highlights
  M.setup_highlights()

  -- Store original lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)

  -- Clean markdown formatting if present
  new_code = M.clean_code_block(new_code)

  -- Parse new code into lines
  local new_lines = vim.split(new_code, '\n')

  -- Build diff display
  local diff_lines = {}

  -- Add diff header
  table.insert(diff_lines, '@@ -1,' .. #lines .. ' +1,' .. #new_lines .. ' @@ [Full Buffer Replacement]')

  -- Show removed lines (original content)
  for _, line in ipairs(lines) do
    table.insert(diff_lines, '-' .. line)
  end

  -- Show added lines (new content)
  for _, line in ipairs(new_lines) do
    table.insert(diff_lines, '+' .. line)
  end

  -- Apply the diff display to the buffer
  vim.cmd('noautocmd silent! undojoin')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_lines)
  vim.bo[bufnr].modified = false

  -- Apply highlighting
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- Highlight header
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffHeader', 0, 0, -1)

  -- Highlight removed lines
  for i = 1, #lines do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDelete', i, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDeleteLine', i, 1, -1)
  end

  -- Highlight added lines
  local added_start = 1 + #lines
  for i = 1, #new_lines do
    local line_idx = added_start + i - 1
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAdd', line_idx, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAddLine', line_idx, 1, -1)
  end

  -- Add virtual text for accept/reject
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
    virt_text = {{' [<leader>ta: accept, <leader>tr: reject]', 'Comment'}},
    virt_text_pos = 'eol',
  })

  -- Store the new lines for replacement
  M.state.new_lines = new_lines
end

-- Show diff for visual selection
function M.show_visual(bufnr, start_line, end_line, new_code, explanation)
  M.state.target_buf = bufnr
  M.state.target_start_line = start_line
  M.state.target_end_line = end_line
  M.state.is_visual = true

  local config = require('todo-ai.config')
  local style = config.get('diff_style')

  if style == 'inline' then
    M.show_inline_visual(bufnr, start_line, end_line, new_code)
  else
    -- TODO: implement split view for visual
    M.show_inline_visual(bufnr, start_line, end_line, new_code)
  end
end

function M.show_inline_visual(bufnr, start_line, end_line, new_code)
  -- Setup minimalist highlights
  M.setup_highlights()

  -- Store original lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.state.original_lines = vim.deepcopy(lines)

  -- Clean markdown formatting if present
  new_code = M.clean_code_block(new_code)

  -- Parse new code into lines
  local new_lines = vim.split(new_code, '\n')

  -- Get indent from first selected line
  local indent = lines[start_line]:match('^(%s*)') or ''

  -- Build the new buffer content with minimal diff display
  local new_buffer_lines = {}

  -- Add lines before the selection
  for i = 1, start_line - 1 do
    table.insert(new_buffer_lines, lines[i])
  end

  -- Add diff header
  table.insert(new_buffer_lines, string.format('%s@@ -%d,%d +%d,%d @@ [Visual Selection]',
    indent,
    start_line, end_line - start_line + 1,
    start_line, #new_lines))

  -- Show removed lines (original selection)
  for i = start_line, end_line do
    table.insert(new_buffer_lines, '-' .. lines[i])
  end

  -- Show added lines (new code)
  for _, line in ipairs(new_lines) do
    table.insert(new_buffer_lines, '+' .. indent .. line)
  end

  -- Add the rest of the file
  for i = end_line + 1, #lines do
    table.insert(new_buffer_lines, lines[i])
  end

  -- Apply the diff display to the buffer
  vim.cmd('noautocmd silent! undojoin')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_buffer_lines)
  vim.bo[bufnr].modified = false

  -- Apply highlighting
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')

  -- The header is at position start_line
  local header_line = start_line

  -- Highlight header
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffHeader', header_line - 1, 0, -1)

  -- Removed lines
  local removed_start = header_line + 1
  for i = 0, (end_line - start_line) do
    local line_idx = removed_start + i - 1
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDelete', line_idx, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffDeleteLine', line_idx, 1, -1)
  end

  -- Added lines
  local added_start = removed_start + (end_line - start_line + 1)
  for i = 0, #new_lines - 1 do
    local line_idx = added_start + i - 1
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAdd', line_idx, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'TodoAIDiffAddLine', line_idx, 1, -1)
  end

  -- Add virtual text for accept/reject
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line - 1, 0, {
    virt_text = {{' [<leader>ta: accept, <leader>tr: reject]', 'Comment'}},
    virt_text_pos = 'eol',
  })

  -- Store the new lines for visual replacement
  M.state.new_lines = {}
  for i = 1, start_line - 1 do
    table.insert(M.state.new_lines, lines[i])
  end
  for _, line in ipairs(new_lines) do
    table.insert(M.state.new_lines, indent .. line)
  end
  for i = end_line + 1, #lines do
    table.insert(M.state.new_lines, lines[i])
  end
end

function M.reject()
  if not M.state.original_lines or #M.state.original_lines == 0 then
    return false
  end

  -- Clear highlighting first
  local ns_id = vim.api.nvim_create_namespace('todo_ai_diff')
  vim.api.nvim_buf_clear_namespace(M.state.target_buf, ns_id, 0, -1)

  -- Restore original lines (just undo the diff display)
  vim.cmd('normal! u')  -- This undoes the diff display, returning to original

  -- Close diff buffer if in split mode
  if M.state.diff_buf and vim.api.nvim_buf_is_valid(M.state.diff_buf) then
    vim.api.nvim_buf_delete(M.state.diff_buf, { force = true })
  end

  -- Clear state
  M.state = {
    original_lines = {},
    new_lines = {},
    diff_buf = nil,
    target_buf = nil,
    target_line = nil
  }

  vim.notify('✗ Changes rejected', vim.log.levels.WARN)
  return true
end

function M.clean_code_block(code)
  -- Remove markdown code block formatting if present
  local cleaned = code

  -- Remove opening ```language marker
  cleaned = cleaned:gsub('^```%w*\n', '')

  -- Remove closing ```
  cleaned = cleaned:gsub('\n```$', '')
  cleaned = cleaned:gsub('^```$', '')

  -- If it still starts/ends with ```, remove them
  if cleaned:match('^```') then
    cleaned = cleaned:gsub('^```[^\n]*\n?', '')
  end
  if cleaned:match('```%s*$') then
    cleaned = cleaned:gsub('```%s*$', '')
  end

  return cleaned
end

function M.is_block_start(line, filetype)
  -- Detect start of a new code block based on language
  local patterns = {
    -- Python
    python = { '^%s*def ', '^%s*class ', '^%s*async def ' },
    -- JavaScript/TypeScript
    javascript = { '^%s*function ', '^%s*const %w+%s*=%s*function', '^%s*class ', '^%s*async function' },
    typescript = { '^%s*function ', '^%s*const %w+%s*=%s*function', '^%s*class ', '^%s*async function', '^%s*interface ', '^%s*type ' },
    javascriptreact = { '^%s*function ', '^%s*const %w+%s*=%s*', '^%s*class ', '^%s*export ' },
    typescriptreact = { '^%s*function ', '^%s*const %w+%s*=%s*', '^%s*class ', '^%s*export ', '^%s*interface ' },
    -- Java/C/C++
    java = { '^%s*public ', '^%s*private ', '^%s*protected ', '^%s*class ', '^%s*interface ', '^%s*void ', '^%s*int ', '^%s*String ' },
    c = { '^%s*int ', '^%s*void ', '^%s*char ', '^%s*float ', '^%s*double ', '^%s*struct ', '^%s*typedef ' },
    cpp = { '^%s*int ', '^%s*void ', '^%s*char ', '^%s*float ', '^%s*double ', '^%s*class ', '^%s*struct ', '^%s*namespace ', '^%s*template' },
    -- Go
    go = { '^%s*func ', '^%s*type ', '^%s*var ', '^%s*const ' },
    -- Rust
    rust = { '^%s*fn ', '^%s*impl ', '^%s*struct ', '^%s*enum ', '^%s*trait ', '^%s*mod ', '^%s*pub fn' },
    -- Ruby
    ruby = { '^%s*def ', '^%s*class ', '^%s*module ', '^%s*begin ' },
    -- PHP
    php = { '^%s*function ', '^%s*class ', '^%s*public function', '^%s*private function', '^%s*protected function' },
    -- Lua
    lua = { '^%s*function ', '^%s*local function' },
    -- Shell/Bash
    sh = { '^%s*function ', '^%s*[%w_]+%(%)%s*{' },
    bash = { '^%s*function ', '^%s*[%w_]+%(%)%s*{' },
    -- Default patterns for unknown languages
    default = { '^%s*function', '^%s*def ', '^%s*class ', '^%s*fn ', '^%s*func ' }
  }

  local lang_patterns = patterns[filetype] or patterns.default

  for _, pattern in ipairs(lang_patterns) do
    if line:match(pattern) then
      return true
    end
  end

  -- Also check for common block delimiters
  if line:match('^%s*{%s*$') or  -- Opening brace on its own line
     line:match('^%s*}%s*$') or  -- Closing brace on its own line
     line:match('^%s*<%s*$') or  -- Opening angle (some templates)
     line:match('^%s*>%s*$') then  -- Closing angle
    return true
  end

  return false
end

return M