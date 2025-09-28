#!/usr/bin/env lua
-- Run tests for todo-ai plugin

-- Add plugin to runtimepath
vim.opt.runtimepath:append('/Users/taran/Projects/todo-ai')

-- Load required modules
local ok, plenary = pcall(require, 'plenary.test_harness')
if not ok then
  print("Plenary not found, running basic tests...")

  -- Basic test runner without plenary
  dofile('/Users/taran/Projects/todo-ai/tests/search_replace_spec.lua')

  print("\n=== Basic Tests Complete ===")
else
  -- Run with plenary
  plenary.test_directory('/Users/taran/Projects/todo-ai/tests', {
    minimal_init = '/Users/taran/Projects/todo-ai/tests/minimal_init.lua',
    sequential = true
  })
end