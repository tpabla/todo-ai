# todo-ai

Neovim + an AI coding agent via tmux. The agent runs in its own tmux pane with full access to your editor state. It edits files directly; you review with [diffview.nvim](https://github.com/sindrets/diffview.nvim).

**Two harnesses are supported** — pick one in your config:

- **`claude_code`** (default) — [Claude Code CLI](https://claude.com/claude-code), wired up via a bundled Claude Code plugin (MCP server + hooks + skills)
- **`pi`** — [pi coding agent](https://github.com/mariozechner/pi-coding-agent), wired up via the existing pi extension

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

`:TodoAI` opens pi in a tmux split. Pi and Neovim are linked by CWD — close Neovim, reopen it, and pi reconnects automatically (🟢). Close Neovim for good and pi shows disconnected (🔴). Multiple Neovim instances in different projects each get their own pi.

## Requirements

- **[tmux](https://github.com/tmux/tmux)** — Neovim must be running inside tmux
- **[pi](https://github.com/mariozechner/pi-coding-agent)** — `npm i -g @mariozechner/pi-coding-agent`
- **[diffview.nvim](https://github.com/sindrets/diffview.nvim)** — for reviewing changes
- **[todo-comments.nvim](https://github.com/folke/todo-comments.nvim)** *(optional)* — adds telescope search and icons for `AGENT:` tags

See **[INSTALL.md](INSTALL.md)** for detailed setup.

## Quick start

```lua
-- lazy.nvim
{
  "tpabla/todo-ai",
  dependencies = { "sindrets/diffview.nvim" },
  opts = {},
}
```

## Usage

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>tc` | `:TodoAI` | Open the agent in a tmux pane (or reuse existing) |
| `<leader>tf` | `:TodoAIFocus` | Switch tmux focus to the agent's pane |
| `<leader>ts` | `:TodoAIScan` | Find `AGENT:` comments, send them to the agent |
| `<leader>ti` | `:TodoAIVisual` | Send visual selection to the agent |
|              | `:TodoAIInstall` | Install the Claude Code plugin (MCP deps + register) |

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

### AGENT scanning

```python
# AGENT: add input validation
def process(data):
    return data.upper()
```

`<leader>ts` or `:TodoAIScan` — finds all `AGENT:` comments across the project and sends them to pi for resolution. Also available as `/scan` in pi's pane.

### Sessions & reconnection

Pi manages sessions natively. `:TodoAI` always passes `--resume` so you can pick up where you left off or start fresh.

If pi is already running for your project (same CWD), `:TodoAI` reconnects to it instead of spawning a new instance. Close Neovim → pi shows 🔴. Reopen Neovim → pi goes 🟢 automatically.

Pi started independently (not through `:TodoAI`) also works — the extension auto-discovers Neovim's socket via CWD hash. Just run pi with the extension in the same directory as Neovim.

## Configuration

Provider, model, and thinking are configured through pi directly — see [pi docs](https://github.com/mariozechner/pi-coding-agent). The settings below are todo-ai-specific:

```lua
require("todo-ai").setup({
  harness = "claude_code",       -- "claude_code" (default) | "pi"
  tag = "AGENT",                 -- comment tag for scanning (AGENT:)
  pane_width = 80,               -- tmux pane width in columns

  -- Claude Code harness
  claude_model = nil,            -- override model, e.g. "sonnet"
  claude_extra_args = {},        -- extra CLI args passed to `claude`

  -- Pi harness
  pi_extra_args = {},            -- extra CLI args passed to `pi`
})
```

### Claude Code harness

The Claude Code adapter ships as a Claude Code plugin in this repo, bundling:

- **MCP server** (`mcp-server/`) exposing `neovim_open_file`, `neovim_diff_review`, `neovim_get_context`
- **PostToolUse hook** (`hooks/post-edit.sh`) that calls `:checktime` after every Edit/Write
- **`/scan` skill** (`skills/scan/`) for AGENT-tag resolution
- **Workflow rules** (`rules/neovim-workflow.md`) telling Claude to fetch editor context per task

**Setup is one command.** After lazy.nvim clones the repo, run:

```vim
:TodoAIInstall
```

That runs `npm install` in `mcp-server/` (skipped if `node_modules/` exists) and that's it. Nothing is written under `~/.claude/`.

The plugin is loaded **in-place** every time `:TodoAI` launches `claude`, via `claude --plugin-dir <plugin_root>`. Edits to the plugin source are picked up on the next launch (or `/reload-plugins` inside `claude`). No copy, no marketplace registration, no global state.

If you want the same plugin available when you run `claude` from a regular terminal (outside Neovim), alias it: `alias claude='claude --plugin-dir ~/.local/share/nvim/lazy/todo-ai'`.

## What the extension does

The [pi extension](extension/neovim.ts) (~280 lines of TypeScript):

| Hook | What it does |
|------|-------------|
| Socket polling | Detects Neovim connect/disconnect via state dir. 🟢 when connected, 🔴 when not. |
| `before_agent_start` | Queries editor state (file, cursor, buffers, diagnostics). Injects workflow rules. |
| `neovim` tool | Opens files at specific lines and triggers `:DiffviewOpen`. |
| `tool_execution_end` | Calls `:checktime` after edits so buffers reload. |
| `/scan` command | Greps for `AGENT:` (uses `rg` if available) and sends matches to pi. |
| Prompt polling | Watches for prompt files from Neovim (visual selection, scan). |

## Project structure

```
todo-ai/
├── lua/todo-ai/             # Neovim plugin (harness-agnostic)
│   ├── init.lua             #   tmux pane management + remote functions
│   ├── visual.lua           #   visual selection → prompt
│   └── config.lua           #   configuration + harness constants
├── plugin/todo-ai.vim       # Commands + keymaps
├── extension/neovim.ts      # Pi adapter (pi extension)
├── mcp-server/              # Claude Code adapter — MCP server (Node)
├── hooks/                   # Claude Code adapter — PostToolUse hooks
├── skills/scan/             # Claude Code adapter — /scan skill
├── rules/                   # Claude Code adapter — workflow rules
├── .claude-plugin/          # Claude Code plugin manifest
├── .mcp.json                # MCP server registration
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
