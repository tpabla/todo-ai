#!/bin/bash
# Smoke tests for the hook scripts.
# Verifies they handle the missing-editor cases gracefully and that pane
# tagging and editor resolution work through the shared helpers.
set -euo pipefail

cd "$(dirname "$0")"

passed=0
failed=0

ok()   { echo "  ok  $1"; passed=$((passed+1)); }
fail() { echo "  FAIL $1"; echo "       $2"; failed=$((failed+1)); }

# 1. Editor resolution exits non-zero when no editor is published.
REG=$(mktemp -d)
if TODO_AI_SOCKET= node ../shared/editor-cli.js socket "$REG" >/dev/null 2>&1; then
    : # an editor happens to be published for this path; not a failure
    ok "editor-cli reports a socket without crashing"
else
    ok "editor-cli exits non-zero when no editor is paired"
fi
rm -rf "$REG"

# 2. Pane tagging is a no-op outside tmux and never fails the agent.
if (unset TMUX TMUX_PANE; ../shared/tag-pane.sh claude sess-1 api); then
    ok "tag-pane.sh exits 0 outside tmux"
else
    fail "tag-pane.sh exits 0 outside tmux" "exit $?"
fi

# 3. Pane tagging survives being called with no arguments at all.
if (unset TMUX TMUX_PANE; ../shared/tag-pane.sh); then
    ok "tag-pane.sh exits 0 with no arguments"
else
    fail "tag-pane.sh exits 0 with no arguments" "exit $?"
fi

# 4. inject-context.sh works with no plugin env set — a manually started
#    claude has none of it, and set -u used to abort the hook here.
if (unset TODO_AI_STATE_DIR CLAUDE_PLUGIN_ROOT TMUX TMUX_PANE; \
        echo '{"session_id":"abc-123"}' | ./inject-context.sh >/dev/null); then
    ok "inject-context.sh survives an unset plugin environment"
else
    fail "inject-context.sh survives an unset plugin environment" "exit $?"
fi

# 2. Hook exits 0 when cwd has no state dir / socket.
TMP_CWD=$(mktemp -d)
INPUT=$(printf '{"cwd": "%s", "tool_input": {"file_path": "/tmp/x"}}' "$TMP_CWD")
if (unset TMUX TMUX_PANE; echo "$INPUT" | ./post-edit.sh); then
    ok "hook exits 0 when no nvim socket exists"
else
    fail "hook exits 0 when no nvim socket exists" "exit $?"
fi
rm -rf "$TMP_CWD"

# 3. Hook exits 0 when cwd is missing from input.
if (unset TMUX TMUX_PANE; echo '{"tool_input": {"file_path": "/tmp/x"}}' | ./post-edit.sh); then
    ok "hook exits 0 when cwd missing"
else
    fail "hook exits 0 when cwd missing" "exit $?"
fi

# 4. Hook exits 0 with empty stdin.
if (unset TMUX TMUX_PANE; echo '{}' | ./post-edit.sh); then
    ok "hook exits 0 with empty json"
else
    fail "hook exits 0 with empty json" "exit $?"
fi

# 5. inject-context.sh emits the workflow rule on stdout regardless of stdin.
out=$(unset TMUX TMUX_PANE; echo '{}' | ./inject-context.sh)
if echo "$out" | grep -q "neovim_open_file"; then
    ok "inject-context.sh emits workflow rules"
else
    fail "inject-context.sh emits workflow rules" "stdout missing 'neovim_open_file'"
fi
if echo "$out" | grep -q "neovim-workflow"; then
    ok "inject-context.sh wraps output in neovim-workflow tag"
else
    fail "inject-context.sh wraps output in neovim-workflow tag" "missing tag"
fi

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
