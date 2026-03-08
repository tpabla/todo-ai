-- Gather Neovim context and format it for inclusion in prompts
local M = {}

-- Get absolute paths of open buffers (excluding chat)
function M.get_open_buffer_paths()
  local paths = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' and not name:match('Todo%-AI Chat') then
        table.insert(paths, name)
      end
    end
  end
  return paths
end

-- Get LSP diagnostics for a buffer as text
function M.get_lsp_diagnostics(bufnr)
  local diagnostics = vim.diagnostic.get(bufnr)
  if #diagnostics == 0 then return nil end

  local lines = {}
  for _, diag in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[diag.severity] or "UNKNOWN"
    table.insert(lines, string.format("  Line %d: [%s] %s", diag.lnum + 1, severity, diag.message))
  end
  return table.concat(lines, '\n')
end

-- Build context text to prepend to a prompt
function M.build(opts)
  opts = opts or {}
  local parts = {}

  -- Current file
  if opts.file_path and opts.file_path ~= '' then
    table.insert(parts, string.format("Current file: %s", opts.file_path))
  end

  -- Visual selection
  if opts.selected_text then
    table.insert(parts, string.format("\nSelected text (lines %d-%d):\n```\n%s\n```",
      opts.start_line or 0, opts.end_line or 0, opts.selected_text))
  end

  -- TODO context
  if opts.todo then
    table.insert(parts, string.format("\nTODO at line %d: %s", opts.todo.line, opts.todo.instruction))
  end

  -- LSP diagnostics for current buffer
  if opts.bufnr then
    local diags = M.get_lsp_diagnostics(opts.bufnr)
    if diags then
      table.insert(parts, "\nLSP Diagnostics:\n" .. diags)
    end
  end

  -- Open buffers
  local open = M.get_open_buffer_paths()
  if #open > 0 then
    table.insert(parts, "\nOpen files:\n" .. table.concat(vim.tbl_map(function(p) return "  " .. p end, open), '\n'))
  end

  -- Project context
  local ok, context_compact = pcall(require, 'todo-ai.context_compact')
  if ok then
    local project_ctx = context_compact.get_for_prompt()
    if project_ctx and project_ctx ~= '' then
      table.insert(parts, "\nProject context:\n" .. project_ctx)
    end
  end

  if #parts == 0 then return nil end
  return table.concat(parts, '\n')
end

return M
