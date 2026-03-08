# TODO-AI Development Guidelines

## Architecture

todo-ai is a thin Neovim plugin that wraps [pi coding agent](https://github.com/mariozechner/pi-coding-agent). The intelligence lives in a pi extension.

### Components

- **`extension/neovim.ts`** — Pi extension: context injection, neovim tool, buffer reload, `/scan` and `/nvim` commands
- **`lua/todo-ai/init.lua`** — Terminal management (open, reuse, focus) + remote functions the extension calls via `nvim --server`
- **`lua/todo-ai/visual.lua`** — Visual selection capture → prompt
- **`lua/todo-ai/config.lua`** — Configuration
- **`plugin/todo-ai.vim`** — Commands + keymaps

### Flow

1. `:TodoAI` opens pi in a terminal split (reuses existing session)
2. User types in pi's TUI
3. Extension injects Neovim state on every prompt (`before_agent_start`)
4. Pi edits files → extension calls `checktime` → buffers reload
5. Pi can open files and trigger diffview via the `neovim` tool

## Principles

- **Pi does the work.** The Neovim plugin is glue — keep it tiny.
- **Extension-first.** New features go in the TypeScript extension, not Lua.
- **No reimplementing pi.** Sessions, streaming, retries, tools — all pi's job.
- **Fail fast.** No silent fallbacks or error recovery.

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
