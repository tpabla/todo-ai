#!/bin/bash
# Smoke tests for post-edit.sh.
# Verifies the hook handles missing-socket cases gracefully and that
# its state-dir derivation matches the Lua sha256(cwd):sub(1,16) scheme.
set -euo pipefail

cd "$(dirname "$0")"

passed=0
failed=0

ok()   { echo "  ok  $1"; passed=$((passed+1)); }
fail() { echo "  FAIL $1"; echo "       $2"; failed=$((failed+1)); }

# 1. State dir derivation matches the value Lua produces for /foo/bar.
expected="a05d96ad6bf8f3ea"
actual=$(printf '%s' "/foo/bar" | shasum -a 256 | cut -c1-16)
if [ "$actual" = "$expected" ]; then
    ok "shasum derivation matches Lua sha256"
else
    fail "shasum derivation matches Lua sha256" "expected $expected, got $actual"
fi

# 2. Hook exits 0 when cwd has no state dir / socket.
TMP_CWD=$(mktemp -d)
INPUT=$(printf '{"cwd": "%s", "tool_input": {"file_path": "/tmp/x"}}' "$TMP_CWD")
if echo "$INPUT" | ./post-edit.sh; then
    ok "hook exits 0 when no nvim socket exists"
else
    fail "hook exits 0 when no nvim socket exists" "exit $?"
fi
rm -rf "$TMP_CWD"

# 3. Hook exits 0 when cwd is missing from input.
if echo '{"tool_input": {"file_path": "/tmp/x"}}' | ./post-edit.sh; then
    ok "hook exits 0 when cwd missing"
else
    fail "hook exits 0 when cwd missing" "exit $?"
fi

# 4. Hook exits 0 with empty stdin.
if echo '{}' | ./post-edit.sh; then
    ok "hook exits 0 with empty json"
else
    fail "hook exits 0 with empty json" "exit $?"
fi

# 5. inject-context.sh emits the workflow rule on stdout regardless of stdin.
out=$(echo '{}' | ./inject-context.sh)
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
