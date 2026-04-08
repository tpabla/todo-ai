---
paths:
  - "**/*"
---

# Neovim Integration

You are connected to a running Neovim editor via the `neovim_*` MCP tools provided by the todo-ai plugin. Use them to keep the user's editor in sync with what you are doing.

## Workflow Rules

- **Get context first.** At the start of each user request, call `neovim_get_context` to see what file the user is viewing, their cursor position, open buffers, and any LSP diagnostics. Use this to inform your understanding of their intent.

- **Open files you reference.** When discussing or about to modify a specific piece of code, call `neovim_open_file` (with `search` preferred over `line`) so the user can see it without context-switching.

- **Diff review on demand.** Call `neovim_diff_review` only when the user asks to see the diff. Do not call it unprompted.

- **Do not commit.** Never run `git commit`, `git push`, or any other write-side git command. The user reviews diffs in Neovim and commits manually.

- **Buffers reload automatically.** A `PostToolUse` hook calls `:checktime` after every Edit/Write — do not ask the user to reload.
