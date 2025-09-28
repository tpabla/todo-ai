local M = {}

-- Create a floating window for input
function M.create_input_window(callback)
  local width = 60
  local height = 3

  -- Calculate center position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.bo[buf].buftype = 'prompt'
  vim.bo[buf].bufhidden = 'wipe'

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Enter TODO instruction ',
    title_pos = 'center'
  })

  -- Set window options
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = false

  -- Add prompt text
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "What should the AI do with this code?",
    "",
    "> "
  })

  -- Position cursor after prompt
  vim.api.nvim_win_set_cursor(win, {3, 2})

  -- Set up keymaps
  vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>', '', {
    noremap = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local instruction = lines[3]:sub(3) -- Remove "> " prompt

      -- Close window
      vim.api.nvim_win_close(win, true)

      -- Call callback with instruction
      if instruction and instruction ~= '' then
        callback(instruction)
      end
    end
  })

  vim.api.nvim_buf_set_keymap(buf, 'i', '<Esc>', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
    end
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
    end
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
    end
  })

  -- Start insert mode
  vim.cmd('startinsert!')
end

-- Get visual selection
function M.get_visual_selection()
  -- Get selection marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  -- Get the lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil, nil, nil
  end

  -- Handle single line selection
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    -- First line: from start_col to end
    lines[1] = lines[1]:sub(start_col)
    -- Last line: from beginning to end_col
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end

  return lines, start_line, end_line
end

-- Process visual selection
function M.process_visual_selection()
  -- Get the selected text
  local selected_lines, start_line, end_line = M.get_visual_selection()

  if not selected_lines then
    vim.notify('No text selected', vim.log.levels.WARN)
    return
  end

  -- Store the original buffer before opening input window
  local original_bufnr = vim.api.nvim_get_current_buf()

  -- Create floating input window
  M.create_input_window(function(instruction)
    -- Create a virtual TODO comment at the selection
    local init = require('todo-ai.init')
    local chat = require('todo-ai.chat')

    -- Build context from selection
    local selected_text = table.concat(selected_lines, '\n')

    -- Create a todo object
    local todo = {
      instruction = instruction,
      line = start_line,
      end_line = end_line,
      selected_text = selected_text,
      is_visual = true,
      bufnr = original_bufnr  -- Store the original buffer
    }

    -- Store in state
    init.state.current_todo = todo

    -- Open chat and show processing
    init.open_chat()
    chat.add_message('user', string.format('Selected code:\n```\n%s\n```\n\nInstruction: %s', selected_text, instruction))

    -- Get model and show thinking
    local config = require('todo-ai.config')
    local model = config.get('model')
    chat.show_thinking(model)

    -- Gather context from the original buffer
    local context = init.gather_context(original_bufnr, todo)

    -- Add selected text and range to context
    context.selected_text = selected_text
    context.instruction = instruction
    context.end_line = end_line  -- Add end line for the range

    -- Get provider and process
    local providers = require('todo-ai.providers')
    local provider_name = config.get('provider')
    local provider = providers.get(provider_name)

    if not provider then
      chat.hide_thinking()
      chat.add_message('ai', 'Error: Provider ' .. provider_name .. ' not found')
      vim.notify('Error: Provider ' .. provider_name .. ' not found', vim.log.levels.ERROR)
      return
    end

    -- Build context string with selected text emphasis
    local context_str = vim.fn.json_encode(context)

    -- Request completion from provider
    provider.complete_async(instruction, context_str, {
      model = config.get('model'),
      temperature = config.get('temperature')
    }, function(response, error)
      -- Hide thinking spinner
      chat.hide_thinking()

      if error then
        chat.add_message('ai', 'Error: ' .. error)
        vim.notify('Error: ' .. error, vim.log.levels.ERROR)
        return
      end

      -- Display diff for the selected region
      if response.changes and #response.changes > 0 then
        local diff = require('todo-ai.diff')

        -- Visual selection uses changes format
        local change = response.changes[1]
        diff.show_range(original_bufnr, change.start_line or start_line, change.end_line or end_line, change.code, change.description or response.explanation)
        init.state.pending_diff = response
        init.state.pending_diff.is_visual = true
        init.state.pending_diff.start_line = start_line
        init.state.pending_diff.end_line = end_line
      end

      -- Store the target buffer filetype for proper formatting
      response.target_filetype = vim.bo[original_bufnr].filetype

      -- Add formatted response to chat
      local formatted = init.format_response(response)
      if formatted and formatted ~= '' then
        chat.add_message('ai', formatted)
      else
        -- Fallback to simple display
        if response.changes then
          chat.add_message('ai', 'Generated changes for selected lines')
        elseif response.code_snippet then
          chat.add_message('ai', 'Code example:\n```\n' .. response.code_snippet .. '\n```')
        end
        if response.explanation then
          chat.add_message('ai', response.explanation)
        end
      end
    end)
  end)
end

return M