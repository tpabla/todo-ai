-- Minimal init.lua for running tests with Plenary
-- This sets up the test environment with necessary paths and plugins

-- Add current plugin to runtime path
vim.opt.rtp:append('.')

-- Set up package path for Lua modules
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

-- Bootstrap Plenary if not installed
local plenary_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 0 then
  -- Try to find Plenary in common locations
  local possible_paths = {
    vim.fn.stdpath('data') .. '/lazy/plenary.nvim',
    vim.fn.stdpath('data') .. '/plugged/plenary.nvim',
    vim.fn.stdpath('config') .. '/pack/*/start/plenary.nvim',
    vim.fn.stdpath('config') .. '/pack/*/opt/plenary.nvim',
  }

  for _, path in ipairs(possible_paths) do
    local expanded = vim.fn.glob(path)
    if expanded ~= '' then
      plenary_path = expanded
      break
    end
  end
end

-- Add Plenary to runtime path if found
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:append(plenary_path)
else
  print("Warning: Plenary.nvim not found. Install it with your package manager.")
  print("Example: use 'nvim-lua/plenary.nvim' in your config")
end

-- Set up test environment
vim.env.TODOAI_TEST = '1'
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false

-- Load TodoAI plugin
require('todo-ai')

-- Configure for testing
local config = require('todo-ai.config_manager')
config.set('log_level', 'ERROR', false)  -- Reduce noise during tests
config.set('auto_scan_on_save', false, false)  -- Disable auto features

print("Test environment initialized")