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

function M.create()
  -- Create display buffer for chat messages
  M.state.display_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.state.display_buf].filetype = 'markdown'
  vim.bo[M.state.display_buf].modifiable = false
  vim.bo[M.state.display_buf].buftype = 'nofile'
  vim.bo[M.state.display_buf].swapfile = false

  -- Set buffer name
  vim.api.nvim_buf_set_name(M.state.display_buf, 'Todo-AI Chat')

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

  -- Check if chat window is already open
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    -- Window exists, just focus it
    vim.api.nvim_set_current_win(M.state.win)
    return
  end

  -- Find existing chat buffer window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    if win_buf == M.state.display_buf then
      M.state.win = win
      vim.api.nvim_set_current_win(win)
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

  -- Render messages
  M.render()

  -- Set up input handling
  M.setup_input()
end

function M.setup_input()
  -- Create input area at bottom
  local buf = M.state.display_buf
  vim.api.nvim_buf_set_keymap(buf, 'n', 'i', ':lua require("todo-ai.chat").start_input()<CR>', {
    noremap = true,
    silent = true
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'a', ':lua require("todo-ai.chat").start_input()<CR>', {
    noremap = true,
    silent = true
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', ':lua require("todo-ai.chat").send_message()<CR>', {
    noremap = true,
    silent = true
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("todo-ai.chat").close()<CR>', {
    noremap = true,
    silent = true
  })
end

function M.start_input()
  -- Create a simple input prompt
  local input = vim.fn.input('Message: ')
  if input and input ~= '' then
    M.add_message('user', input)
    M.send_to_backend(input)
  end
end

function M.send_message()
  -- Alias for start_input, called when pressing Enter
  M.start_input()
end

function M.add_message(role, content)
  table.insert(M.state.messages, {
    role = role,
    content = content,
    timestamp = os.date('%H:%M')
  })
  M.render()
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

  -- Add input hint
  table.insert(lines, '')
  table.insert(lines, '_Press `i` to send a message, `q` to close_')

  -- Update buffer
  vim.bo[M.state.display_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.state.display_buf, 0, -1, false, lines)
  vim.bo[M.state.display_buf].modifiable = false

  -- Scroll to bottom
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_set_cursor(M.state.win, {#lines, 0})
  end
end

function M.send_to_backend(message)
  local providers = require('todo-ai.providers')
  local config = require('todo-ai.config')
  local init = require('todo-ai.init')

  -- Show thinking spinner with model name
  local model = config.get('model')
  M.show_thinking(model)

  -- Get provider
  local provider_name = config.get('provider')
  local provider = providers.get(provider_name)

  if not provider then
    M.hide_thinking()
    M.add_message('ai', '❌ **Error**: Provider ' .. provider_name .. ' not found')
    return
  end

  -- Gather all open buffers context
  local open_buffers = M.get_open_buffers_context()

  -- Build context for the message
  local context_info = {}
  if init.state.current_todo then
    context_info.todo = init.state.current_todo
    context_info.pending_diff = init.state.pending_diff
  end
  context_info.open_buffers = open_buffers
  context_info.current_buffer = vim.api.nvim_get_current_buf()

  -- Prepare messages for chat
  local messages = {}

  -- Add context as system message
  table.insert(messages, {
    role = 'system',
    content = 'You have access to the following open buffers: ' .. vim.fn.json_encode(context_info)
  })

  -- Add chat history
  for _, msg in ipairs(M.state.messages) do
    if not msg.is_thinking then
      table.insert(messages, {
        role = msg.role == 'ai' and 'assistant' or msg.role,
        content = msg.content
      })
    end
  end

  -- Add current message
  table.insert(messages, {
    role = 'user',
    content = message
  })

  -- Send chat request to provider
  provider.chat_async(messages, {
    model = config.get('model'),
    temperature = config.get('temperature')
  }, function(response, error)
    -- Hide thinking spinner
    M.hide_thinking()

    if error then
      M.add_message('ai', '❌ **Error**: ' .. error)
    else
      -- Check if we have formatted response with thinking
      if response.thinking_formatted then
        -- Add thinking section
        M.add_message('ai', response.thinking_formatted)
      end

      -- Add main content
      local content = response.content or ""

      -- Check for code in response
      if response.code and response.code ~= "" then
        if content == "" then
          content = "### 📄 Generated Code\n```" .. (vim.bo.filetype or "") .. "\n" .. response.code .. "\n```"
        end
      end

      -- Add explanation if present
      if response.explanation and response.explanation ~= "" and response.explanation ~= "Generated code" then
        if content ~= "" then
          content = content .. "\n\n"
        end
        content = content .. "### 💬 Explanation\n" .. response.explanation
      end

      -- If still no content, use fallback
      if content == "" then
        content = response.raw_response or "No response received"
      end

      -- Check for edit commands in the response
      M.process_edit_commands(content)

      if content ~= "" then
        M.add_message('ai', content)
      end

      -- Handle code changes based on new schema
      if response.changes and #response.changes > 0 then
        local diff = require('todo-ai.diff_native')

        -- Store current buffer for changes
        local target_buf = context_info.current_buffer

        -- Check if this is a new file creation
        if response.new_file then
          -- Create new file and apply changes
          local content = response.changes[1].code
          M.create_new_file(response.new_file, content)
        elseif response.replace_buffer then
          -- Replace entire buffer
          local full_code = response.changes[1].code
          diff.show_full_buffer(target_buf, full_code, response.explanation or "")
          init.state.pending_diff = response
          init.state.pending_diff.is_full_buffer = true
        else
          -- Apply multiple changes as edits
          M.queue_changes(target_buf, response.changes, response.explanation)
        end
      elseif response.code_snippet then
        -- Just display code snippet in chat, no buffer changes
        local snippet_display = "```" .. (vim.bo.filetype or "") .. "\n" .. response.code_snippet .. "\n```"
        if response.explanation then
          M.add_message('ai', response.explanation .. "\n\n" .. snippet_display)
        else
          M.add_message('ai', snippet_display)
        end
      end
    end
  end)
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
    -- Show thinking animation on one line, model on the next in grey
    local content = M.thinking_frames[1] .. '\n_' .. model .. '_'
    table.insert(M.state.messages, {
      role = 'ai',
      content = content,
      timestamp = os.date('%H:%M'),
      is_thinking = true,
      model_name = model  -- Store for animation updates
    })
    M.render()  -- Full render for new message
  end

  -- Start animation timer (slower at 750ms)
  M.state.thinking_frame = 1
  M.state.thinking_timer = vim.fn.timer_start(750, function()
    if M.state.messages[#M.state.messages] and M.state.messages[#M.state.messages].is_thinking then
      M.state.thinking_frame = M.state.thinking_frame + 1
      if M.state.thinking_frame > #M.thinking_frames then
        M.state.thinking_frame = 1
      end
      -- Update thinking animation but keep model name on separate line
      local thinking_msg = M.state.messages[#M.state.messages]
      local model = thinking_msg.model_name or 'AI'
      thinking_msg.content = M.thinking_frames[M.state.thinking_frame] .. '\n_' .. model .. '_'
      M.update_thinking_line()  -- Efficient update just for the thinking line
    end
  end, {['repeat'] = -1})
end

function M.update_thinking_line()
  -- More efficient update - just update the thinking message line
  if not M.state.display_buf or not vim.api.nvim_buf_is_valid(M.state.display_buf) then
    return
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
      vim.bo[M.state.display_buf].modifiable = true

      -- Figure out how many lines to replace (could be 1 or 2)
      local end_line = math.min(ai_line + 3, #lines + 1)  -- At most 2 lines after header
      vim.api.nvim_buf_set_lines(M.state.display_buf, ai_line + 1, end_line, false, content_lines)

      vim.bo[M.state.display_buf].modifiable = false

      -- Keep scroll at bottom if we were there
      if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
        local cursor = vim.api.nvim_win_get_cursor(M.state.win)
        if cursor[1] >= #lines - 5 then  -- If near bottom, stay at bottom
          vim.api.nvim_win_set_cursor(M.state.win, {vim.api.nvim_buf_line_count(M.state.display_buf), 0})
        end
      end
    else
      -- Fallback to full render if we can't find the right line
      M.render()
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

        -- Limit content size (first 100 lines for context)
        local content_lines = {}
        for i = 1, math.min(#lines, 100) do
          table.insert(content_lines, lines[i])
        end

        table.insert(buffers, {
          id = bufnr,
          path = name,
          filename = vim.fn.fnamemodify(name, ':t'),
          filetype = filetype,
          content = table.concat(content_lines, '\n'),
          line_count = #lines,
          modified = vim.bo[bufnr].modified
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