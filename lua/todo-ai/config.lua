local M = {}

-- Harness identifiers (use these constants instead of string literals)
M.HARNESS_PI = 'pi'
M.HARNESS_CLAUDE_CODE = 'claude_code'

M.defaults = {
  harness = M.HARNESS_CLAUDE_CODE,
  tag = 'AGENT',
  pane_width = 80,

  -- "new" or "resume"; nil = harness default (pi → resume, claude_code → new)
  session_mode = nil,

  -- Pi-specific
  pi_extra_args = {},

  -- Claude Code-specific
  claude_extra_args = {},
  claude_model = nil,
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
