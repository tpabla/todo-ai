local M = {}

-- Create a minimal floating window for input
function M.create_input_window(callback)
  local width = 50
  local height = 3

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = ''
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true

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

  vim.cmd('startinsert')

  -- Submit on Enter
  vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>', '', {
    noremap = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local input = vim.trim(table.concat(lines, ' '))
      vim.api.nvim_win_close(win, true)
      vim.cmd('stopinsert')
      if input ~= '' then
        callback(input)
      end
    end
  })

  -- Cancel on Escape
  vim.api.nvim_buf_set_keymap(buf, 'i', '<Esc>', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
      vim.cmd('stopinsert')
    end
  })
end

function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then return nil end

  -- Trim to selection columns
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end

  return lines, start_line, end_line
end

function M.process_visual_selection()
  local selected_lines, start_line, end_line = M.get_visual_selection()

  if not selected_lines then
    vim.notify('No text selected', vim.log.levels.WARN)
    return
  end

  local original_bufnr = vim.api.nvim_get_current_buf()

  M.create_input_window(function(instruction)
    local pi = require('todo-ai.pi_client')
    local ctx = require('todo-ai.context')
    local chat = require('todo-ai.chat')
    local init = require('todo-ai.init')

    local selected_text = table.concat(selected_lines, '\n')
    local file_path = vim.api.nvim_buf_get_name(original_bufnr)

    vim.cmd('stopinsert')
    init.open_chat()

    local filename = vim.fn.fnamemodify(file_path, ':t')
    chat.add_message('user', string.format(
      "**Task:** %s\n\n**File:** %s (lines %d-%d)\n\n**Selected text:**\n```\n%s\n```",
      instruction, filename, start_line, end_line, selected_text
    ))

    local context_text = ctx.build({
      bufnr = original_bufnr,
      file_path = file_path,
      selected_text = selected_text,
      start_line = start_line,
      end_line = end_line,
    })

    local message = string.format(
      "In file %s, regarding the selected code at lines %d-%d:\n```\n%s\n```\n\n%s",
      file_path, start_line, end_line, selected_text, instruction
    )

    if context_text then
      message = "<neovim_context>\n" .. context_text .. "\n</neovim_context>\n\n" .. message
    end

    chat.show_thinking()
    pi.prompt(message)
  end)
end

return M
