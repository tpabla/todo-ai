#!/bin/bash
# Tag the current tmux pane for discovery by the Neovim plugin.
# One implementation shared by every harness: the Claude Code hook calls it and
# the pi extension execs it, so adding a harness means calling this rather than
# reimplementing the option names.
#
# Usage: tag-pane.sh <agent-label> [session-id] [name]
#
# Best-effort by design: tagging must never fail the agent, and no variable is
# assumed to be set (a manually started agent has none of the plugin's env).
set -uo pipefail

agent="${1:-}"
session_id="${2:-}"
name="${3:-${TODO_AI_NAME:-}}"

[ -z "$agent" ] && exit 0
[ -z "${TMUX:-}" ] && exit 0
[ -z "${TMUX_PANE:-}" ] && exit 0

set_opt() {
    [ -n "$2" ] && tmux set-option -p -t "$TMUX_PANE" "$1" "$2" 2>/dev/null || true
}

set_opt @todo-ai-agent "$agent"
set_opt @todo-ai-dir "$PWD"
set_opt @todo-ai-session "$session_id"
set_opt @todo-ai-name "$name"

exit 0
