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
