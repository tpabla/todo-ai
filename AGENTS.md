# TODO-AI Development Guidelines

## Architecture

todo-ai is a thin Neovim plugin that opens [pi coding agent](https://github.com/mariozechner/pi-coding-agent) in a tmux pane. The intelligence lives in a pi extension.

### Components

- **`extension/neovim.ts`** — Pi extension: context injection via `$NVIM` socket, neovim tool, buffer reload, `/scan` command, prompt file polling
- **`lua/todo-ai/init.lua`** — Tmux pane management (open, reuse, focus) + remote functions the extension calls via `nvim --server`
- **`lua/todo-ai/visual.lua`** — Visual selection capture → prompt
- **`lua/todo-ai/config.lua`** — Configuration
- **`plugin/todo-ai.vim`** — Commands + keymaps

### Flow

1. `setup()` writes Neovim socket to `/tmp/todo-ai-<cwd-hash>/nvim-socket`
2. `:TodoAI` checks for existing pi pane (reads `pane-id` from state dir), reconnects or spawns new
3. Extension polls state dir: socket changes → 🟢/🔴, prompt files → `sendUserMessage`
4. Extension injects editor state + workflow rules on every prompt (`before_agent_start`)
5. Pi edits files → extension calls `checktime` → buffers reload
6. Pi uses `open_file` only when referencing specific code during conversation
7. Pi uses `diff_review` only when the user asks to see the diff
8. Pi MUST NOT commit changes — user reviews diff and commits themselves

### Reconnection

- CWD anchors pi to a project: `/tmp/todo-ai-<sha256(cwd)[:16]>/`
- State dir stores: `nvim-socket`, `pane-id`, `prompt.md`
- Neovim writes socket on `setup()`, removes on `VimLeavePre`
- Extension auto-derives state dir from CWD (same hash) if `TODO_AI_STATE_DIR` not set
- Extension writes its own `pane-id` on startup — pi started outside `:TodoAI` is still discoverable
- Extension polls every 500ms — detects connect/disconnect without restart
- Pane liveness checked via `tmux list-panes` (not `display-message` — exits 0 for dead panes)
- Dead panes trigger `_clear_pane()` which removes stale `pane-id` and `prompt.md` files
- Multiple projects = multiple pi instances, no conflicts

## Principles

- **Pi does the work.** The Neovim plugin is glue — keep it tiny.
- **Extension-first.** New features go in the TypeScript extension, not Lua.
- **No reimplementing pi.** Sessions, streaming, retries, tools — all pi's job.
- **Fail fast.** No silent fallbacks or error recovery. `error()` not `vim.notify`.
- **Tmux required.** No fallback to Neovim terminal buffers.
- **Never commit.** Pi must not run `git commit`. User reviews diff and commits themselves.

## Code guidelines

### Lua
- Use `vim.api.nvim_*` over `vim.fn.*`
- Total Lua should stay under 250 lines
- No module beyond `init.lua`, `visual.lua`, `config.lua` unless truly necessary

### TypeScript (extension)
- Use pi's extension API: `pi.on()`, `pi.registerTool()`, `pi.registerCommand()`
- Communicate with Neovim via `nvim --server $NVIM --remote-expr`
- Keep tool descriptions concise — frontier models don't need verbose instructions
- Use `promptGuidelines` for when-to-use hints

## Testing

```bash
make test          # plenary tests
make lint          # dead code detection
```
