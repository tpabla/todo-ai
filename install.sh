#!/bin/bash

# Todo-AI Installation Script

set -e

# Get the data directory for Neovim
NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
TODOAI_DIR="$NVIM_DATA_DIR/todo-ai"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Add the plugin to your Neovim config:"
echo "   Packer:    use 'todo-ai'"
echo "   Lazy.nvim: { 'todo-ai' }"
echo ""
echo "2. Configure your provider in ~/.config/nvim/lua/todo-ai-config.lua:"
echo "   require('todo-ai').setup({"
echo "     provider = 'ollama',  -- or 'claude', 'openai', 'custom'"
echo "     model = 'llama3.2',"
echo "   })"
echo ""
echo "3. Use the plugin:"
echo "   - Write: # TODO: @ai implement binary search"
echo "   - Run: :TodoAIScan or press <leader>ts"
echo ""
