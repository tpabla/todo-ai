---
name: scan
description: Find AGENT-tagged comments in the project and resolve each one
argument-hint: "[tag]"
allowed-tools: "Bash(rg:*) Bash(grep:*) Grep Read Edit"
---

Find and resolve all `AGENT:` (or custom tag) comments in this project.

Tag to scan for: ${1:-AGENT}

Results:

!`rg -n "${1:-AGENT}:" . 2>/dev/null || grep -rn "${1:-AGENT}:" . --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null || echo "No matches found"`

For each comment above:
1. Read the surrounding code to understand the context
2. Implement what the comment describes
3. Remove the comment after resolving it

If there are no matches, report "No tagged comments found" and stop.
