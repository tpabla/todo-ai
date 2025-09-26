#!/bin/bash

# Development setup script for todo-ai

echo "Setting up todo-ai for local development..."

# 1. Install Python dependencies locally
echo "Installing Python dependencies..."
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install anthropic openai  # Optional providers

# 2. Create a test Neovim config
echo "Creating test Neovim configuration..."
mkdir -p test/nvim

cat > test/nvim/init.lua << 'EOF'
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
EOF

# 3. Create a test file with examples
cat > test/example.py << 'EOF'
# Test file for todo-ai plugin

# TODO: @ai write a function that calculates fibonacci numbers recursively
def fibonacci(n):
    pass

# TODO: @ai implement a simple LRU cache decorator with a size limit of 100
class Cache:
    pass

# TODO: @ai create a context manager for timing code execution
def timer():
    pass

# Regular TODO (should not trigger)
# TODO: This is a normal todo without @ai

print("Test file ready!")
EOF

cat > test/example.js << 'EOF'
// JavaScript test file

// TODO: @ai implement a promise-based delay function
function delay(ms) {
}

// TODO: @ai create a deep clone function for objects
function deepClone(obj) {
}

// TODO: @ai write a function to flatten nested arrays
const flatten = (arr) => {
};
EOF

# 4. Create a launcher script
cat > test-plugin.sh << 'EOF'
#!/bin/bash

# Start the Python backend server
echo "Starting backend server..."
source venv/bin/activate
python python/server.py &
SERVER_PID=$!

# Give server time to start
sleep 2

# Launch Neovim with test config
echo "Launching Neovim..."
nvim -u test/nvim/init.lua test/example.py

# Kill server when done
echo "Stopping server..."
kill $SERVER_PID 2>/dev/null

echo "Test session ended."
EOF

chmod +x test-plugin.sh

echo ""
echo "Setup complete! Here's how to test:"
echo ""
echo "1. Make sure Ollama is running:"
echo "   ollama serve"
echo "   ollama pull llama3.2  # if you haven't already"
echo ""
echo "2. Run the test environment:"
echo "   ./test-plugin.sh"
echo ""
echo "3. In Neovim:"
echo "   - The test file will open with TODO examples"
echo "   - Press <Space>ts to scan for TODOs"
echo "   - Press <Space>ta to accept changes"
echo "   - Press <Space>tr to reject changes"
echo "   - Press <Space>tc to open chat"
echo ""
echo "For manual testing:"
echo "   # Terminal 1: Start the server"
echo "   source venv/bin/activate"
echo "   python python/server.py"
echo ""
echo "   # Terminal 2: Open Neovim"
echo "   nvim -u test/nvim/init.lua test/example.py"
EOF

chmod +x dev-setup.sh