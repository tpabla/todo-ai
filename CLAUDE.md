# TODO-AI Development Guidelines

## Architecture

todo-ai is a thin Neovim plugin that opens [pi coding agent](https://github.com/mariozechner/pi-coding-agent) in a tmux pane. The intelligence lives in a pi extension.

### Components

- **`extension/neovim.ts`** — Pi extension: context injection via `$NVIM` socket, neovim tool, buffer reload, `/scan` and `/nvim` commands
- **`lua/todo-ai/init.lua`** — Tmux pane management (open, reuse, focus) + remote functions the extension calls via `nvim --server`
- **`lua/todo-ai/visual.lua`** — Visual selection capture → prompt
- **`lua/todo-ai/config.lua`** — Configuration
- **`plugin/todo-ai.vim`** — Commands + keymaps

### Flow

1. `:TodoAI` opens pi in a tmux pane with `NVIM=<socket>` env var
2. Pi shows session selector (`--resume`)
3. User types in pi's TUI (separate tmux pane, not inside Neovim)
4. Extension injects Neovim state on every prompt (`before_agent_start`)
5. Pi edits files → extension calls `checktime` → buffers reload
6. Pi can open files and trigger diffview via the `neovim` tool

### Multi-instance

Each Neovim spawns its own pi in its own tmux pane. `$NVIM` is unique per instance — no socket discovery needed, no conflicts.

## Principles

- **Pi does the work.** The Neovim plugin is glue — keep it tiny.
- **Extension-first.** New features go in the TypeScript extension, not Lua.
- **No reimplementing pi.** Sessions, streaming, retries, tools — all pi's job.
- **Fail fast.** No silent fallbacks or error recovery. `error()` not `vim.notify`.
- **Tmux required.** No fallback to Neovim terminal buffers.

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
