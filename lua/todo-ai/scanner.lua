-- TODO: @ai scanner module
-- Delegates to Rust backend (required)
local M = {}

local bridge = require('todo-ai.bridge')

function M.find_todos(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local comment_string = vim.bo[bufnr].commentstring

  local result, err = bridge.call_sync('scan_todos', {
    lines = lines,
    comment_string = comment_string,
  })
  if err then
    error('scanner.find_todos failed: ' .. err)
  end
  return result
end

function M.find_todo_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local comment_string = vim.bo[bufnr].commentstring

  local result, err = bridge.call_sync('scan_todos', {
    lines = lines,
    comment_string = comment_string,
  })
  if err then
    error('scanner.find_todo_at_cursor failed: ' .. err)
  end

  -- Find the TODO at the cursor line
  for _, todo in ipairs(result) do
    if todo.line == cursor_line then
      return todo
    end
  end
  return nil
end

-- Scan entire project for TODOs
function M.scan_project()
  local todos_by_file = {}
  local total_todos = 0

  -- Get all files in the project using git ls-files if available, otherwise find
  local cmd = "git ls-files 2>/dev/null || find . -type f -name '*.lua' -o -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' 2>/dev/null"

  local handle = io.popen(cmd)
  if not handle then
    error("Failed to scan project files")
  end

  local files = {}
  for file in handle:lines() do
    if not file:match("^%.git/") and
       not file:match("^node_modules/") and
       not file:match("^%.venv/") and
       not file:match("^vendor/") and
       not file:match("^target/") and
       not file:match("^dist/") and
       not file:match("^build/") and
       not file:match("%.min%.") then
      table.insert(files, file)
    end
  end
  handle:close()

  -- Scan each file for TODOs via Rust backend
  for _, file_path in ipairs(files) do
    local file = io.open(file_path, "r")
    if file then
      local lines = {}
      for line in file:lines() do
        table.insert(lines, line)
      end
      file:close()

      local result, err = bridge.call_sync('scan_todos', {
        lines = lines,
        comment_string = '// %s',
      })
      if result and not err and #result > 0 then
        for _, todo in ipairs(result) do
          todo.file = file_path
        end
        todos_by_file[file_path] = result
        total_todos = total_todos + #result
      end
    end
  end

  vim.notify(string.format("Found %d TODOs across %d files", total_todos, vim.tbl_count(todos_by_file)), vim.log.levels.INFO)
  return todos_by_file
end

-- Format project TODOs for context
function M.format_project_todos(todos_by_file)
  local formatted = {}

  table.insert(formatted, "=== Project-wide TODOs ===\n")

  for file_path, todos in pairs(todos_by_file) do
    table.insert(formatted, string.format("\n%s:", file_path))
    for _, todo in ipairs(todos) do
      table.insert(formatted, string.format("  Line %d: %s", todo.line, todo.instruction))
    end
  end

  return table.concat(formatted, "\n")
end

return M
