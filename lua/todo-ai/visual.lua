local M = {}

function M.get_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return nil end
  return {
    text = table.concat(lines, '\n'),
    start_line = start_pos[2],
    end_line = end_pos[2],
    file = vim.api.nvim_buf_get_name(0),
  }
end

function M.process()
  local sel = M.get_selection()
  if not sel then
    vim.notify('No text selected', vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = 'Instruction: ' }, function(instruction)
    if not instruction or instruction == '' then return end
    local prompt = string.format(
      'In %s (lines %d-%d):\n```\n%s\n```\n\n%s',
      sel.file, sel.start_line, sel.end_line, sel.text, instruction
    )
    require('todo-ai').open_pi(prompt)
  end)
end

return M
