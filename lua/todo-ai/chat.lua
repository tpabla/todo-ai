local M = {}

M.state = {
  messages = {},
  display_buf = nil,
  win = nil,
  thinking_timer = nil,
  thinking_frame = 1,
  last_input_line = "",
  streaming_content = "",  -- accumulates streamed text
}

M.thinking_frames = {
  '`🤔 Thinking`',
  '`🤔 Thinking.`',
  '`🤔 Thinking..`',
  '`🤔 Thinking...`',
}

function M.create()
  -- Reuse existing buffer if it exists
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match('Todo%-AI Chat$') then
        M.state.display_buf = buf
        M._configure_buffer(buf)
        return buf
      end
    end
  end

  M.state.display_buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, M.state.display_buf, 'Todo-AI Chat')
  M._configure_buffer(M.state.display_buf)
  return M.state.display_buf
end

function M._configure_buffer(buf)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].modifiable = true
  vim.bo[buf].modified = false

  -- :w sends message
  vim.api.nvim_buf_set_keymap(buf, 'c', 'w<CR>',
    '<Cmd>lua require("todo-ai.chat").send_message()<CR>', { silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'c', 'wq<CR>',
    '<Cmd>lua require("todo-ai.chat").send_message()<CR><Cmd>q<CR>', { silent = true })

  -- Enable render-markdown if available
  pcall(function()
    if pcall(require, 'render-markdown') then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.cmd, 'RenderMarkdown enable')
        end
      end)
    end
  end)
end

function M.open(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = M.create()
  end

  local original_win = vim.api.nvim_get_current_win()

  -- Reuse existing window
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    M.render()
    M._setup_input()
    return
  end

  -- Find existing window showing chat buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == M.state.display_buf then
      M.state.win = win
      M.render()
      M._setup_input()
      return
    end
  end

  -- Open new window
  local config = require('todo-ai.config')
  local width = config.get('chat_window_width') or 60
  local position = config.get('chat_window_position') or 'right'

  if position == 'right' then
    vim.cmd('vsplit')
    vim.cmd('wincmd L')
  elseif position == 'left' then
    vim.cmd('vsplit')
    vim.cmd('wincmd H')
  else
    vim.cmd('split')
    vim.cmd('wincmd J')
  end

  M.state.win = vim.api.nvim_get_current_win()

  if position == 'bottom' then
    vim.api.nvim_win_set_height(M.state.win, 15)
  else
    vim.api.nvim_win_set_width(M.state.win, width)
  end

  vim.api.nvim_win_set_buf(M.state.win, buf)
  vim.wo[M.state.win].wrap = true
  vim.wo[M.state.win].linebreak = true
  vim.wo[M.state.win].number = false
  vim.wo[M.state.win].relativenumber = false
  vim.wo[M.state.win].signcolumn = 'no'
  vim.wo[M.state.win].statusline = '%#StatusLine# :w to send | q to close %=%#StatusLineNC# Todo-AI Chat '

  vim.api.nvim_set_current_win(original_win)
  M.render()
  M._setup_input()
end

function M._setup_input()
  local buf = M.state.display_buf

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      M.send_message()
      vim.bo[buf].modified = false
    end
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',
    ':lua require("todo-ai.chat").send_message()<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q',
    ':lua require("todo-ai.chat").close()<CR>', { noremap = true, silent = true })

  -- Position cursor at input line
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) and M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
      local line_count = vim.api.nvim_buf_line_count(buf)
      pcall(vim.api.nvim_win_set_cursor, M.state.win, { line_count, 0 })
    end
  end)
end

-- Extract user input from the chat buffer and send it
function M.send_message()
  local buf = M.state.display_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input_idx = nil

  for i, line in ipairs(lines) do
    if line:match("^## Your message:") then
      input_idx = i + 2
      break
    end
  end

  if not input_idx or input_idx > #lines then return end

  local input = vim.trim(lines[input_idx] or "")
  if input == '' or input == M.state.last_input_line then return end

  M.state.last_input_line = input
  M.add_message('user', input)

  -- Clear input line
  lines[input_idx] = ''
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.schedule(function()
    M._send_to_pi(input)
  end)
end

-- Send a prompt to pi with Neovim context
function M._send_to_pi(message)
  local pi = require('todo-ai.pi_client')
  local ctx = require('todo-ai.context')

  if not pi.is_running() then
    M.add_message('system', '❌ pi is not running. Restarting...')
    local config = require('todo-ai.config')
    pi.start(config.config)
    M._setup_pi_handlers()
  end

  -- Build context from Neovim state
  local current_buf = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= '' and not name:match('Todo%-AI Chat') then
      current_buf = b
      break
    end
  end

  local context_text = ctx.build({
    bufnr = current_buf,
    file_path = current_buf and vim.api.nvim_buf_get_name(current_buf) or nil,
  })

  -- Prepend context to message
  local full_message = message
  if context_text then
    full_message = "<neovim_context>\n" .. context_text .. "\n</neovim_context>\n\n" .. message
  end

  M.show_thinking()
  pi.prompt(full_message)
end

-- Register event handlers for pi streaming
function M._setup_pi_handlers()
  local pi = require('todo-ai.pi_client')
  pi.clear_handlers()

  -- Streaming text
  pi.on('message_start', function(event)
    M.state.streaming_content = ""
  end)

  pi.on('message_update', function(event)
    local delta = event.assistantMessageEvent
    if not delta then return end

    if delta.type == 'text_delta' then
      M.state.streaming_content = M.state.streaming_content .. delta.delta
      M._update_streaming_display()
    end
  end)

  pi.on('message_end', function(event)
    M.hide_thinking()
    if M.state.streaming_content ~= "" then
      M.add_message('ai', M.state.streaming_content)
      M.state.streaming_content = ""
    end
  end)

  -- Tool execution feedback
  pi.on('tool_execution_start', function(event)
    local tool = event.toolName or "unknown"
    local desc = tool
    if tool == 'edit' and event.args and event.args.path then
      desc = "editing " .. vim.fn.fnamemodify(event.args.path, ':t')
    elseif tool == 'write' and event.args and event.args.path then
      desc = "writing " .. vim.fn.fnamemodify(event.args.path, ':t')
    elseif tool == 'bash' and event.args and event.args.command then
      desc = "running `" .. event.args.command:sub(1, 40) .. "`"
    elseif tool == 'read' and event.args and event.args.path then
      desc = "reading " .. vim.fn.fnamemodify(event.args.path, ':t')
    end
    M.add_message('system', '🔧 ' .. desc)
  end)

  -- Agent done
  pi.on('agent_end', function(event)
    M.hide_thinking()
    M.add_message('system', '✅ Done. Use `:DiffviewOpen` to review file changes.')
    -- Reload any buffers that pi may have modified
    vim.schedule(function()
      vim.cmd('checktime')
    end)
  end)
end

-- Update the display with streaming content (efficient, no full re-render)
function M._update_streaming_display()
  if not M.state.display_buf or not vim.api.nvim_buf_is_valid(M.state.display_buf) then return end

  -- Hide thinking if still showing
  M.hide_thinking()

  -- Find or create the streaming message area
  local lines = vim.api.nvim_buf_get_lines(M.state.display_buf, 0, -1, false)

  -- Look for the streaming marker
  local stream_start = nil
  for i, line in ipairs(lines) do
    if line == '<!-- streaming -->' then
      stream_start = i
      break
    end
  end

  local content_lines = vim.split(M.state.streaming_content, '\n')
  local new_lines = { '<!-- streaming -->', '**AI** _(' .. os.date('%H:%M') .. ')_:', '' }
  for _, line in ipairs(content_lines) do
    table.insert(new_lines, line)
  end
  table.insert(new_lines, '')
  table.insert(new_lines, '---')

  vim.bo[M.state.display_buf].modifiable = true

  if stream_start then
    -- Replace from stream marker to the next --- or end
    local stream_end = #lines
    for i = stream_start + 1, #lines do
      if lines[i] == '---' then
        stream_end = i
        break
      end
    end
    vim.api.nvim_buf_set_lines(M.state.display_buf, stream_start - 1, stream_end, false, new_lines)
  else
    -- Insert before "## Your message:" section
    local insert_at = #lines
    for i, line in ipairs(lines) do
      if line:match("^## Your message:") then
        insert_at = i - 2  -- Before the blank line before header
        break
      end
    end
    if insert_at < 1 then insert_at = 1 end
    vim.api.nvim_buf_set_lines(M.state.display_buf, insert_at, insert_at, false, new_lines)
  end

  -- Scroll to bottom
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    local count = vim.api.nvim_buf_line_count(M.state.display_buf)
    pcall(vim.api.nvim_win_set_cursor, M.state.win, { count, 0 })
  end
end

function M.add_message(role, content)
  -- Remove streaming marker from buffer when finalizing
  if role == 'ai' and M.state.display_buf and vim.api.nvim_buf_is_valid(M.state.display_buf) then
    local lines = vim.api.nvim_buf_get_lines(M.state.display_buf, 0, -1, false)
    local filtered = {}
    local skip_until_separator = false
    for _, line in ipairs(lines) do
      if line == '<!-- streaming -->' then
        skip_until_separator = true
      elseif skip_until_separator and line == '---' then
        skip_until_separator = false
      elseif not skip_until_separator then
        table.insert(filtered, line)
      end
    end
    vim.bo[M.state.display_buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.state.display_buf, 0, -1, false, filtered)
  end

  table.insert(M.state.messages, {
    role = role,
    content = content,
    timestamp = os.date('%H:%M')
  })
  M.render()
end

function M.render()
  if not M.state.display_buf or not vim.api.nvim_buf_is_valid(M.state.display_buf) then return end

  local lines = { '# Todo-AI Chat', '', '---', '' }

  for _, msg in ipairs(M.state.messages) do
    local prefix = msg.role == 'user' and '**You**' or '**AI**'
    if msg.role == 'system' then prefix = '**System**' end
    table.insert(lines, prefix .. ' _(' .. msg.timestamp .. ')_:')
    table.insert(lines, '')
    for _, line in ipairs(vim.split(msg.content or '', '\n')) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '')
  end

  table.insert(lines, '')
  table.insert(lines, '## Your message:')
  table.insert(lines, '')
  table.insert(lines, '')

  M.state.last_input_line = ""

  vim.bo[M.state.display_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.state.display_buf, 0, -1, false, lines)
  vim.bo[M.state.display_buf].modified = false

  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    local count = vim.api.nvim_buf_line_count(M.state.display_buf)
    pcall(vim.api.nvim_win_set_cursor, M.state.win, { count, 0 })
  end
end

function M.close()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
    M.state.win = nil
  end
end

function M.clear()
  M.state.messages = {}
  M.render()
end

function M.show_thinking()
  if M.state.thinking_timer then return end

  table.insert(M.state.messages, {
    role = 'ai',
    content = M.thinking_frames[1],
    timestamp = os.date('%H:%M'),
    is_thinking = true,
  })
  M.render()

  M.state.thinking_frame = 1
  M.state.thinking_timer = vim.fn.timer_start(800, function()
    local msg = M.state.messages[#M.state.messages]
    if msg and msg.is_thinking then
      M.state.thinking_frame = (M.state.thinking_frame % #M.thinking_frames) + 1
      msg.content = M.thinking_frames[M.state.thinking_frame]
      M.render()
    end
  end, { ['repeat'] = -1 })
end

function M.hide_thinking()
  if M.state.thinking_timer then
    vim.fn.timer_stop(M.state.thinking_timer)
    M.state.thinking_timer = nil
  end
  if M.state.messages[#M.state.messages] and M.state.messages[#M.state.messages].is_thinking then
    table.remove(M.state.messages)
    M.render()
  end
end

return M
