#!/bin/bash
# PostToolUse hook for Claude Code: when Claude edits or writes a file,
# tell the paired Neovim instance to :checktime (reload buffers) and open the
# edited file.
#
# Hook input (stdin): JSON with .cwd and .tool_input.file_path
set -uo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

INPUT=$(cat)

# Parsed with grep/sed so the hook has no jq dependency.
json_str() {
    printf '%s' "$INPUT" \
        | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

CWD=$(json_str cwd)
FILE_PATH=$(json_str file_path)
[ -n "$CWD" ] || exit 0

# Resolve the editor through the shared pairing logic: it may be in a
# subdirectory of this agent's cwd rather than the same directory.
NVIM_SOCKET=$(node "$ROOT/shared/editor-cli.js" socket "$CWD" 2>/dev/null) || exit 0
[ -n "$NVIM_SOCKET" ] || exit 0

# Reload all buffers from disk.
nvim --server "$NVIM_SOCKET" --remote-expr 'execute("silent! checktime")' \
    >/dev/null 2>&1 || true

# Open the edited file so the user sees what changed. The editor refuses
# relative paths, so resolve against the agent's cwd first.
if [ -n "$FILE_PATH" ]; then
    ABS=$(node "$ROOT/shared/editor-cli.js" abs "$FILE_PATH" "$CWD" 2>/dev/null)
    if [ -n "$ABS" ]; then
        ESCAPED=$(printf '%s' "$ABS" | sed "s/'/\\\\'/g")
        nvim --server "$NVIM_SOCKET" --remote-expr \
            "execute(\"lua require('todo-ai').remote_open('${ESCAPED}', 1)\")" \
            >/dev/null 2>&1 || true
    fi
fi

exit 0
