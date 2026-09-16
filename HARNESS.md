# Adding a harness

A harness is the agent CLI todo-ai drives (Claude Code, pi, …). Adding one is a
data change: write a spec table that satisfies the contract and register it. No
other file in the plugin compares harness names — `tests/plenary/connect_spec.lua`
asserts that mechanically, so a new harness cannot reintroduce branching.

## 1. Write the spec

Create `lua/todo-ai/harness/<name>.lua` returning a table. The contract lives in
`lua/todo-ai/harness/interface.lua` (`FIELDS`), which is the single source of
truth — `interface.validate()` checks against it and `interface.describe()`
prints it.

| Field | Type | Purpose |
|---|---|---|
| `name` | string | Identifier used as the `harness` config value |
| `label` | string | Human label shown in the connect picker |
| `bin` | string | Executable, checked before spawning |
| `process_pattern` | string | Matches a pane's process, so an agent that has not tagged itself yet is still discoverable |
| `deliver` | `'send_keys'` \| `'prompt_file'` \| function | How a prompt reaches the agent |
| `scan_prompt` | string | Text delivered by `:TodoAIScan` |
| `build_cmd` | `(opts) -> argv` | Full command line |
| `resume_args` | `(session_id) -> argv` | Target one past session |
| `installed` | `() -> boolean, hint` | Install state; `hint` is shown when false |
| `install` | `(notify) -> boolean` | Perform the install |

`build_cmd(opts)` receives `{ plugin_root, extension_path, initial_prompt,
session_id, session_mode }`. Read harness-specific options straight from
`todo-ai.config` (require it *inside* the function, not at file scope, so the
spec stays reload-safe).

```lua
-- lua/todo-ai/harness/myagent.lua
return {
    name = 'myagent',
    label = 'myagent',
    bin = 'myagent',
    process_pattern = 'myagent',
    deliver = 'send_keys',
    scan_prompt = '/scan',

    build_cmd = function(opts)
        local config = require('todo-ai.config')
        local cmd = { 'myagent' }
        if opts.session_id then
            vim.list_extend(cmd, { '--resume', opts.session_id })
        end
        vim.list_extend(cmd, config.get('myagent_extra_args') or {})
        if opts.initial_prompt then table.insert(cmd, opts.initial_prompt) end
        return cmd
    end,

    resume_args = function(id) return { '--resume', id } end,
    installed = function() return true end,
    install = function(notify) notify('nothing to install'); return true end,
}
```

Register it by adding the name to `BUILTINS` in `lua/todo-ai/harness/init.lua`,
or from your own config:

```lua
require('todo-ai.harness').register(require('my.harness.spec'))
require('todo-ai').setup({ harness = 'myagent' })
```

A spec missing a field, or with a field of the wrong type, fails at
`register()` with a message naming the field — not later at a call site.

## 2. Make the agent discoverable

The agent side needs two things, both already implemented and shared:

- **Tag its pane** — call `shared/tag-pane.sh <label> [session-id] [name]` from
  wherever the harness can run a command on startup or per prompt (a hook, an
  extension, a wrapper). It writes the `@todo-ai-*` pane options, which supply
  the picker's metadata (name, session id).

  Tagging is optional for discovery and never establishes liveness: a pane
  counts as an active agent when its foreground command, or any descendant of
  its `pane_pid`, has a basename equal to the spec's `bin` or
  `process_pattern`. Set `process_pattern` to what the process actually reports
  (`ps -eo comm`), which may be `node` rather than your CLI's name. If it does
  report a generic runtime name, tag the pane — a tagged pane running a
  non-shell process is trusted, while a tagged pane sitting at a shell prompt
  is treated as stale and untagged.
- **Find the editor** — use `shared/pairing.js` (`resolveEditor`, `toAbsolute`).
  Do not reimplement pairing: nvim may be in a subdirectory of the agent's cwd
  (a worktree below a project-root agent), so pairing is by path ancestry, and
  `toAbsolute` is what keeps `remote_open` from receiving a relative path it
  must refuse. For shell integrations, `shared/editor-cli.js socket|abs` exposes
  the same logic.

## 3. Test it

`tests/plenary/harness_spec.lua` validates every registered spec against the
contract, so a new harness is covered by that suite as soon as it is registered.
