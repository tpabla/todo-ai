#!/bin/bash

# Todo-AI Installation Script

set -e

echo "Installing Todo-AI Backend..."

# Get the data directory for Neovim
NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
TODOAI_DIR="$NVIM_DATA_DIR/todo-ai"

# Create directory structure
echo "Creating directories..."
mkdir -p "$TODOAI_DIR"

# Copy Python backend files
echo "Copying backend files..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cp -r "$SCRIPT_DIR/python"/* "$TODOAI_DIR/"

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$TODOAI_DIR/venv"

# Activate venv and install dependencies
echo "Installing Python dependencies..."
source "$TODOAI_DIR/venv/bin/activate"

# Install required packages
pip install --upgrade pip
pip install aiohttp aiohttp-cors

# Install optional packages (don't fail if they error)
echo "Installing optional AI providers..."
pip install anthropic || echo "Warning: anthropic package not installed (needed for Claude API key method)"
pip install openai || echo "Warning: openai package not installed (needed for GPT)"

# Create launcher script
echo "Creating launcher script..."
cat > "$TODOAI_DIR/server.py" << 'EOF'
#!/usr/bin/env python3
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from server import main
if __name__ == '__main__':
    main()
EOF

chmod +x "$TODOAI_DIR/server.py"

# Check if Claude Code is available
if command -v claude &> /dev/null; then
    echo "Claude Code CLI detected! You can use your Claude Pro/Max subscription."
    echo "Set USE_CLAUDE_CODE=true in your config to use it."
else
    echo "Claude Code CLI not found. You can still use API keys or other providers."
fi

# Check if Ollama is available
if command -v ollama &> /dev/null; then
    echo "Ollama detected! Make sure it's running (ollama serve) to use local models."
fi

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