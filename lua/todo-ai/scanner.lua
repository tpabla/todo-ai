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
    local todo = M.parse_line(line, line_num, lines)  -- Pass lines for multi-line support
    if todo then
      table.insert(todos, todo)
    end
  end

  return todos
end

function M.parse_line(line, line_num, all_lines)
  for _, pattern in ipairs(M.patterns) do
    local instruction = line:match(pattern)
    if instruction then
      -- Check for multi-line TODO
      local full_instruction = instruction:gsub('^%s+', ''):gsub('%s+$', '')  -- Trim

      -- If all_lines is provided, look for continuation lines
      if all_lines then
        full_instruction = M.extract_multiline_todo(all_lines, line_num, full_instruction)
      end

      return {
        line = line_num,
        instruction = full_instruction,
        full_line = line,
        pattern = pattern
      }
    end
  end
  return nil
end

function M.extract_multiline_todo(lines, start_line, initial_instruction)
  local full_instruction = initial_instruction
  local indent = lines[start_line]:match('^(%s*)')

  -- Detect comment string for the buffer
  local comment_string = vim.bo.commentstring or '// %s'
  local comment_start = comment_string:match('^(.-)%s*%%s') or '//'
  comment_start = comment_start:gsub('%s+$', '')  -- Trim trailing spaces

  -- Look for continuation lines
  local i = start_line + 1
  while i <= #lines do
    local line = lines[i]
    local line_indent = line:match('^(%s*)')

    -- Check if this is a continuation:
    -- Same indentation, starts with comment marker, doesn't have TODO or @ai
    if line_indent == indent and line:match('^%s*' .. vim.pesc(comment_start)) then
      if not line:match('TODO') and not line:match('@ai') then
        -- Extract the comment content (remove indent and comment marker)
        local content = line:gsub('^%s*' .. vim.pesc(comment_start) .. '%s*', '')
        if content and content ~= '' then
          full_instruction = full_instruction .. ' ' .. content
        end
        i = i + 1
      else
        break  -- Found another TODO, stop here
      end
    else
      break  -- Different indentation or not a comment, stop here
    end
  end

  return full_instruction:gsub('%s+', ' ')  -- Normalize whitespace
end

-- Scan entire project for TODOs
function M.scan_project()
  local todos_by_file = {}
  local total_todos = 0

  -- Get all files in the project using git ls-files if available, otherwise find
  local cmd = "git ls-files 2>/dev/null || find . -type f -name '*.lua' -o -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' 2>/dev/null"

  local handle = io.popen(cmd)
  if not handle then
    vim.notify("Failed to scan project files", vim.log.levels.ERROR)
    return todos_by_file
  end

  local files = {}
  for file in handle:lines() do
    -- Skip common directories we don't want to scan
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

  -- Scan each file for TODOs
  for _, file_path in ipairs(files) do
    local file = io.open(file_path, "r")
    if file then
      local lines = {}
      for line in file:lines() do
        table.insert(lines, line)
      end
      file:close()

      -- Parse each line for TODOs
      local file_todos = {}
      for line_num, line in ipairs(lines) do
        local todo = M.parse_line(line, line_num, lines)
        if todo then
          todo.file = file_path
          table.insert(file_todos, todo)
          total_todos = total_todos + 1
        end
      end

      if #file_todos > 0 then
        todos_by_file[file_path] = file_todos
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
    table.insert(formatted, string.format("\n📄 %s:", file_path))
    for _, todo in ipairs(todos) do
      table.insert(formatted, string.format("  Line %d: %s", todo.line, todo.instruction))
    end
  end

  return table.concat(formatted, "\n")
end

return M