local M = {}
local config = require('todo-ai.config')

M.state = {
  tmux_pane = nil,
}

local severity_map = {
  [1] = 'ERROR', [2] = 'WARN', [3] = 'INFO', [4] = 'HINT',
}

function M.setup(opts)
  config.setup(opts or {})

  vim.o.autoread = true
  vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
    group = vim.api.nvim_create_augroup('TodoAI', { clear = true }),
    callback = function() vim.cmd('silent! checktime') end,
  })

  local hl = config.get('ai_highlight')
  if hl and hl.enabled then
    vim.api.nvim_set_hl(0, 'TodoAI', { fg = hl.fg, bg = hl.bg, bold = hl.bold })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'TextChanged', 'TextChangedI' }, {
      group = vim.api.nvim_create_augroup('TodoAI_Highlight', { clear = true }),
      pattern = '*',
      callback = function()
        pcall(vim.fn.matchadd, 'TodoAI', '@ai.*', 10, -1)
      end,
    })
  end
end

-- Tmux pane management --------------------------------------------------------

function M._in_tmux()
  return os.getenv('TMUX') ~= nil
end

function M._is_pane_alive()
  if not M.state.tmux_pane then return false end
  local panes = vim.fn.system("tmux list-panes -a -F '#{pane_id}'")
  return panes:find(M.state.tmux_pane, 1, true) ~= nil
end

function M._extension_path()
  local source = debug.getinfo(1, 'S').source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source, ':h:h:h')
  return plugin_root .. '/extension/neovim.ts'
end

function M._build_cmd(initial_prompt)
  local cmd = { 'pi' }
  local cfg = config.config

  if cfg.pi_provider then
    table.insert(cmd, '--provider')
    table.insert(cmd, cfg.pi_provider)
  end
  if cfg.pi_model then
    table.insert(cmd, '--model')
    table.insert(cmd, cfg.pi_model)
  end
  if cfg.pi_thinking then
    table.insert(cmd, '--thinking')
    table.insert(cmd, cfg.pi_thinking)
  end

  table.insert(cmd, '-e')
  table.insert(cmd, M._extension_path())
  table.insert(cmd, '--resume')

  if cfg.pi_extra_args then
    for _, arg in ipairs(cfg.pi_extra_args) do
      table.insert(cmd, arg)
    end
  end

  if initial_prompt then
    table.insert(cmd, initial_prompt)
  end

  return cmd
end

function M.open_pi(initial_prompt)
  if not M._in_tmux() then
    error('todo-ai requires tmux. Start Neovim inside a tmux session.')
  end

  if M._is_pane_alive() then
    if initial_prompt then
      M.send_prompt(initial_prompt)
    end
    return
  end

  local cmd = M._build_cmd(initial_prompt)
  local socket = vim.v.servername
  local width = config.get('pi_width') or 80

  -- env NVIM=<socket> pi [args...]
  local parts = { 'env', 'NVIM=' .. socket }
  for _, arg in ipairs(cmd) do
    table.insert(parts, arg)
  end
  local shell_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, parts), ' ')

  local result = vim.fn.system({
    'tmux', 'split-window', '-h', '-l', tostring(width),
    '-P', '-F', '#{pane_id}',
    shell_cmd,
  })
  M.state.tmux_pane = vim.trim(result)
end

function M.send_prompt(text)
  if not M._is_pane_alive() then
    M.open_pi(text)
    return
  end
  local tmpfile = '/tmp/todo-ai-prompt-' .. vim.fn.getpid() .. '.md'
  local f = io.open(tmpfile, 'w')
  if not f then error('Failed to write ' .. tmpfile) end
  f:write(text)
  f:close()
  vim.fn.system({
    'tmux', 'send-keys', '-t', M.state.tmux_pane,
    '/nvim ' .. tmpfile, 'Enter',
  })
end

function M.focus_pi()
  if M._is_pane_alive() then
    vim.fn.system({ 'tmux', 'select-pane', '-t', M.state.tmux_pane })
  else
    M.open_pi()
  end
end

-- Remote functions (called by pi extension via nvim --server) -----------------

function M.remote_open(path, line)
  vim.schedule(function()
    vim.cmd('edit +' .. (line or 1) .. ' ' .. vim.fn.fnameescape(path))
  end)
end

function M.remote_diff_review()
  vim.schedule(function()
    vim.cmd('DiffviewOpen')
  end)
end

function M.remote_get_context()
  local ctx = { open_files = {} }

  -- Current window's file and cursor
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  if name ~= '' and vim.bo[buf].buftype == '' then
    ctx.current_file = name
    ctx.cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local diags = vim.diagnostic.get(buf)
    if #diags > 0 then
      ctx.diagnostics = {}
      for i, d in ipairs(diags) do
        if i > 20 then break end
        table.insert(ctx.diagnostics, {
          line = d.lnum + 1,
          severity = severity_map[d.severity] or 'UNKNOWN',
          message = d.message,
        })
      end
    end
  end

  -- All open file buffers
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '' then
      local n = vim.api.nvim_buf_get_name(b)
      if n ~= '' then
        table.insert(ctx.open_files, n)
      end
    end
  end

  return vim.fn.json_encode(ctx)
end

return M
