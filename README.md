# todo-ai

Pair Neovim with any coding agent running beside it in [herdr](https://herdr.dev) or tmux. Send it code from your editor; let it open files, highlight ranges and walk you through code in your editor. Review its changes with [diffview.nvim](https://github.com/sindrets/diffview.nvim).

No harness-specific code: Claude Code, pi, codex or anything else works through one CLI and one skill.

## How it works

```
┌─ herdr tab / tmux window ──────────────────────────────────────────┐
│                                                                    │
│  Neovim                                agent (claude, pi, …)       │
│  ┌─────────────────────────┐          ┌──────────────────────────┐ │
│  │ <leader>ti  ask about   │ prompt   │                          │ │
│  │   the selection         │─────────►│                          │ │
│  │                         │          │ todo-ai context          │ │
│  │ file, cursor, selection │◄─────────│ todo-ai open f.ts:12-30  │ │
│  │ highlighted ranges      │   rpc    │ todo-ai diff             │ │
│  │ buffers reload on edit  │          │                          │ │
│  └─────────────────────────┘          └──────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

`<leader>tc` attaches the editor to an agent in the same herdr workspace or tmux session, starting one if there is none. The agent's `todo-ai` command then always reaches that editor.

## Usage

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>tc` | `:TodoAI` | Attach to an agent in this workspace/session; starts one if none |
| `<leader>ti` | `:TodoAIVisual` | Ask the agent about the selected code |
|              | `:TodoAISend {text}` | Send a prompt |
| `<leader>tf` | `:TodoAIFocus` | Focus the attached agent |
| `<leader>ts` | `:TodoAIScan` | Ask the agent to resolve every `AGENT:` comment |

Selecting code and asking about it from the agent's pane works too: the agent runs `todo-ai context` to read your selection.

### The `todo-ai` command

```
todo-ai context                 current file, cursor, last selection, buffers, diagnostics
todo-ai open <path>[:a[-b]]     show a file, highlighting lines a..b
todo-ai diff                    open the diff review
todo-ai reload                  re-read changed buffers
todo-ai slides <deck.md>        show a deck above the code, each slide with its code
todo-ai which                   print the chosen editor and why
```

### Slides

A deck is markdown with slides separated by `---`. A slide names the code to show beneath it with `<!-- code: path:12-30 -->`. `todo-ai slides deck.md` opens it in a split above your code window (`slides_height`, default 40%); `l`/`h` move between slides and `q` closes. Mermaid diagrams in slides render like in any markdown buffer.

It finds the editor by, in order: the editor attached to this agent, the only editor in the agent's tab, then the nearest editor by directory, all within the agent's workspace/session. When that is ambiguous it fails and lists the candidates; run `:TodoAI` in the editor you want.

### AGENT comments

```python
# AGENT: add input validation
def process(data):
    return data.upper()
```

`<leader>ts` asks the agent to resolve them all.

## Configuration

```lua
require("todo-ai").setup({
  agent = "claude",          -- started when none exists: a herdr agent kind, or the tmux command
  split = "right",           -- "right" | "down"
  agent_commands = { "claude", "pi", "codex", "opencode", "gemini", "amp" }, -- tmux discovery
  tag = "AGENT",
  reload_interval_ms = 1000,
})
```

See **[INSTALL.md](INSTALL.md)** for setup.

## Development

```
make test                     Run tests
make test-single FILE=...     Run one test file
make lint                     Find dead Lua code
```

## License

MIT
