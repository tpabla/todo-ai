-- Minimal init for test environment
vim.opt.runtimepath:append('.')

-- Try common plenary install locations
local plenary_paths = {
  vim.fn.stdpath('data') .. '/lazy/plenary.nvim',
  vim.fn.stdpath('data') .. '/site/pack/test/start/plenary.nvim',
  vim.fn.stdpath('data') .. '/site/pack/plugins/start/plenary.nvim',
}
for _, path in ipairs(plenary_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    break
  end
end

-- Load the plugin
require('todo-ai')

-- Set up test environment
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
