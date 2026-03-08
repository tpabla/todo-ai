local M = {}
local config = require('todo-ai.config')

M.state = {
  terminal_buf = nil,
  terminal_win = nil,
  terminal_job = nil,
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

-- Terminal management ---------------------------------------------------------

function M._is_pi_running()
  if not M.state.terminal_job or not M.state.terminal_buf then return false end
  if not vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
    M.state.terminal_job = nil
    M.state.terminal_buf = nil
    return false
  end
  return true
end

function M._ensure_visible()
  if M.state.terminal_win and vim.api.nvim_win_is_valid(M.state.terminal_win) then
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == M.state.terminal_buf then
      M.state.terminal_win = win
      return
    end
  end
  local original_win = vim.api.nvim_get_current_win()
  M._open_split()
  vim.api.nvim_win_set_buf(M.state.terminal_win, M.state.terminal_buf)
  vim.api.nvim_set_current_win(original_win)
end

function M._open_split()
  local position = config.get('pi_position') or 'right'
  local width = config.get('pi_width') or 80
  vim.cmd('vsplit')
  if position == 'right' then vim.cmd('wincmd L') else vim.cmd('wincmd H') end
  M.state.terminal_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(M.state.terminal_win, width)
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
  if M._is_pi_running() then
    M._ensure_visible()
    if initial_prompt then
      M.send_prompt(initial_prompt)
    end
    return
  end

  local original_win = vim.api.nvim_get_current_win()
  M._open_split()

  -- Fresh buffer so termopen doesn't hijack the original buffer
  -- (vsplit shares the same buffer — termopen converts it in-place)
  vim.cmd('enew')

  local cmd = M._build_cmd(initial_prompt)
  M.state.terminal_job = vim.fn.termopen(cmd, {
    on_exit = function()
      M.state.terminal_job = nil
    end,
  })
  M.state.terminal_buf = vim.api.nvim_get_current_buf()
  vim.bo[M.state.terminal_buf].bufhidden = 'hide'

  M._setup_terminal_nav(M.state.terminal_buf)

  vim.api.nvim_set_current_win(original_win)
end

-- Terminal-mode nav keymaps so Ctrl+h/j/k/l navigate windows/tmux panes
-- instead of being swallowed by pi's TUI
function M._setup_terminal_nav(buf)
  local nav = { h = 'Left', j = 'Down', k = 'Up', l = 'Right' }
  for key, dir in pairs(nav) do
    vim.keymap.set('t', '<C-' .. key .. '>', function()
      vim.cmd('stopinsert')
      local tmux_cmd = 'TmuxNavigate' .. dir
      if vim.fn.exists(':' .. tmux_cmd) == 2 then
        vim.cmd(tmux_cmd)
      else
        vim.cmd('wincmd ' .. key)
      end
    end, { buffer = buf, silent = true })
  end
end

function M.send_prompt(text)
  if not M._is_pi_running() then
    M.open_pi(text)
    return
  end
  local tmpfile = '/tmp/todo-ai-prompt.md'
  local f = io.open(tmpfile, 'w')
  if not f then error('Failed to write ' .. tmpfile) end
  f:write(text)
  f:close()
  vim.fn.chansend(M.state.terminal_job, '/nvim\r')
end

function M.focus_pi()
  if not M._is_pi_running() then
    M.open_pi()
    return
  end
  M._ensure_visible()
  if M.state.terminal_win and vim.api.nvim_win_is_valid(M.state.terminal_win) then
    vim.api.nvim_set_current_win(M.state.terminal_win)
    vim.cmd('startinsert')
  end
end

-- Remote functions (called by the pi extension via nvim --server) -------------

function M.remote_open(path, line)
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= 'terminal' then
        vim.api.nvim_set_current_win(win)
        vim.cmd('edit +' .. (line or 1) .. ' ' .. vim.fn.fnameescape(path))
        return
      end
    end
    vim.cmd('vsplit')
    vim.cmd('edit +' .. (line or 1) .. ' ' .. vim.fn.fnameescape(path))
  end)
end

function M.remote_diff_review()
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= 'terminal' then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
    vim.cmd('DiffviewOpen')
  end)
end

function M.remote_get_context()
  local ctx = { open_files = {} }

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= 'terminal' then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= '' then
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
      break
    end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == '' then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= '' then
        table.insert(ctx.open_files, name)
      end
    end
  end

  return vim.fn.json_encode(ctx)
end

return M
