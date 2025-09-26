-- Minimal init.lua for testing todo-ai

-- Add the plugin to runtime path
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Load the plugin
require('todo-ai').setup({
  provider = 'ollama',  -- Start with Ollama for local testing
  model = 'llama3.2',
  server_host = 'localhost',
  server_port = 8765,
  auto_open_chat = true,
  highlight_todos = true,
})

-- Set leader key
vim.g.mapleader = ' '

-- Optional: Add some helpful settings for testing
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4

print("Todo-AI loaded! Use :TodoAIScan or <leader>ts to scan for TODOs")
