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

1. `setup()` publishes this editor to `/tmp/todo-ai/sessions/<pid>/editor.json` (socket, cwd, pid, name)
2. `:TodoAI` lists agent panes from tmux; it spawns when there are none and otherwise always asks which to connect to
3. The agent resolves an editor by path ancestry (`shared/pairing.js`) and polls its session dir: socket changes → 🟢/🔴, prompt files → `sendUserMessage`
4. Extension injects editor state + workflow rules on every prompt (`before_agent_start`)
5. Pi edits files → extension calls `checktime` → buffers reload
6. Pi uses `open_file` only when referencing specific code during conversation
7. Pi uses `diff_review` only when the user asks to see the diff
8. Pi MUST NOT commit changes — user reviews diff and commits themselves

### Pairing

The agent and the editor need not share a directory: a common layout is one
agent at a project root with several worktrees under it and nvim inside one of
them. Pairing is therefore by **path ancestry**, never by directory equality.

- Editors publish `/tmp/todo-ai/sessions/<pid>/editor.json`; `prompt.md` lives
  in the same directory for `prompt_file` harnesses
- Agents tag their pane via `shared/tag-pane.sh`: `@todo-ai-agent`,
  `@todo-ai-dir` (a real directory), `@todo-ai-name`, `@todo-ai-session`
- **Tags are metadata, never liveness.** A tag outlives the agent that wrote
  it, so candidates are derived from the live process tree: the pane's
  foreground command, else any descendant whose basename matches a harness
  `bin`. Matching is basename-exact, so `grep claude` in a pane is not an agent
- A tagged pane that has fallen back to a shell is stale: excluded, and its
  `@todo-ai-*` options are cleared so every other editor stops seeing it too.
  A tagged pane running some other non-shell process is trusted, which covers
  an agent behind a wrapper that reports `node`
- `registry.candidates()` is a pure function of current state (one
  `tmux list-panes` + one `ps`), cached nowhere, so a closed pane or an exited
  agent simply stops being a candidate
- The attached pane is a *choice*, re-verified against live state on every use
  (`init.attached_pane()`); a pane that dies between picking and sending can
  never receive keystrokes
- `:TodoAI` ranks candidates exact > nearest parent > nearest child > unrelated,
  and never hides an unrelated pane — it ranks it last
- Picker lines are built by `init._describe_pane()` and label each pane with the
  agent's session name from `#{pane_title}` (Claude Code writes `✳ <summary>`),
  dropping a title that is just the hostname or the running command
- An agent that has not tagged itself yet is still found by matching its pane
  process against the harness `process_pattern`
- Paths crossing the boundary are always absolute, resolved by the *sender*
  against its own cwd; `remote_open` refuses a relative path rather than
  resolving it against nvim's cwd
- Ancestry comparison resolves symlinks, so tmux's `/var/...` matches nvim's
  `/private/var/...` on darwin
- Editors are pruned from the registry when their pid is gone -- lazily by any
  agent that resolves, and eagerly by `setup()` so entries left by an editor
  that was SIGKILLed do not accumulate; an editor outside the agent's tree is
  never paired with
- Pane liveness checked via `tmux list-panes` (not `display-message` — exits 0 for dead panes)
- Multiple projects = multiple agents, no conflicts

Adding a harness: see [HARNESS.md](HARNESS.md).

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
