local M = {}

-- Pattern to match TODO: @ai comments
-- Supports multiple comment styles
M.patterns = {
  -- Single-line comments
  '%-%-+%s*TODO:%s*@ai%s+(.+)',           -- Lua: -- TODO: @ai
  '//%s*TODO:%s*@ai%s+(.+)',             -- C-style: // TODO: @ai
  '#%s*TODO:%s*@ai%s+(.+)',              -- Python/Shell: # TODO: @ai
  '"%s*TODO:%s*@ai%s+(.+)',              -- Vim: " TODO: @ai
  ';%s*TODO:%s*@ai%s+(.+)',              -- Lisp/Assembly: ; TODO: @ai

  -- Multi-line comment start
  '/%*%s*TODO:%s*@ai%s+(.+)',            -- C-style: /* TODO: @ai
  '<!%-%-% %s*TODO:%s*@ai%s+(.+)',       -- HTML: <!-- TODO: @ai
  '{%-%s*TODO:%s*@ai%s+(.+)',            -- Jinja: {# TODO: @ai

  -- Language-specific
  '%%%s*TODO:%s*@ai%s+(.+)',             -- LaTeX: % TODO: @ai
  '%.%.%.%s*TODO:%s*@ai%s+(.+)',         -- Haskell: -- TODO: @ai
}

function M.find_todos(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local todos = {}

  for line_num, line in ipairs(lines) do
    local todo = M.parse_line(line, line_num)
    if todo then
      table.insert(todos, todo)
    end
  end

  return todos
end

function M.parse_line(line, line_num)
  for _, pattern in ipairs(M.patterns) do
    local instruction = line:match(pattern)
    if instruction then
      return {
        line = line_num,
        instruction = instruction:gsub('^%s+', ''):gsub('%s+$', ''),  -- Trim
        full_line = line,
        pattern = pattern
      }
    end
  end
  return nil
end

function M.find_todo_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)[1]

  return M.parse_line(line, cursor_line)
end

function M.highlight_todos(bufnr)
  local ns_id = vim.api.nvim_create_namespace('todo_ai_highlight')
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local todos = M.find_todos(bufnr)
  for _, todo in ipairs(todos) do
    -- Find the position of @ai in the line
    local start_col = todo.full_line:find('@ai')
    if start_col then
      vim.api.nvim_buf_add_highlight(
        bufnr,
        ns_id,
        'TodoAIHighlight',
        todo.line - 1,
        start_col - 1,
        -1
      )
    end
  end
end

-- Set up highlight group
vim.api.nvim_set_hl(0, 'TodoAIHighlight', { bg = '#3a3a3a', fg = '#ffcc00', bold = true })

-- Auto-highlight on buffer enter if enabled
vim.api.nvim_create_autocmd({'BufEnter', 'TextChanged', 'InsertLeave'}, {
  callback = function()
    local config = require('todo-ai.config')
    if config.get('highlight_todos') then
      M.highlight_todos(vim.api.nvim_get_current_buf())
    end
  end
})

return M