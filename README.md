# todo-ai

Neovim + [pi coding agent](https://github.com/mariozechner/pi-coding-agent) via tmux. Pi runs in its own tmux pane with full access to your editor state. It edits files directly; you review with [diffview.nvim](https://github.com/sindrets/diffview.nvim).

## How it works

```
┌─ tmux ──────────────────────────────────────────────┐
│                                                      │
│  Neovim (pane 1)              pi (pane 2)            │
│  ┌──────────────────┐        ┌────────────────────┐  │
│  │                  │        │                    │  │
│  │ • current file   │───────►│ reads editor state │  │
│  │ • cursor line    │        │ on every prompt    │  │
│  │ • open buffers   │        │                    │  │
│  │ • LSP diagnostics│◄───────│ opens files        │  │
│  │                  │        │ triggers diffview  │  │
│  │                  │◄───────│ reloads buffers    │  │
│  │                  │        │                    │  │
│  └──────────────────┘        └────────────────────┘  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

`:TodoAI` opens pi in a tmux split. Each Neovim instance gets its own pi pane with the correct `$NVIM` socket — multiple sessions work independently.

The Neovim plugin is ~50 lines of Lua. All intelligence lives in pi and its [extension](extension/neovim.ts).

## Requirements

- **[tmux](https://github.com/tmux/tmux)** — Neovim must be running inside tmux
- **[pi](https://github.com/mariozechner/pi-coding-agent)** — `npm i -g @mariozechner/pi-coding-agent`
- **[diffview.nvim](https://github.com/sindrets/diffview.nvim)** — for reviewing changes

See **[INSTALL.md](INSTALL.md)** for detailed setup.

## Quick start

```lua
-- lazy.nvim
{
  "tpabla/todo-ai",
  dependencies = { "sindrets/diffview.nvim" },
  config = function()
    require("todo-ai").setup()
  end,
}
```

## Usage

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>tc` | `:TodoAI` | Open pi in a tmux pane (or reuse existing) |
| `<leader>tf` | `:TodoAIFocus` | Switch tmux focus to pi's pane |
| `<leader>ti` | `:TodoAIVisual` | Send visual selection to pi |

### Workflow

1. `:TodoAI` — pi opens in a tmux pane to the right, shows session selector
2. Pick a previous session or start new
3. Type your request in pi's TUI
4. Pi reads files, makes edits, runs commands
5. Pi opens relevant files in your editor and triggers diff review
6. Switch back to Neovim, review with `:DiffviewOpen`, commit or revert

### Context is always fresh

Open files, navigate code, trigger LSP between prompts — the extension queries Neovim for current file, cursor position, open buffers, and diagnostics fresh on every prompt.

### Visual mode

Select code → `<leader>ti` → type instruction → pi processes it.

### TODO scanning

```python
# TODO: @ai add input validation
def process(data):
    return data.upper()
```

In pi's pane, type `/scan` — finds all `TODO: @ai` comments and resolves them.

### Sessions

Pi manages sessions natively. `:TodoAI` always passes `--resume` so you can pick up where you left off or start fresh. Use `/new` in pi for a blank session, `/resume` to switch.

## Configuration

Provider, model, and thinking are configured through pi directly — see [pi docs](https://github.com/mariozechner/pi-coding-agent). The settings below are todo-ai-specific:

```lua
require("todo-ai").setup({
  pi_extra_args = {},            -- extra CLI args passed to pi
  pi_position = "right",        -- tmux pane position: "right" or "left"
  pi_width = 80,                -- tmux pane width in columns

  ai_highlight = {               -- @ai tag highlighting
    enabled = true,
    fg = "#ff79c6",
    bg = "#1a1a2e",
    bold = true,
  },
})
```

## What the extension does

The [pi extension](extension/neovim.ts) (~170 lines of TypeScript):

| Hook | What it does |
|------|-------------|
| `before_agent_start` | Queries Neovim via `$NVIM` socket for current file, cursor, open buffers, LSP diagnostics. Injected fresh on every prompt. |
| `neovim` tool | Pi can open files at specific lines and trigger `:DiffviewOpen`. |
| `tool_execution_end` | Calls `:checktime` after edits so buffers reload. |
| `/scan` command | Greps for `TODO: @ai` and sends matches to pi. |
| `/nvim` command | Reads prompts sent from Neovim (visual selection, etc.). |

## Project structure

```
todo-ai/
├── extension/neovim.ts      # Pi extension — context, tools, commands
├── lua/todo-ai/
│   ├── init.lua             # Tmux pane management + remote functions
│   ├── visual.lua           # Visual selection → prompt
│   └── config.lua           # Configuration
├── plugin/todo-ai.vim       # Commands + keymaps
├── tests/plenary/
├── INSTALL.md
└── Makefile
```

## Development

```
make test                     Run tests
make test-single FILE=...     Run one test file
make lint                     Find dead Lua code
make dev                      Symlink for development
make install                  Install to Neovim packages
```

## License

MIT
