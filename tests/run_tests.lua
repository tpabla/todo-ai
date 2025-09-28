-- Simple test runner that sets up test mode and runs tests
vim.g.todo_ai_test_mode = true
vim.g.todo_ai_test_timeout = 100

-- Add current plugin to path
vim.opt.rtp:append('.')
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua"

-- Find and add Plenary
local plenary_paths = {
  vim.fn.stdpath('data') .. '/lazy/plenary.nvim',
  vim.fn.stdpath('data') .. '/site/pack/test/start/plenary.nvim',
  vim.fn.stdpath('data') .. '/plugged/plenary.nvim',
  '~/.local/share/nvim/site/pack/test/start/plenary.nvim',
}

for _, path in ipairs(plenary_paths) do
  local expanded = vim.fn.expand(path)
  if vim.fn.isdirectory(expanded) == 1 then
    vim.opt.rtp:append(expanded)
    break
  end
end

-- Run tests
local test_dir = 'tests/plenary'
require('plenary.test_harness').test_directory(test_dir, {
  minimal_init = false,  -- We already initialized
  sequential = true,     -- Run tests sequentially to avoid timing issues
  timeout = 5000,        -- 5 second timeout per test
})

-- Exit
vim.cmd('qall!')