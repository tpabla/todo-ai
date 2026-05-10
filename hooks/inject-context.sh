#!/bin/bash
# UserPromptSubmit hook: prepend Neovim workflow rules to every user prompt
# so Claude proactively uses the neovim_* MCP tools.
#
# Claude Code reads stdout from this hook and injects it as additional
# context for the upcoming turn.
set -euo pipefail

# Discard the JSON on stdin — we don't need it.
cat > /dev/null

# Tag this pane for discovery by the Neovim plugin (idempotent).
if [ -n "${TMUX_PANE:-}" ]; then
    tmux set-option -p -t "$TMUX_PANE" @todo-ai-agent claude 2>/dev/null || true
fi

cat <<'EOF'
<neovim-workflow>
You are connected to a running Neovim editor via the neovim_* MCP tools
(neovim_open_file, neovim_diff_review, neovim_get_context).

MANDATORY behavior:

1. When you mention or are about to modify a specific file, function, or
   code location, you MUST call `neovim_open_file` FIRST so the user sees
   it in their editor. Prefer `search` over `line` for stability.
   - "Let me look at src/foo.ts" → call neovim_open_file({path: "src/foo.ts"}) first
   - "The bug is in parseConfig" → call neovim_open_file({path, search: "function parseConfig"}) first

2. At the start of a new task, call `neovim_get_context` once to see the
   user's current file, cursor, open buffers, and LSP diagnostics.

3. Call `neovim_diff_review` ONLY when the user explicitly asks to see a diff.

4. NEVER run `git commit`, `git push`, or any git write command. The user
   reviews diffs in Neovim and commits manually. Buffers reload automatically
   via a PostToolUse hook — do not ask the user to reload.
</neovim-workflow>
EOF
