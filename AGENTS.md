# TODO-AI Development Guidelines

## Architecture

todo-ai pairs Neovim with any coding agent running beside it in herdr or tmux.
It has no harness-specific code: agents drive the editor through one CLI, and
the editor talks to agents through the multiplexer.

### Components

- **`bin/todo-ai`** — CLI agents run (`context`, `open`, `diff`, `reload`, `which`). A shell wrapper around `nvim -l`
- **`lua/todo-ai/cli.lua`** — CLI logic: editor resolution, argument parsing, rpc to the editor
- **`lua/todo-ai/init.lua`** — Attach/spawn/send/focus + `remote_*` functions the CLI calls
- **`lua/todo-ai/herdr.lua`**, **`tmux.lua`** — Multiplexer backends: `list`, `spawn`, `prompt`, `focus`, `location`
- **`lua/todo-ai/visual.lua`** — Visual selection → prompt
- **`lua/todo-ai/config.lua`** — Configuration
- **`plugin/todo-ai.vim`** — Commands + keymaps
- **`skills/neovim/`** — Tells agents when to call `todo-ai`; **`skills/scan/`** — resolves `AGENT:` comments

### Flow

1. `:TodoAI` lists agents in the editor's herdr workspace / tmux session; spawns one when there are none, otherwise always asks
2. Attaching writes `/tmp/todo-ai/agents/<agent pane id>` containing this editor's socket
3. nvim → agent: `herdr agent prompt` / `tmux send-keys`
4. agent → nvim: `todo-ai <command>` connects to the editor's socket over msgpack-rpc and calls `require('todo-ai').remote_*`
5. Buffers reload via `autoread` + a `checktime` timer while attached
6. The agent MUST NOT commit — the user reviews the diff and commits

### Editor resolution (`cli.resolve`)

First step yielding exactly one live editor wins:

1. **attached** — `/tmp/todo-ai/agents/$HERDR_PANE_ID|$TMUX_PANE` names a live socket
2. **same tab** — exactly one editor in the agent's herdr tab / tmux window
3. **cwd** — nearest by path ancestry: exact > nearest parent > nearest child
4. otherwise error listing the candidates; never guess

- An agent inside herdr/tmux only sees editors in its own workspace/session
- Editors are found from nvim's default sockets; one without this plugin loaded is invisible
- Pane ids, tabs and workspaces are read live on every call; nothing is cached
- Paths crossing the boundary are absolute, resolved by the sender; `remote_open` refuses relative paths
- Ancestry compares realpaths, so `/var/...` matches `/private/var/...` on darwin

### Backends

- herdr wins when both are present (herdr panes can run inside tmux)
- herdr detects agents itself; tmux matches `pane_current_command` against `agent_commands`
- herdr scoping uses `herdr pane current`, not `$HERDR_WORKSPACE_ID`, which goes stale when a pane moves
- `tmux display-message` exits 0 for dead panes — check for empty output

## Principles

- **Harness-agnostic.** No code for a particular agent. New agents need only the skill or one instruction line.
- **The agent pulls, the editor pushes.** No hooks, MCP servers or extensions.
- **Fail fast.** `error()` not `vim.notify` for failures; the CLI exits non-zero with the reason.
- **Never commit.** The agent must not run `git commit`.

## Code guidelines

- Use `vim.api.nvim_*` over `vim.fn.*`
- Side effects are injected (`run` in backends, `deps` in `cli` and `init`) so logic is testable without herdr, tmux or a second nvim

## Testing

```bash
make test          # plenary tests
make lint          # dead code detection
```
