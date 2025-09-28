---@class ChatVim
---@field state ChatVimState
local M = {}

---@class ChatVimState
---@field chat_buf number|nil
---@field chat_win number|nil
---@field input_start_line number
---@field is_inserting boolean
---@field conversation table[]
---@field waiting_for_response boolean

M.state = {
  chat_buf = nil,
  chat_win = nil,
  input_start_line = 0,
  is_inserting = false,
  conversation = {},
  waiting_for_response = false,
}

-- Markers
M.MARKERS = {
  INPUT = "━━━ Your Message (save buffer to send) ━━━",
  WAITING = "━━━ Waiting for response... ━━━",
  DIVIDER = "─────────────────────────────────────────",
}

---Open or focus chat window
function M.open()
  local chat_manager = require('todo-ai.chat_manager')
  local config = require('todo-ai.config_manager')

  -- Check if window exists and is valid
  if M.state.chat_win and vim.api.nvim_win_is_valid(M.state.chat_win) then
    vim.api.nvim_set_current_win(M.state.chat_win)
    return
  end

  -- Create buffer if needed
  if not M.state.chat_buf or not vim.api.nvim_buf_is_valid(M.state.chat_buf) then
    M.state.chat_buf = vim.api.nvim_create_buf(false, false)  -- Not listed, not scratch

    -- Set buffer options
    vim.api.nvim_buf_set_name(M.state.chat_buf, 'TodoAI-Chat')
    vim.api.nvim_buf_set_option(M.state.chat_buf, 'buftype', 'acwrite')
    vim.api.nvim_buf_set_option(M.state.chat_buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_option(M.state.chat_buf, 'swapfile', false)

    -- Initialize buffer content
    M.initialize_buffer()

    -- Set up autocmds
    M.setup_autocmds()
  end

  -- Open window
  local width = config.get('chat_window_width') or 80
  local height = config.get('chat_window_height') or 30

  if config.get('floating_window') then
    -- Floating window
    local ui = vim.api.nvim_list_uis()[1]
    local win_width = math.min(width, ui.width - 4)
    local win_height = math.min(height, ui.height - 4)

    M.state.chat_win = vim.api.nvim_open_win(M.state.chat_buf, true, {
      relative = 'editor',
      width = win_width,
      height = win_height,
      col = (ui.width - win_width) / 2,
      row = (ui.height - win_height) / 2,
      border = 'rounded',
      title = ' TodoAI Chat ',
      title_pos = 'center',
    })
  else
    -- Split window
    vim.cmd('vsplit')
    M.state.chat_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.state.chat_win, M.state.chat_buf)
    vim.api.nvim_win_set_width(M.state.chat_win, width)
  end

  -- Set window options
  vim.api.nvim_win_set_option(M.state.chat_win, 'wrap', true)
  vim.api.nvim_win_set_option(M.state.chat_win, 'linebreak', true)
  vim.api.nvim_win_set_option(M.state.chat_win, 'number', false)
  vim.api.nvim_win_set_option(M.state.chat_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(M.state.chat_win, 'signcolumn', 'no')

  -- Move cursor to input area
  M.move_to_input()

  -- Set up keybindings
  M.setup_keybindings()
end

---Initialize buffer content
function M.initialize_buffer()
  local lines = {
    "# TodoAI Chat",
    "",
    "Commands:",
    "  • :w or <C-s>  - Send message",
    "  • <C-c>        - Cancel/Clear input",
    "  • <C-d>        - Clear conversation",
    "  • <C-n>        - New conversation",
    "  • q            - Close chat",
    "",
    M.MARKERS.DIVIDER,
    "",
  }

  -- Add existing conversation
  for _, msg in ipairs(M.state.conversation) do
    M.add_message_to_buffer(lines, msg.role, msg.content)
  end

  -- Add input area
  table.insert(lines, M.MARKERS.INPUT)
  table.insert(lines, "")
  table.insert(lines, "")  -- Input area

  M.state.input_start_line = #lines

  vim.api.nvim_buf_set_lines(M.state.chat_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.chat_buf, 'modified', false)
end

---Add message to buffer lines
---@param lines string[]
---@param role string
---@param content string
function M.add_message_to_buffer(lines, role, content)
  local prefix = role == 'user' and '### 👤 You' or '### 🤖 AI'

  table.insert(lines, prefix)
  table.insert(lines, "")

  -- Add content lines
  for line in content:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  table.insert(lines, "")
  table.insert(lines, M.MARKERS.DIVIDER)
  table.insert(lines, "")
end

---Setup autocmds for the buffer
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('TodoAIChat', { clear = true })

  -- Handle buffer write (send message)
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = M.state.chat_buf,
    callback = function()
      M.send_message()
      return true
    end,
  })

  -- Handle buffer unload
  vim.api.nvim_create_autocmd('BufUnload', {
    group = group,
    buffer = M.state.chat_buf,
    callback = function()
      M.state.chat_buf = nil
      M.state.chat_win = nil
    end,
  })

  -- Prevent modification above input line
  vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI'}, {
    group = group,
    buffer = M.state.chat_buf,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      if cursor[1] < M.state.input_start_line - 1 then
        vim.cmd('undo')
        M.move_to_input()
      end
    end,
  })
end

---Setup keybindings
function M.setup_keybindings()
  local opts = { noremap = true, silent = true, buffer = M.state.chat_buf }

  -- Send message
  vim.keymap.set('n', '<C-s>', function() M.send_message() end, opts)

  -- Clear input
  vim.keymap.set('n', '<C-c>', function() M.clear_input() end, opts)

  -- Clear conversation
  vim.keymap.set('n', '<C-d>', function() M.clear_conversation() end, opts)

  -- New conversation
  vim.keymap.set('n', '<C-n>', function() M.new_conversation() end, opts)

  -- Close chat
  vim.keymap.set('n', 'q', function() M.close() end, opts)

  -- Navigate to input with 'i'
  vim.keymap.set('n', 'i', function()
    M.move_to_input()
    vim.cmd('startinsert')
  end, opts)

  -- Navigate to input with 'a'
  vim.keymap.set('n', 'a', function()
    M.move_to_input()
    vim.cmd('startinsert!')
  end, opts)
end

---Move cursor to input area
function M.move_to_input()
  if M.state.chat_win and vim.api.nvim_win_is_valid(M.state.chat_win) then
    local line_count = vim.api.nvim_buf_line_count(M.state.chat_buf)
    vim.api.nvim_win_set_cursor(M.state.chat_win, {math.min(M.state.input_start_line, line_count), 0})
  end
end

---Get input text
---@return string|nil
function M.get_input()
  if not M.state.chat_buf or not vim.api.nvim_buf_is_valid(M.state.chat_buf) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(M.state.chat_buf,
    M.state.input_start_line - 1, -1, false)

  -- Remove empty lines from the end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end

---Clear input area
function M.clear_input()
  if M.state.chat_buf and vim.api.nvim_buf_is_valid(M.state.chat_buf) then
    vim.api.nvim_buf_set_lines(M.state.chat_buf,
      M.state.input_start_line - 1, -1, false, {""})
    vim.api.nvim_buf_set_option(M.state.chat_buf, 'modified', false)
    M.move_to_input()
  end
end

---Send message
function M.send_message()
  if M.state.waiting_for_response then
    vim.notify("Still waiting for response...", vim.log.levels.WARN)
    return
  end

  local input = M.get_input()
  if not input or input == "" then
    vim.notify("No message to send", vim.log.levels.WARN)
    return
  end

  -- Add to conversation
  table.insert(M.state.conversation, {
    role = 'user',
    content = input,
    timestamp = os.time(),
  })

  -- Update buffer to show message was sent
  M.state.waiting_for_response = true
  M.update_buffer()

  -- Clear modified flag
  vim.api.nvim_buf_set_option(M.state.chat_buf, 'modified', false)

  -- Send to AI
  M.process_message(input)
end

---Process and send message to AI
---@param message string
function M.process_message(message)
  local chat_manager = require('todo-ai.chat_manager')
  local async_manager = require('todo-ai.async_manager')
  local config = require('todo-ai.config_manager')

  -- Add to chat manager
  chat_manager.add_message('user', message)

  -- Show thinking
  chat_manager.show_thinking(config.get('model'))

  -- Get provider and send
  local providers = require('todo-ai.providers')
  local provider = providers.get(config.get('provider'))

  if not provider then
    M.state.waiting_for_response = false
    vim.notify("Provider not configured", vim.log.levels.ERROR)
    return
  end

  -- Get context
  local context = M.build_context()

  -- Send with rate limiting
  async_manager.rate_limited_request(
    config.get('provider'),
    function(callback)
      provider.chat_async(
        chat_manager.get_recent_messages(8000),  -- Recent messages with token limit
        {
          model = config.get('model'),
          temperature = config.get('temperature'),
          max_tokens = config.get('max_tokens'),
        },
        callback
      )
    end,
    function(response, error)
      chat_manager.hide_thinking()
      M.state.waiting_for_response = false

      if error then
        vim.notify("Error: " .. error, vim.log.levels.ERROR)
        M.add_response("Error: " .. error)
      else
        local content = response.content or response.explanation or "No response"
        chat_manager.add_message('ai', content)
        M.add_response(content)

        -- Handle code changes if present
        if response.changes then
          M.handle_code_changes(response.changes)
        end
      end
    end
  )
end

---Build context for message
---@return table
function M.build_context()
  local context_module = require('todo-ai.context_compact')
  local project_context = context_module.get_for_prompt()

  return {
    project_context = project_context,
    current_buffer = vim.api.nvim_get_current_buf(),
    current_file = vim.api.nvim_buf_get_name(0),
    filetype = vim.bo.filetype,
  }
end

---Add AI response
---@param content string
function M.add_response(content)
  table.insert(M.state.conversation, {
    role = 'ai',
    content = content,
    timestamp = os.time(),
  })

  M.update_buffer()
  M.clear_input()
end

---Update buffer with current conversation
function M.update_buffer()
  local lines = {
    "# TodoAI Chat",
    "",
    "Commands: :w (send) | <C-c> (clear) | <C-d> (reset) | q (close)",
    "",
    M.MARKERS.DIVIDER,
    "",
  }

  -- Add conversation
  for _, msg in ipairs(M.state.conversation) do
    M.add_message_to_buffer(lines, msg.role, msg.content)
  end

  -- Add input area or waiting message
  if M.state.waiting_for_response then
    table.insert(lines, M.MARKERS.WAITING)
  else
    table.insert(lines, M.MARKERS.INPUT)
    table.insert(lines, "")
    -- Preserve current input if any
    local current_input = M.get_input()
    if current_input and current_input ~= "" then
      for line in current_input:gmatch("[^\r\n]+") do
        table.insert(lines, line)
      end
    end
  end

  M.state.input_start_line = #lines

  vim.api.nvim_buf_set_option(M.state.chat_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.chat_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.chat_buf, 'modifiable', not M.state.waiting_for_response)

  -- Scroll to bottom
  if M.state.chat_win and vim.api.nvim_win_is_valid(M.state.chat_win) then
    vim.api.nvim_win_set_cursor(M.state.chat_win, {#lines, 0})
  end
end

---Handle code changes from AI
---@param changes table[]
function M.handle_code_changes(changes)
  local diff = require('todo-ai.diff')
  local init = require('todo-ai.init')

  if #changes > 0 then
    -- Show diff for first change
    local change = changes[1]
    local bufnr = vim.api.nvim_get_current_buf()

    diff.show_range(bufnr, change.start_line, change.end_line,
                   change.code, change.description)

    init.state.pending_diff = {
      changes = changes,
      is_multi_change = #changes > 1
    }

    vim.notify("Code changes ready. Use <leader>ta to accept, <leader>tr to reject",
              vim.log.levels.INFO)
  end
end

---Clear conversation
function M.clear_conversation()
  M.state.conversation = {}
  M.update_buffer()
  vim.notify("Conversation cleared", vim.log.levels.INFO)
end

---Start new conversation
function M.new_conversation()
  local chat_manager = require('todo-ai.chat_manager')
  chat_manager.clear()
  M.clear_conversation()
end

---Close chat window
function M.close()
  if M.state.chat_win and vim.api.nvim_win_is_valid(M.state.chat_win) then
    vim.api.nvim_win_close(M.state.chat_win, true)
  end
  M.state.chat_win = nil
end

return M