-- Minimal init for test environment
vim.opt.runtimepath:append('.')
vim.opt.runtimepath:append('/Users/taran/.local/share/nvim/lazy/plenary.nvim')

-- Load the plugin
require('todo-ai')

-- Set up test environment
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
