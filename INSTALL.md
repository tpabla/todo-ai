# Installation

## Requirements

- Neovim **0.10+**, running inside [herdr](https://herdr.dev) or tmux
- A coding agent: Claude Code, pi, codex, …
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) for `todo-ai diff`

## 1. Neovim plugin

```lua
-- lazy.nvim
{
  "tpabla/todo-ai",
  dependencies = { "sindrets/diffview.nvim" },
  opts = {},
}
```

The plugin must be loaded in every editor an agent should reach: `todo-ai` calls into it over rpc.

## 2. The `todo-ai` command

Put `bin/todo-ai` on your `PATH`:

```bash
ln -s ~/.local/share/nvim/lazy/todo-ai/bin/todo-ai ~/.local/bin/todo-ai
```

## 3. The skills

The `neovim` skill tells agents when to call `todo-ai`; `scan` resolves `AGENT:` comments.

**Claude Code** — install as a plugin:

```bash
claude plugin marketplace add ~/.local/share/nvim/lazy/todo-ai
claude plugin install todo-ai-nvim@todo-ai
```

**pi, codex and other Agent Skills harnesses** — link them into `~/.agents/skills/`:

```bash
mkdir -p ~/.agents/skills
ln -s ~/.local/share/nvim/lazy/todo-ai/skills/neovim ~/.agents/skills/neovim
ln -s ~/.local/share/nvim/lazy/todo-ai/skills/scan ~/.agents/skills/scan
```

**Anything else** — add one line to its instructions file: *"Use the `todo-ai` command (see `todo-ai --help`) to show code in the user's Neovim and read their selection."*

To skip permission prompts in Claude Code, allow `Bash(todo-ai:*)`.

## Verify

1. In herdr or tmux, open Neovim and press `<leader>tc` — an agent starts beside it
2. Select a few lines, press `<leader>ti`, ask "what does this do?"
3. In the agent's pane: `todo-ai which` prints this editor and `(attached)`

## Troubleshooting

**`todo-ai: run Neovim inside herdr or tmux`** — start Neovim inside one.

**`todo-ai: no editor running`** — no editor with this plugin loaded is running. Check `:lua =require('todo-ai').remote_identity()` in Neovim.

**`todo-ai: N editors match …`** — run `:TodoAI` in the editor you want, or pass `--editor <socket>`.

**tmux: agent not listed** — its process name is not in `agent_commands`; check with `tmux display -p '#{pane_current_command}'` in its pane.

**Buffers not reloading** — they reload every `reload_interval_ms` while attached; `todo-ai reload` forces it.
