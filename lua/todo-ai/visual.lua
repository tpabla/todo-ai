local M = {}

local function get_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return nil end
  return {
    text = table.concat(lines, '\n'),
    start_line = start_pos[2],
    end_line = end_pos[2],
    file = vim.api.nvim_buf_get_name(0),
    filetype = vim.bo.filetype,
  }
end

function M.process()
  local sel = get_selection()
  if not sel then
    vim.notify('No text selected', vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = 'Ask: ' }, function(question)
    if not question or question == '' then return end
    local init = require('todo-ai')
    init.send(init._selection_prompt(sel, question))
  end)
end

return M
