local M = {}

-- Create a minimal floating window for input
function M.create_input_window(callback)
  local width = 50
  local height = 3  -- 3 lines for padding

  -- Calculate center position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.bo[buf].buftype = ''  -- Use normal buffer type for better control
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true

  -- Create minimal window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
    title = ' TODO: @ai ',
    title_pos = 'center'
  })

  -- Set minimal highlight groups
  vim.api.nvim_set_hl(0, 'TodoAIFloatBorder', { fg = '#ff00ff' })
  vim.api.nvim_set_hl(0, 'TodoAIFloatTitle', { fg = '#00ff9f', bold = true })

  -- Apply highlights to window
  vim.api.nvim_win_set_option(win, 'winhighlight', 'FloatBorder:TodoAIFloatBorder,NormalFloat:Normal')

  -- Set window options
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  -- Add lines with padding - middle line has the prompt
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    "> ",
    ""
  })

  -- Position cursor after prompt on middle line
  vim.api.nvim_win_set_cursor(win, {2, 2})

  -- Set up keymaps
  vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>', '', {
    noremap = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local instruction = lines[2]:sub(3) -- Remove "> " prompt from middle line

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

  -- Start insert mode in the floating window
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
    -- Use unified prompt system
    local unified_prompt = require('todo-ai.unified_prompt')
    local selected_text = table.concat(selected_lines, '\n')

    -- Ensure we're in normal mode for proper render-markdown display
    vim.cmd('stopinsert')

    -- Process through unified system
    unified_prompt.process({
      instruction = instruction,
      selected_text = selected_text,
      start_line = start_line,
      end_line = end_line,
      bufnr = original_bufnr
    })
  end)
end

return M