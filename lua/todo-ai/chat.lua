local M = {}

M.state = {
  messages = {},
  input_buf = nil,
  display_buf = nil,
  win = nil,
  thinking_timer = nil,
  thinking_frame = 1,
  thinking_line_num = nil,  -- Track which line has the spinner
  edit_queue = {},  -- Queue of pending edits
  current_edit_index = 0,  -- Current position in edit queue
  edit_preview_buf = nil  -- Buffer showing edit preview
}

-- Thinking animation frames with more visual flair
M.thinking_frames = {
  '`🤔 Thinking`',
  '`🤔 Thinking.`',
  '`🤔 Thinking..`',
  '`🤔 Thinking...`',
  '`💭 Processing`',
  '`💭 Processing.`',
  '`💭 Processing..`',
  '`💭 Processing...`',
  '`🧠 Analyzing`',
  '`🧠 Analyzing.`',
  '`🧠 Analyzing..`',
  '`🧠 Analyzing...`',
  '`✨ Generating`',
  '`✨ Generating.`',
  '`✨ Generating..`',
  '`✨ Generating...`',
  '`🔮 Contemplating`',
  '`🔮 Contemplating.`',
  '`🔮 Contemplating..`',
  '`🔮 Contemplating...`',
  '`⚡ Computing`',
  '`⚡ Computing.`',
  '`⚡ Computing..`',
  '`⚡ Computing...`',
}

function M.create()
  -- Check if a buffer with this name already exists
  local existing_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match('Todo%-AI Chat$') then
        existing_buf = buf
        break
      end
    end
  end

  -- Use existing buffer or create new one
  if existing_buf then
    M.state.display_buf = existing_buf
  else
    -- Create display buffer for chat messages
    M.state.display_buf = vim.api.nvim_create_buf(false, true)

    -- Set buffer name without a file path (using special buffer naming)
    pcall(vim.api.nvim_buf_set_name, M.state.display_buf, 'Todo-AI Chat')
  end

  -- Always reconfigure the buffer settings
  -- Use custom filetype that inherits markdown
  vim.bo[M.state.display_buf].filetype = 'todoai-chat'
  vim.bo[M.state.display_buf].buftype = 'nofile'  -- This is a special buffer, not a file
  vim.bo[M.state.display_buf].swapfile = false
  vim.bo[M.state.display_buf].bufhidden = 'hide'
  vim.bo[M.state.display_buf].modifiable = true  -- Allow modifications
  vim.bo[M.state.display_buf].modified = false  -- Mark as not modified

  -- Map :w to send message in chat buffer (instead of trying to save)
  vim.api.nvim_buf_set_keymap(M.state.display_buf, 'c', 'w<CR>', '<Cmd>lua require("todo-ai.chat").send_message()<CR>', {silent = true})
  vim.api.nvim_buf_set_keymap(M.state.display_buf, 'c', 'wq<CR>', '<Cmd>lua require("todo-ai.chat").send_message()<CR><Cmd>q<CR>', {silent = true})

  -- Enable render-markdown if available
  M.enable_render_markdown(M.state.display_buf)

  return M.state.display_buf
end

function M.enable_render_markdown(buf)
  -- Try to enable render-markdown plugin if available
  local ok = pcall(function()
    -- Check if render-markdown is available
    local has_render_md = pcall(require, 'render-markdown')
    if has_render_md then
      -- Enable render-markdown for this buffer
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          -- Temporarily set filetype to markdown to trigger render-markdown
          local original_ft = vim.bo[buf].filetype
          vim.bo[buf].filetype = 'markdown'

          -- Trigger render-markdown enable
          pcall(vim.cmd, 'RenderMarkdown enable')

          -- Keep markdown filetype for rendering
          vim.bo[buf].filetype = 'markdown'
        end
      end)
    end
  end)

  if not ok then
    -- Render-markdown not available, that's fine
    -- Chat will still work without it
  end
end

function M.open(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = M.create()
  end

  -- Store the current window to return focus to it later
  local original_win = vim.api.nvim_get_current_win()

  -- Check if chat window is already open
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    -- Window exists, don't focus it, just render
    M.render()
    M.setup_input()
    return
  end

  -- Find existing chat buffer window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    if win_buf == M.state.display_buf then
      M.state.win = win
      -- Don't focus the window, just store the reference
      M.render()
      M.setup_input()
      return
    end
  end

  local config = require('todo-ai.config')
  local width = config.get('chat_window_width')
  local position = config.get('chat_window_position')

  -- Calculate window dimensions
  local win_width = width
  local win_height = vim.o.lines - 4

  -- Open new window based on position
  if position == 'right' then
    vim.cmd('vsplit')
    vim.cmd('wincmd L')
  elseif position == 'left' then
    vim.cmd('vsplit')
    vim.cmd('wincmd H')
  else  -- bottom
    vim.cmd('split')
    vim.cmd('wincmd J')
    win_height = 15
    win_width = vim.o.columns
  end

  M.state.win = vim.api.nvim_get_current_win()

  -- Set window size
  if position == 'bottom' then
    vim.api.nvim_win_set_height(M.state.win, win_height)
  else
    vim.api.nvim_win_set_width(M.state.win, win_width)
  end

  -- Set buffer in window
  vim.api.nvim_win_set_buf(M.state.win, buf)

  -- Set window options
  vim.wo[M.state.win].wrap = true
  vim.wo[M.state.win].linebreak = true
  vim.wo[M.state.win].breakindent = true

  -- Enable render-markdown for the window
  M.enable_render_markdown(buf)
  vim.wo[M.state.win].linebreak = true
  vim.wo[M.state.win].number = false
  vim.wo[M.state.win].relativenumber = false
  vim.wo[M.state.win].signcolumn = 'no'

  -- Set window statusline with help text
  vim.wo[M.state.win].statusline = '%#StatusLine# :w to send | <CR> to send | q to close %=%#StatusLineNC# Todo-AI Chat '

  -- Return focus to the original window
  vim.api.nvim_set_current_win(original_win)

  -- Render messages
  M.render()

  -- Set up input handling
  M.setup_input()
end

function M.setup_input()
  -- Set up direct editing in the chat buffer
  local buf = M.state.display_buf

  -- Track the last known input line to detect actual changes
  M.state.last_input_line = ""

  -- Set up autocmd to capture saves as message sends
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      -- Find the input line by looking for the marker
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local input_idx = nil

      -- Find "## Your message:" and get the line 2 below it (skip blank line)
      for i, line in ipairs(lines) do
        if line:match("^## Your message:") then
          input_idx = i + 2  -- Skip header and blank line
          break
        end
      end

      if input_idx and input_idx <= #lines then
        local input = vim.trim(lines[input_idx] or "")

        -- Only process if this is actually new input (not empty and different from last)
        if input ~= '' and input ~= M.state.last_input_line then
          -- Store this as the last input to prevent re-sending
          M.state.last_input_line = input

          -- Add user message
          M.add_message('user', input)

          -- Clear the input line immediately in the buffer
          lines[input_idx] = ''
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

          -- Now send to backend (which will show thinking animation)
          vim.schedule(function()
            M.send_to_backend(input)
          end)
        end
      end
      -- Mark as saved to prevent the "unsaved changes" warning
      vim.bo[buf].modified = false
    end
  })

  -- Position cursor at input line when opening (but stay in normal mode)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(M.state.win) then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- Find "## Your message:" and position cursor 2 lines below
      for i, line in ipairs(lines) do
        if line:match("^## Your message:") then
          local input_line = i + 2  -- Skip header and blank line
          if input_line <= #lines then
            vim.api.nvim_win_set_cursor(M.state.win, {input_line, 0})
            -- Stay in normal mode (don't call startinsert)
          end
          break
        end
      end
    end
  end)

  -- Map Enter key in normal mode to send if there's text
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', ':lua require("todo-ai.chat").send_if_changed()<CR>', {
    noremap = true,
    silent = true,
    desc = 'Send message if input has changed'
  })

  -- Map Ctrl+Enter in insert mode to send message
  vim.api.nvim_buf_set_keymap(buf, 'i', '<C-CR>', '<Esc>:lua require("todo-ai.chat").send_message()<CR>', {
    noremap = true,
    silent = true,
    desc = 'Send message'
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("todo-ai.chat").close()<CR>', {
    noremap = true,
    silent = true
  })
end

-- Send message if input has changed (for Enter key mapping)
function M.send_if_changed()
  local buf = M.state.display_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Find and process input line
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input_idx = nil

  for i, line in ipairs(lines) do
    if line:match("^## Your message:") then
      input_idx = i + 2
      break
    end
  end

  if input_idx and input_idx <= #lines then
    local input = vim.trim(lines[input_idx] or "")
    if input ~= '' and input ~= M.state.last_input_line then
      M.state.last_input_line = input
      M.add_message('user', input)
      lines[input_idx] = ''
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.schedule(function()
        M.send_to_backend(input)
      end)
    end
  end
end

-- Initialize or get current session
function M.init_session()
  if not M.state.session_id then
    -- Generate session ID with timestamp
    M.state.session_id = os.date('%Y%m%d_%H%M%S') .. '_' .. math.random(1000, 9999)
    M.state.session_start = os.date('%Y-%m-%d %H:%M:%S')
  end
  return M.state.session_id
end

-- Save chat history via Rust backend
function M.save_chat_history()
  local backend = require('todo-ai.backend')
  if not backend.is_available() then return end

  local session_id = M.init_session()
  local config = require('todo-ai.config')

  backend.request("save_chat", {
    project_root = vim.fn.getcwd(),
    session_id = session_id,
    session_start = M.state.session_start or os.date('%Y-%m-%d %H:%M:%S'),
    messages = M.state.messages,
    max_sessions = config.get('max_chat_sessions') or 10,
  }, function(_, err)
    if err then
      local logger = require('todo-ai.logger')
      logger.error('chat', 'Failed to save chat: ' .. tostring(err))
    end
  end)
end

-- Load a previous chat session via Rust backend
function M.load_session(session_id)
  local backend = require('todo-ai.backend')
  if not backend.is_available() then
    error("Rust backend not available")
  end

  local loaded = false
  backend.request("load_chat", {
    project_root = vim.fn.getcwd(),
    session_id = session_id,
  }, function(result, err)
    if err then
      vim.notify('Failed to load session: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    M.state.messages = {}
    M.state.session_id = session_id

    if result and result.messages then
      for _, msg in ipairs(result.messages) do
        table.insert(M.state.messages, {
          role = msg.role,
          content = msg.content,
          timestamp = msg.timestamp or '',
          is_thinking = msg.is_thinking or false,
        })
      end
    end

    M.render()
    loaded = true
  end)

  return loaded
end

-- List available chat sessions via Rust backend
function M.list_sessions()
  local backend = require('todo-ai.backend')
  if not backend.is_available() then
    return {}
  end

  local sessions = {}
  backend.request("list_chats", {
    project_root = vim.fn.getcwd(),
  }, function(result, err)
    if err then return end
    if result and result.sessions then
      sessions = result.sessions
    end
  end)

  return sessions
end

function M.add_message(role, content)
  table.insert(M.state.messages, {
    role = role,
    content = content,
    timestamp = os.date('%H:%M')
  })

  -- Auto-prune old messages if history gets too long
  -- Keep system messages and recent messages
  if #M.state.messages > 200 then  -- Hard limit of 200 messages in memory
    local new_messages = {}
    local kept = 0

    -- Keep last 100 messages
    for i = math.max(1, #M.state.messages - 100), #M.state.messages do
      table.insert(new_messages, M.state.messages[i])
      kept = kept + 1
    end

    -- Add a system message about pruning
    table.insert(new_messages, 1, {
      role = 'system',
      content = string.format('💾 Auto-pruned %d old messages to manage memory', #M.state.messages - kept),
      timestamp = os.date('%H:%M')
    })

    M.state.messages = new_messages
  end

  M.render()

  -- Auto-save chat history to file
  M.save_chat_history()
end

-- Lock the buffer from editing
function M.lock_buffer()
  if M.state.display_buf and vim.api.nvim_buf_is_valid(M.state.display_buf) then
    vim.bo[M.state.display_buf].modifiable = false
    vim.bo[M.state.display_buf].modified = false
  end
end

-- Unlock the buffer for editing with treesitter protection
function M.unlock_buffer()
  if M.state.display_buf and vim.api.nvim_buf_is_valid(M.state.display_buf) then
    -- Temporarily disable treesitter highlighting during updates
    pcall(vim.treesitter.stop, M.state.display_buf)
    vim.bo[M.state.display_buf].modifiable = true
  end
end

-- Re-enable markdown highlighting after updates
function M.enable_highlighting()
  if M.state.display_buf and vim.api.nvim_buf_is_valid(M.state.display_buf) then
    -- Re-enable treesitter for markdown highlighting
    pcall(vim.treesitter.start, M.state.display_buf)
  end
end

function M.render()
  if not M.state.display_buf or not vim.api.nvim_buf_is_valid(M.state.display_buf) then
    return
  end

  local lines = {}

  -- Add header
  table.insert(lines, '# Todo-AI Chat')
  table.insert(lines, '')
  table.insert(lines, '---')
  table.insert(lines, '')

  -- Add messages
  for _, msg in ipairs(M.state.messages) do
    local prefix = msg.role == 'user' and '**You**' or '**AI**'
    local timestamp = ' _(' .. msg.timestamp .. ')_'

    table.insert(lines, prefix .. timestamp .. ':')
    table.insert(lines, '')

    -- Split content into lines and indent
    local content = msg.content or ""
    local content_lines = vim.split(content, '\n')
    for _, line in ipairs(content_lines) do
      table.insert(lines, line)
    end

    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '')
  end

  -- Add input section
  table.insert(lines, '')
  table.insert(lines, '## Your message:')
  table.insert(lines, '')
  -- Add placeholder for user input (this line will be editable)
  table.insert(lines, '')  -- This is the input line - always empty after render

  -- Reset the last input line tracker when re-rendering
  M.state.last_input_line = ""

  -- Update buffer using lock/unlock pattern like codecompanion
  M.unlock_buffer()
  vim.api.nvim_buf_set_lines(M.state.display_buf, 0, -1, false, lines)
  -- Re-enable highlighting after update
  M.enable_highlighting()
  -- Keep unlocked for user editing

  -- Mark buffer as not modified since this is just a display
  vim.bo[M.state.display_buf].modified = false

  -- Ensure we stay in normal mode unless user is actively editing
  local current_win = vim.api.nvim_get_current_win()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    if current_win ~= M.state.win then
      -- If chat window is not focused, ensure it's in normal mode
      vim.cmd('stopinsert')
    end
    -- Scroll to bottom (ensure valid position)
    if M.state.display_buf and vim.api.nvim_buf_is_valid(M.state.display_buf) then
      local line_count = vim.api.nvim_buf_line_count(M.state.display_buf)
      if line_count > 0 then
        -- Use pcall to handle any edge cases with cursor positioning
        pcall(vim.api.nvim_win_set_cursor, M.state.win, {line_count, 0})
      end
    end
  end
end

function M.send_to_backend(message)
  local unified_prompt = require('todo-ai.unified_prompt')
  local target_buf = unified_prompt.find_target_buffer()

  -- Build conversation history with smart limits
  local config = require('todo-ai.config')
  local conv_config = config.get('conversation') or {}

  local conversation_history = {}
  local total_chars = 0
  local max_total_chars = conv_config.max_total_chars or 50000  -- ~12k tokens
  local max_messages = conv_config.max_messages or 20            -- 10 exchanges
  local max_msg_length = conv_config.max_message_length or 4000  -- Per message limit

  -- Process messages in reverse to prioritize recent context
  local messages_to_process = {}
  for i = #M.state.messages, 1, -1 do
    local msg = M.state.messages[i]
    if msg.role and msg.content and not msg.is_thinking then
      table.insert(messages_to_process, 1, msg)
      if #messages_to_process >= max_messages then
        break
      end
    end
  end

  -- Build history with size limits
  for _, msg in ipairs(messages_to_process) do
    -- Convert our internal roles to standard LLM roles
    local role = msg.role
    if role == 'ai' then
      role = 'assistant'
    end

    if role == 'user' or role == 'assistant' then
      local content = msg.content

      -- Truncate very long messages (like file dumps)
      if #content > max_msg_length then
        content = content:sub(1, max_msg_length) .. "\n\n[... truncated for context limit ...]"
      end

      -- Check total size limit
      if total_chars + #content > max_total_chars then
        -- If we're close to limit, add a summary message and stop
        if #conversation_history > 0 then
          table.insert(conversation_history, 1, {
            role = 'system',
            content = string.format('[Previous %d messages truncated due to context limits]',
              #messages_to_process - #conversation_history)
          })
        end
        break
      end

      table.insert(conversation_history, {
        role = role,
        content = content
      })
      total_chars = total_chars + #content
    end
  end

  unified_prompt.process({
    instruction = message,
    bufnr = target_buf,
    conversation_history = conversation_history
  })
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

-- Clear conversation history (new session)
function M.clear_history()
  M.state.messages = {}
  M.add_message('system', '🔄 Conversation history cleared. Starting fresh!')
  M.render()
end

function M.show_thinking(model_name)
  -- Check if we already have a thinking message
  if M.state.thinking_timer then
    -- Already showing thinking, don't add another
    return
  end

  -- Get model name from config if not provided
  local config = require('todo-ai.config')
  local model = model_name or config.get('model') or 'AI'

  -- Add thinking message only if there isn't one already
  local last_msg = M.state.messages[#M.state.messages]
  if not (last_msg and last_msg.is_thinking) then
    -- Show thinking animation
    local content = M.thinking_frames[1]
    table.insert(M.state.messages, {
      role = 'ai',
      content = content,
      timestamp = os.date('%H:%M'),
      is_thinking = true,
      model_name = model  -- Store for animation updates
    })
    M.render()  -- Full render for new message
  end

  -- Start animation timer with slower speed to reduce flicker (1000ms)
  M.state.thinking_frame = 1
  M.state.thinking_timer = vim.fn.timer_start(1000, function()
    if M.state.messages[#M.state.messages] and M.state.messages[#M.state.messages].is_thinking then
      M.state.thinking_frame = M.state.thinking_frame + 1
      if M.state.thinking_frame > #M.thinking_frames then
        M.state.thinking_frame = 1
      end
      -- Update thinking animation
      local thinking_msg = M.state.messages[#M.state.messages]
      thinking_msg.content = M.thinking_frames[M.state.thinking_frame]
      M.update_thinking_line()  -- Efficient update just for the thinking line
    end
  end, {['repeat'] = -1})
end

function M.update_thinking_line()
  -- More efficient update - just update the thinking message line
  if not M.state.display_buf or not vim.api.nvim_buf_is_valid(M.state.display_buf) then
    return
  end

  -- Only update if chat window is not currently focused to avoid disrupting editing
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    local current_win = vim.api.nvim_get_current_win()
    if current_win == M.state.win then
      -- User is actively editing in chat window, skip update to prevent cursor jumping
      return
    end
  end

  -- Find the last AI message line in the buffer
  local lines = vim.api.nvim_buf_get_lines(M.state.display_buf, 0, -1, false)
  local thinking_msg = M.state.messages[#M.state.messages]

  if thinking_msg and thinking_msg.is_thinking then
    -- Find where the last message starts (look for the AI timestamp pattern)
    local ai_line = -1
    for i = #lines, 1, -1 do
      if lines[i]:match("^%*%*AI%*%*.*:$") then
        ai_line = i
        break
      end
    end

    if ai_line > 0 then
      -- Split content into lines (thinking animation + model name)
      local content_lines = vim.split(thinking_msg.content, '\n')

      -- Update the content lines after the header
      -- Only update the thinking animation line (skip the blank line after header)
      -- ai_line is "**AI** _(timestamp):"
      -- ai_line + 1 is blank line
      -- ai_line + 2 is the thinking animation
      local thinking_line_idx = ai_line + 2
      if thinking_line_idx <= #lines then
        -- Store current buffer state to avoid flicker
        local was_modifiable = vim.bo[M.state.display_buf].modifiable

        -- Make buffer modifiable without triggering treesitter restart
        vim.bo[M.state.display_buf].modifiable = true

        -- Only replace the single thinking line
        vim.api.nvim_buf_set_lines(M.state.display_buf, thinking_line_idx - 1, thinking_line_idx, false, content_lines)

        -- Restore original modifiable state
        vim.bo[M.state.display_buf].modifiable = was_modifiable
      end
    end
  end
end

function M.hide_thinking()
  -- Stop animation timer
  if M.state.thinking_timer then
    vim.fn.timer_stop(M.state.thinking_timer)
    M.state.thinking_timer = nil
  end

  -- Remove thinking message
  if M.state.messages[#M.state.messages] and M.state.messages[#M.state.messages].is_thinking then
    table.remove(M.state.messages)
    M.render()
  end
end

function M.get_open_buffers_context()
  local buffers = {}

  -- Get all listed buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)
      -- Skip special buffers and the chat buffer itself
      if name ~= '' and not name:match('^Todo%-AI Chat') and bufnr ~= M.state.display_buf then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local filetype = vim.bo[bufnr].filetype

        -- For conversational mode, we'll send more context
        -- Include full content for small files, first 200 lines for large files
        local content_lines = {}
        local line_limit = #lines <= 300 and #lines or 200
        for i = 1, math.min(#lines, line_limit) do
          table.insert(content_lines, lines[i])
        end

        -- Extract key information from the file
        local has_todos = false
        local function_count = 0
        local class_count = 0

        for _, line in ipairs(lines) do
          if line:match('TODO') or line:match('FIXME') then
            has_todos = true
          end
          if line:match('^%s*def ') or line:match('^%s*function ') then
            function_count = function_count + 1
          end
          if line:match('^%s*class ') then
            class_count = class_count + 1
          end
        end

        table.insert(buffers, {
          id = bufnr,
          path = name,
          filename = vim.fn.fnamemodify(name, ':t'),
          filetype = filetype,
          content = table.concat(content_lines, '\n'),
          line_count = #lines,
          modified = vim.bo[bufnr].modified,
          has_todos = has_todos,
          function_count = function_count,
          class_count = class_count
        })
      end
    end
  end

  return buffers
end

function M.apply_edit(buffer_id, line_start, line_end, new_content)
  -- Apply an edit to a buffer
  if not vim.api.nvim_buf_is_valid(buffer_id) then
    return false, "Invalid buffer"
  end

  -- Switch to the buffer being edited
  -- Find a window showing this buffer or create one
  local found_window = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buffer_id then
      vim.api.nvim_set_current_win(win)
      found_window = true
      break
    end
  end

  -- If buffer not visible, open it in current window (not the chat window)
  if not found_window then
    -- Find a non-chat window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= M.state.win then
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_buf(win, buffer_id)
        break
      end
    end
  end

  -- Clean any markdown formatting from the content
  local cleaned_content = new_content:gsub('^```[^\n]*\n', ''):gsub('\n```$', '')

  -- Convert new_content string to lines
  local new_lines = vim.split(cleaned_content, '\n')

  -- Apply the edit
  vim.api.nvim_buf_set_lines(buffer_id, line_start - 1, line_end, false, new_lines)

  -- Highlight the changed lines briefly
  local ns_id = vim.api.nvim_create_namespace('todo_ai_edit')
  for i = 0, #new_lines - 1 do
    vim.api.nvim_buf_add_highlight(buffer_id, ns_id, 'DiffAdd', line_start - 1 + i, 0, -1)
  end

  -- Clear highlight after 2 seconds
  vim.defer_fn(function()
    vim.api.nvim_buf_clear_namespace(buffer_id, ns_id, 0, -1)
  end, 2000)

  return true, "Edit applied"
end

function M.process_edit_commands(content)
  -- Clear previous edit queue
  M.state.edit_queue = {}
  M.state.current_edit_index = 0

  -- Look for EDIT commands in the format: EDIT[buffer_id:line_start-line_end]: content
  local pattern = "EDIT%[(%d+):(%d+)%-(%d+)%]:"
  local lines = vim.split(content, '\n')

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local buffer_id, line_start, line_end = line:match("EDIT%[(%d+):(%d+)%-(%d+)%]:")

    if buffer_id then
      buffer_id = tonumber(buffer_id)
      line_start = tonumber(line_start)
      line_end = tonumber(line_end)

      -- Collect edit content
      local edit_lines = {}
      local inline_content = line:match("EDIT%[%d+:%d+%-%d+%]:%s*(.+)")
      if inline_content then
        table.insert(edit_lines, inline_content)
      end

      -- Collect subsequent lines until next EDIT or code block end
      i = i + 1
      while i <= #lines do
        if lines[i]:match("^EDIT%[") or lines[i]:match("^```") or lines[i] == "" then
          break
        end
        table.insert(edit_lines, lines[i])
        i = i + 1
      end

      -- Get buffer info
      local buffer_name = "Unknown"
      if vim.api.nvim_buf_is_valid(buffer_id) then
        buffer_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer_id), ':t')
        if buffer_name == "" then
          buffer_name = "Buffer #" .. buffer_id
        end
      end

      -- Add to edit queue
      table.insert(M.state.edit_queue, {
        buffer_id = buffer_id,
        buffer_name = buffer_name,
        line_start = line_start,
        line_end = line_end,
        content = table.concat(edit_lines, '\n'),
        status = 'pending'  -- 'pending', 'applied', 'rejected'
      })
    else
      i = i + 1
    end
  end

  -- If we have edits, show the first one
  if #M.state.edit_queue > 0 then
    M.show_next_edit()
  end
end

function M.show_next_edit()
  -- Find next pending edit
  local next_edit = nil
  local next_index = nil

  for i = M.state.current_edit_index + 1, #M.state.edit_queue do
    if M.state.edit_queue[i].status == 'pending' then
      next_edit = M.state.edit_queue[i]
      next_index = i
      break
    end
  end

  if not next_edit then
    -- Check if there are any pending edits at all
    local has_pending = false
    for _, edit in ipairs(M.state.edit_queue) do
      if edit.status == 'pending' then
        has_pending = true
        break
      end
    end

    if not has_pending then
      vim.notify('All edits have been processed!', vim.log.levels.INFO)
      M.clear_edit_status()
      return
    end

    -- Wrap around to beginning
    for i = 1, M.state.current_edit_index do
      if M.state.edit_queue[i].status == 'pending' then
        next_edit = M.state.edit_queue[i]
        next_index = i
        break
      end
    end
  end

  if next_edit then
    M.state.current_edit_index = next_index
    M.preview_edit(next_edit)
  end
end

function M.preview_edit(edit)
  -- Switch to the buffer
  if not vim.api.nvim_buf_is_valid(edit.buffer_id) then
    vim.notify('Buffer #' .. edit.buffer_id .. ' is no longer valid', vim.log.levels.ERROR)
    edit.status = 'rejected'
    M.show_next_edit()
    return
  end

  -- Find or create window for the buffer
  local found_window = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == edit.buffer_id and win ~= M.state.win then
      vim.api.nvim_set_current_win(win)
      found_window = true
      break
    end
  end

  if not found_window then
    -- Find a non-chat window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= M.state.win then
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_buf(win, edit.buffer_id)
        break
      end
    end
  end

  -- Get current lines
  local lines = vim.api.nvim_buf_get_lines(edit.buffer_id, 0, -1, false)
  local original_lines = {}
  for i = edit.line_start, edit.line_end do
    if lines[i] then
      table.insert(original_lines, lines[i])
    end
  end

  -- Apply preview
  local new_lines = vim.split(edit.content, '\n')
  vim.api.nvim_buf_set_lines(edit.buffer_id, edit.line_start - 1, edit.line_end, false, new_lines)

  -- Highlight the changes
  local ns_id = vim.api.nvim_create_namespace('todo_ai_edit_preview')
  vim.api.nvim_buf_clear_namespace(edit.buffer_id, ns_id, 0, -1)
  for i = 0, #new_lines - 1 do
    vim.api.nvim_buf_add_highlight(edit.buffer_id, ns_id, 'DiffAdd', edit.line_start - 1 + i, 0, -1)
  end

  -- Move cursor to the edit
  vim.api.nvim_win_set_cursor(0, {edit.line_start, 0})

  -- Store original for reverting
  edit.original_lines = original_lines

  -- Show edit status
  M.show_edit_status()
end

function M.show_edit_status()
  local current = M.state.edit_queue[M.state.current_edit_index]
  if not current then return end

  -- Count pending edits
  local pending_count = 0
  for _, edit in ipairs(M.state.edit_queue) do
    if edit.status == 'pending' then
      pending_count = pending_count + 1
    end
  end

  -- Create status message
  local status_lines = {
    string.format('📝 Edit %d of %d pending edits', M.state.current_edit_index, #M.state.edit_queue),
    string.format('File: %s, Lines: %d-%d', current.buffer_name, current.line_start, current.line_end),
    '',
    'Press <leader>ea to accept | <leader>er to reject | <leader>en for next edit',
    string.format('(%d edits remaining)', pending_count)
  }

  -- Show as virtual text at top of buffer
  local ns_id = vim.api.nvim_create_namespace('todo_ai_edit_status')
  vim.api.nvim_buf_clear_namespace(current.buffer_id, ns_id, 0, -1)

  for i, line in ipairs(status_lines) do
    vim.api.nvim_buf_set_extmark(current.buffer_id, ns_id, 0, 0, {
      virt_lines = {{
        {line, i == 1 and 'Title' or (i == 4 and 'Comment' or 'Normal')}
      }},
      virt_lines_above = true,
      priority = 100
    })
  end
end

function M.accept_current_edit()
  local edit = M.state.edit_queue[M.state.current_edit_index]
  if not edit or edit.status ~= 'pending' then
    vim.notify('No pending edit to accept', vim.log.levels.WARN)
    return
  end

  -- Mark as applied
  edit.status = 'applied'

  -- Clear highlights
  local ns_id = vim.api.nvim_create_namespace('todo_ai_edit_preview')
  vim.api.nvim_buf_clear_namespace(edit.buffer_id, ns_id, 0, -1)

  vim.notify(string.format('✓ Applied edit to %s', edit.buffer_name), vim.log.levels.INFO)

  -- Show next edit
  M.show_next_edit()
end

function M.reject_current_edit()
  local edit = M.state.edit_queue[M.state.current_edit_index]
  if not edit or edit.status ~= 'pending' then
    vim.notify('No pending edit to reject', vim.log.levels.WARN)
    return
  end

  -- Revert changes if we have original lines
  if edit.original_lines and vim.api.nvim_buf_is_valid(edit.buffer_id) then
    vim.api.nvim_buf_set_lines(edit.buffer_id, edit.line_start - 1, edit.line_start - 1 + #vim.split(edit.content, '\n'), false, edit.original_lines)
  end

  -- Mark as rejected
  edit.status = 'rejected'

  -- Clear highlights
  local ns_id = vim.api.nvim_create_namespace('todo_ai_edit_preview')
  vim.api.nvim_buf_clear_namespace(edit.buffer_id, ns_id, 0, -1)

  vim.notify(string.format('✗ Rejected edit to %s', edit.buffer_name), vim.log.levels.INFO)

  -- Show next edit
  M.show_next_edit()
end

function M.clear_edit_status()
  -- Clear status display from all buffers
  local ns_id = vim.api.nvim_create_namespace('todo_ai_edit_status')
  for _, edit in ipairs(M.state.edit_queue) do
    if vim.api.nvim_buf_is_valid(edit.buffer_id) then
      vim.api.nvim_buf_clear_namespace(edit.buffer_id, ns_id, 0, -1)
    end
  end
end

function M.queue_changes(target_buf, changes, explanation)
  -- Queue and display changes for review
  local diff = require('todo-ai.diff_native')
  local init = require('todo-ai.init')

  -- If single change, show standard diff
  if #changes == 1 then
    local change = changes[1]
    init.state.pending_diff = {
      changes = changes,
      explanation = explanation,
      is_multi_change = false
    }
  else
    -- Multiple changes - show multi-diff view
    diff.show_multi_changes(target_buf, changes, explanation)
    init.state.pending_diff = {
      changes = changes,
      explanation = explanation,
      is_multi_change = true
    }
  end
end

function M.create_new_file(filename, content)
  -- Create new buffer
  local new_buf = vim.api.nvim_create_buf(true, false)  -- listed, not scratch

  -- Set the buffer name
  local full_path = filename
  if not filename:match('^/') then
    -- Relative path, make it absolute
    full_path = vim.fn.getcwd() .. '/' .. filename
  end

  vim.api.nvim_buf_set_name(new_buf, full_path)

  -- Set the content
  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, lines)

  -- Open in a new window (split)
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, new_buf)

  -- Set filetype based on extension
  local ext = filename:match('%.([^%.]+)$')
  if ext then
    local filetype_map = {
      py = 'python',
      js = 'javascript',
      ts = 'typescript',
      jsx = 'javascript',
      tsx = 'typescript',
      lua = 'lua',
      rs = 'rust',
      go = 'go',
      java = 'java',
      c = 'c',
      cpp = 'cpp',
      h = 'c',
      hpp = 'cpp',
      md = 'markdown',
      json = 'json',
      yaml = 'yaml',
      yml = 'yaml',
      toml = 'toml',
      sh = 'sh',
      bash = 'bash',
      zsh = 'zsh',
      vim = 'vim',
    }
    local ft = filetype_map[ext] or ext
    vim.bo[new_buf].filetype = ft
  end

  -- Mark as modified so user knows to save
  vim.bo[new_buf].modified = true

  M.add_message('system', string.format('✨ Created new file: %s\n💾 Use :w to save to disk', full_path))

  return new_buf
end

return M