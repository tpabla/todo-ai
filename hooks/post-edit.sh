#!/bin/bash
# PostToolUse hook for Claude Code: when Claude edits or writes a file,
# tell the connected Neovim instance to :checktime (reload buffers) and
# open the edited file at line 1.
#
# Hook input (stdin): JSON with .cwd and .tool_input.file_path
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -n "$CWD" ] || exit 0

# Derive state dir the same way Lua does: sha256(cwd) first 16 hex chars.
HASH=$(printf '%s' "$CWD" | shasum -a 256 | cut -c1-16)
STATE_DIR="/tmp/todo-ai-${HASH}"
SOCKET_FILE="${STATE_DIR}/nvim-socket"

[ -f "$SOCKET_FILE" ] || exit 0
NVIM_SOCKET=$(cat "$SOCKET_FILE")
[ -n "$NVIM_SOCKET" ] || exit 0

# Reload all buffers from disk.
nvim --server "$NVIM_SOCKET" --remote-expr 'execute("silent! checktime")' \
    >/dev/null 2>&1 || true

# Open the edited file in Neovim so the user sees what changed.
if [ -n "$FILE_PATH" ]; then
    ESCAPED=$(printf '%s' "$FILE_PATH" | sed "s/'/\\\\'/g")
    nvim --server "$NVIM_SOCKET" --remote-expr \
        "execute(\"lua require('todo-ai').remote_open('${ESCAPED}', 1)\")" \
        >/dev/null 2>&1 || true
fi

exit 0
