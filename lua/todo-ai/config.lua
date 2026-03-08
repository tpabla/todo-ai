local M = {}

M.defaults = {
  pi_extra_args = {},
  pi_width = 80,
}

M.config = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

function M.get(key)
  return M.config[key]
end

return M
