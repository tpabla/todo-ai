local M = {}

M.defaults = {
  tag = 'AGENT',

  -- Agent started when <leader>tc finds none: a herdr agent kind, or the
  -- command run in a new tmux pane
  agent = 'claude',
  split = 'right', -- 'right' or 'down'

  -- Foreground commands treated as agents when discovering tmux panes. herdr
  -- detects agents itself and ignores this.
  agent_commands = { 'claude', 'pi', 'codex', 'opencode', 'gemini', 'amp' },

  -- Share of the window height taken by the slides split
  slides_height = 0.4,

  -- How often attached buffers are re-read from disk while an agent edits them
  reload_interval_ms = 1000,
}

M.config = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

function M.get(key)
  local v = M.config[key]
  if v == nil then return M.defaults[key] end
  return v
end

return M
