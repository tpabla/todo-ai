local M = {}

M.defaults = {
  pi_provider = nil,
  pi_model = nil,
  pi_thinking = nil,
  pi_extra_args = {},
  pi_position = 'right',
  pi_width = 80,
  ai_highlight = {
    enabled = true,
    fg = '#ff79c6',
    bg = '#1a1a2e',
    bold = true,
  },
}

M.config = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

function M.get(key)
  return M.config[key]
end

return M
