---
name: scan
description: Find AGENT-tagged comments in the project and resolve each one
allowed-tools: "Bash(rg:*) Bash(git:*) Bash(grep:*) Grep Read Edit"
---

Find and resolve all `AGENT:` comments in this project.

Search respects `.gitignore` — `rg` honors it by default, and the fallback uses `git grep` (tracked files only). Untracked/gitignored paths (e.g. `node_modules`, build output) are excluded.

Results:

!`rg -n "AGENT:" . 2>/dev/null || git grep -nI "AGENT:" 2>/dev/null || grep -rn "AGENT:" . --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=coverage 2>/dev/null || echo "No matches found"`

For each comment above:
1. Read the surrounding code to understand the context
2. Implement what the comment describes
3. Remove the comment after resolving it

If there are no matches, report "No tagged comments found" and stop.
