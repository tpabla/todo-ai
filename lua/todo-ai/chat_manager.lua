---@class ChatManager
---@field state ChatState
---@field MAX_MESSAGES number Maximum messages to keep in memory
---@field MAX_MESSAGE_LENGTH number Maximum length per message
local M = {}

---@class ChatState
---@field messages Message[]
---@field input_buf number|nil
---@field display_buf number|nil
---@field win number|nil
---@field thinking_timer number|nil
---@field thinking_frame number
---@field thinking_line_num number|nil
---@field edit_queue Edit[]
---@field current_edit_index number
---@field edit_preview_buf number|nil
---@field message_count number
---@field total_tokens number

---@class Message
---@field role string 'user'|'ai'|'system'
---@field content string
---@field timestamp number
---@field token_estimate number

-- Constants
M.MAX_MESSAGES = 100  -- Keep last 100 messages
M.MAX_MESSAGE_LENGTH = 10000  -- 10KB per message
M.CLEANUP_THRESHOLD = 150  -- Trigger cleanup at 150 messages
M.TOKEN_LIMIT = 100000  -- Approximate token limit

-- Initialize state with proper defaults
M.state = {
  messages = {},
  input_buf = nil,
  display_buf = nil,
  win = nil,
  thinking_timer = nil,
  thinking_frame = 1,
  thinking_line_num = nil,
  edit_queue = {},
  current_edit_index = 0,
  edit_preview_buf = nil,
  message_count = 0,
  total_tokens = 0,
}

-- Thinking animation frames
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
}

---Estimate token count for a message
---@param content string
---@return number
local function estimate_tokens(content)
  -- Rough estimate: 1 token per 4 characters
  return math.ceil(#content / 4)
end

---Add a message with memory management
---@param role string
---@param content string
---@return boolean success
function M.add_message(role, content)
  -- Validate inputs
  if not role or not content then
    return false
  end

  -- Truncate if too long
  if #content > M.MAX_MESSAGE_LENGTH then
    content = content:sub(1, M.MAX_MESSAGE_LENGTH) .. "\n... (truncated)"
  end

  -- Create message
  local message = {
    role = role,
    content = content,
    timestamp = os.time(),
    token_estimate = estimate_tokens(content),
  }

  -- Add to messages
  table.insert(M.state.messages, message)
  M.state.message_count = M.state.message_count + 1
  M.state.total_tokens = M.state.total_tokens + message.token_estimate

  -- Cleanup if needed
  if M.state.message_count > M.CLEANUP_THRESHOLD then
    M.cleanup_old_messages()
  end

  -- Check token limit
  if M.state.total_tokens > M.TOKEN_LIMIT then
    M.cleanup_by_tokens()
  end

  -- Update display if exists
  if M.state.display_buf and vim.api.nvim_buf_is_valid(M.state.display_buf) then
    M.update_display()
  end

  return true
end

---Clean up old messages to prevent memory leak
function M.cleanup_old_messages()
  local utils = require('todo-ai.utils')

  -- Keep only the last MAX_MESSAGES
  if #M.state.messages > M.MAX_MESSAGES then
    local to_remove = #M.state.messages - M.MAX_MESSAGES

    -- Calculate tokens to remove
    local removed_tokens = 0
    for i = 1, to_remove do
      removed_tokens = removed_tokens + (M.state.messages[i].token_estimate or 0)
    end

    -- Remove old messages
    for i = 1, to_remove do
      table.remove(M.state.messages, 1)
    end

    M.state.message_count = #M.state.messages
    M.state.total_tokens = M.state.total_tokens - removed_tokens

    -- Log cleanup
    local logger = require('todo-ai.logger')
    logger.info("chat.cleanup", {
      removed = to_remove,
      remaining = M.state.message_count,
      tokens_freed = removed_tokens
    })
  end
end

---Clean up messages by token limit
function M.cleanup_by_tokens()
  local current_tokens = M.state.total_tokens
  local removed = 0

  -- Remove oldest messages until under limit
  while M.state.total_tokens > M.TOKEN_LIMIT * 0.8 and #M.state.messages > 10 do
    local message = table.remove(M.state.messages, 1)
    M.state.total_tokens = M.state.total_tokens - (message.token_estimate or 0)
    removed = removed + 1
  end

  if removed > 0 then
    M.state.message_count = #M.state.messages

    local logger = require('todo-ai.logger')
    logger.info("chat.token_cleanup", {
      removed_messages = removed,
      tokens_before = current_tokens,
      tokens_after = M.state.total_tokens
    })
  end
end

---Get recent messages for context (with token limit)
---@param max_tokens number|nil
---@return Message[]
function M.get_recent_messages(max_tokens)
  max_tokens = max_tokens or 10000

  local messages = {}
  local token_count = 0

  -- Start from most recent
  for i = #M.state.messages, 1, -1 do
    local msg = M.state.messages[i]
    local msg_tokens = msg.token_estimate or estimate_tokens(msg.content)

    if token_count + msg_tokens > max_tokens then
      break
    end

    table.insert(messages, 1, msg)  -- Insert at beginning
    token_count = token_count + msg_tokens
  end

  return messages
end

---Update display buffer efficiently
function M.update_display()
  if not M.state.display_buf or not vim.api.nvim_buf_is_valid(M.state.display_buf) then
    return
  end

  -- Get visible messages only
  local win_height = 50  -- Default window height
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    win_height = vim.api.nvim_win_get_height(M.state.win)
  end

  -- Render only visible messages
  local lines = M.render_messages(win_height * 2)  -- Render 2x height for scrolling

  -- Update buffer
  vim.api.nvim_buf_set_option(M.state.display_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.display_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.display_buf, 'modifiable', false)
end

---Render messages to lines
---@param max_lines number|nil
---@return string[]
function M.render_messages(max_lines)
  max_lines = max_lines or 1000

  local lines = {}
  local line_count = 0

  -- Add header
  table.insert(lines, "# Todo-AI Chat")
  table.insert(lines, string.format("Messages: %d | Tokens: ~%d",
    M.state.message_count, M.state.total_tokens))
  table.insert(lines, "")
  line_count = 3

  -- Render messages from most recent
  for i = #M.state.messages, 1, -1 do
    if line_count > max_lines then
      break
    end

    local msg = M.state.messages[i]
    local role_prefix = msg.role == 'user' and '👤 You' or '🤖 AI'

    table.insert(lines, string.format("### %s", role_prefix))

    -- Split content into lines
    for line in msg.content:gmatch("[^\r\n]+") do
      table.insert(lines, line)
      line_count = line_count + 1

      if line_count > max_lines then
        break
      end
    end

    table.insert(lines, "")
    line_count = line_count + 2
  end

  return lines
end

---Show thinking animation
---@param model string|nil
function M.show_thinking(model)
  if M.state.thinking_timer then
    M.hide_thinking()
  end

  -- Add thinking message
  local thinking_msg = model and string.format('`🤔 Asking %s...`', model) or '`🤔 Thinking...`'
  M.add_message('system', thinking_msg)
  M.state.thinking_line_num = #M.state.messages

  -- Start animation
  M.state.thinking_timer = vim.fn.timer_start(200, function()
    if M.state.thinking_line_num and M.state.display_buf and
       vim.api.nvim_buf_is_valid(M.state.display_buf) then

      M.state.thinking_frame = (M.state.thinking_frame % #M.thinking_frames) + 1

      -- Update thinking message
      if M.state.messages[M.state.thinking_line_num] then
        M.state.messages[M.state.thinking_line_num].content = M.thinking_frames[M.state.thinking_frame]
        M.update_display()
      end
    end
  end, {['repeat'] = -1})
end

---Hide thinking animation
function M.hide_thinking()
  if M.state.thinking_timer then
    vim.fn.timer_stop(M.state.thinking_timer)
    M.state.thinking_timer = nil
  end

  -- Remove thinking message
  if M.state.thinking_line_num and M.state.messages[M.state.thinking_line_num] then
    if M.state.messages[M.state.thinking_line_num].content:match('Thinking') or
       M.state.messages[M.state.thinking_line_num].content:match('Processing') or
       M.state.messages[M.state.thinking_line_num].content:match('Analyzing') or
       M.state.messages[M.state.thinking_line_num].content:match('Asking') then
      table.remove(M.state.messages, M.state.thinking_line_num)
      M.state.message_count = M.state.message_count - 1
    end
  end

  M.state.thinking_line_num = nil
  M.update_display()
end

---Clear all messages and reset state
function M.clear()
  -- Stop any running timers
  if M.state.thinking_timer then
    vim.fn.timer_stop(M.state.thinking_timer)
  end

  -- Close buffers and windows
  local utils = require('todo-ai.utils')
  utils.cleanup({
    {type = 'buffer', id = M.state.input_buf},
    {type = 'buffer', id = M.state.display_buf},
    {type = 'buffer', id = M.state.edit_preview_buf},
    {type = 'window', id = M.state.win},
  })

  -- Reset state
  M.state = {
    messages = {},
    input_buf = nil,
    display_buf = nil,
    win = nil,
    thinking_timer = nil,
    thinking_frame = 1,
    thinking_line_num = nil,
    edit_queue = {},
    current_edit_index = 0,
    edit_preview_buf = nil,
    message_count = 0,
    total_tokens = 0,
  }
end

---Get memory usage stats
---@return table
function M.get_stats()
  return {
    message_count = M.state.message_count,
    total_tokens = M.state.total_tokens,
    memory_usage = collectgarbage("count") * 1024,  -- In bytes
    max_messages = M.MAX_MESSAGES,
    token_limit = M.TOKEN_LIMIT,
  }
end

return M