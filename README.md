# todo-ai

Neovim + [pi coding agent](https://github.com/mariozechner/pi-coding-agent). Pi runs in a terminal pane with full access to your editor state — open files, cursor position, LSP diagnostics. It edits files directly; you review with [diffview.nvim](https://github.com/sindrets/diffview.nvim).

## How it works

```
┌──────────────────────────────────────────────────────┐
│ Neovim                                               │
│                                                      │
│  ┌──────────────────┐    ┌─────────────────────────┐ │
│  │ Code buffers      │◄──│ pi (terminal pane)      │ │
│  │                   │   │                         │ │
│  │ • current file    │──►│ • reads editor state    │ │
│  │ • cursor position │   │ • edits files directly  │ │
│  │ • open buffers    │   │ • runs shell commands   │ │
│  │ • LSP diagnostics │   │ • opens files in editor │ │
│  │                   │   │ • triggers diff review  │ │
│  │ :DiffviewOpen ◄───│───│                         │ │
│  └──────────────────┘    └─────────────────────────┘ │
│                                                      │
└──────────────────────────────────────────────────────┘
```

The Neovim plugin is ~60 lines of Lua. All intelligence lives in pi and its [extension](extension/neovim.ts).

## Install

See **[INSTALL.md](INSTALL.md)** for detailed setup.

**Quick start** — requires [pi](https://github.com/mariozechner/pi-coding-agent) (`npm i -g @mariozechner/pi-coding-agent`):

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
| `<leader>tc` | `:TodoAI` | Open/show pi terminal |
| `<leader>tf` | `:TodoAIFocus` | Focus pi terminal |
| `<leader>ti` | `:TodoAIVisual` | Send visual selection to pi |

### Workflow

1. `:TodoAI` — opens pi in a right split
2. Type your request in pi's TUI
3. Pi reads files, makes edits, runs commands
4. Pi opens relevant files in your editor and triggers diff review
5. Review with `:DiffviewOpen`, commit or revert

### Between prompts

Open files, navigate code, trigger LSP — the extension queries your editor state fresh on every prompt. Pi always sees what you're currently looking at.

### Visual mode

Select code → `<leader>ti` → type instruction → pi processes it in context.

### TODO scanning

```python
# TODO: @ai add input validation
def process(data):
    return data.upper()
```

In pi's terminal, type `/scan` — finds all `TODO: @ai` comments across the project and resolves them.

### Session persistence

Pi manages its own sessions. Close the terminal, reopen with `:TodoAI` — your conversation is there. Use `/resume` in pi to switch between sessions, or add `--continue` to `pi_extra_args` to auto-resume.

## Configuration

Provider, model, and thinking are configured through pi itself (see [pi docs](https://github.com/mariozechner/pi-coding-agent)).

```lua
require("todo-ai").setup({
  pi_extra_args = {},            -- extra CLI args for pi
  pi_position = "right",        -- terminal position: "right" or "left"
  pi_width = 80,                -- terminal width in columns

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
| `before_agent_start` | Queries Neovim for current file, cursor, open buffers, LSP diagnostics. Injected fresh on every prompt. |
| `neovim` tool | Pi can open files at specific lines and trigger `:DiffviewOpen` in your editor. |
| `tool_execution_end` | Calls `:checktime` after edits so buffers reload automatically. |
| `/scan` command | Greps for `TODO: @ai` and sends matches to pi for resolution. |
| `/nvim` command | Reads prompts sent programmatically from the Neovim plugin. |

## Project structure

```
todo-ai/
├── extension/neovim.ts      # Pi extension — context, tools, commands
├── lua/todo-ai/
│   ├── init.lua             # Terminal management + remote functions
│   ├── visual.lua           # Visual selection → prompt
│   └── config.lua           # Configuration
├── plugin/todo-ai.vim       # Commands + keymaps
├── tests/plenary/           # Tests
├── INSTALL.md
└── Makefile
```

## Development

```
make test             Run tests
make test-single FILE=...   Run one test file
make lint             Find dead Lua code
make dev              Symlink for development
make install          Install to Neovim packages
```

## License

MIT
