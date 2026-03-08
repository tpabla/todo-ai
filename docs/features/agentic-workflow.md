# Agentic Workflow

Branch: `feature/agentic-workflow`

## Goal

Todo-ai becomes a thin Neovim UI that wraps **pi coding agent** via its RPC protocol. Pi handles all file editing, tool execution, retries, and context management. Todo-ai provides:

1. Chat buffer in Neovim (`:w` to send)
2. Neovim-specific context (open buffers, TODOs, LSP diagnostics)
3. Streaming response display
4. Diffview integration for reviewing changes

## Architecture

```
Neovim (todo-ai)                    pi (RPC subprocess)
┌──────────────┐                   ┌──────────────────┐
│ Chat buffer  │──── prompt ──────→│                  │
│              │←── text_delta ────│  LLM + Tools     │
│ TODO scanner │                   │  (read, write,   │
│ LSP context  │                   │   edit, bash)    │
│ Open buffers │                   │                  │
└──────────────┘                   └──────────────────┘
                                          │
                                    writes files directly
                                          │
                                    user runs :DiffviewOpen
```

## What pi gives us for free

- **File editing** — read, write, edit tools (no SEARCH/REPLACE parsing needed)
- **Streaming** — text_delta events for live response display
- **Session management** — conversation history, compaction, forking
- **Multi-provider** — anthropic, openai, google, ollama, etc.
- **Retries** — auto-retry on rate limits and transient errors
- **Tool execution** — bash commands, file operations
- **Planning** — use `--append-system-prompt` or a pi skill to enforce plan-first behavior

## What todo-ai provides

- **Chat UI** — vim-native buffer, `:w` to send, markdown rendering
- **Neovim context** — inject open buffer paths, LSP diagnostics, project context into prompts
- **TODO scanning** — find `TODO: @ai` comments, feed them as prompts to pi
- **Diffview shortcut** — `:TodoAIDiff` opens diffview to review pi's file changes

## What gets deleted

| Module | Lines | Reason |
|--------|-------|--------|
| `rust/` (entire backend) | ~3000 | Pi handles LLM calls, prompt building, parsing, retries |
| `diff.lua` | ~870 | Diffview replaces inline diff UI |
| `search_replace.lua` | ~60 | Pi's edit tool handles file modifications |
| `unified_prompt.lua` | ~400 | Simplifies to context gathering + pi RPC call |
| `backend.lua` | ~200 | Replaced by pi RPC client |

## What stays (simplified)

| Module | Purpose |
|--------|---------|
| `chat.lua` | Chat buffer UI, streaming display, `:w` to send |
| `scanner.lua` | TODO: @ai detection |
| `context_compact.lua` | Project context generation |
| `lsp_context.lua` | LSP diagnostics for context |
| `config.lua` | Plugin configuration |
| `visual.lua` | Visual mode selection → prompt |
| `init.lua` | Setup, commands, keymaps |
| `logger.lua` | Debug logging |

## New module: `pi_client.lua`

Replaces `backend.lua`. Spawns pi in RPC mode and communicates via JSON lines on stdin/stdout.

```lua
local M = {}

function M.start(config)
  -- Spawn: pi --mode rpc --provider <x> --model <y> --append-system-prompt <context>
  M.job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data) M.on_event(data) end,
    on_exit = function() M.job = nil end,
  })
end

function M.prompt(message)
  -- {"type": "prompt", "message": "..."}
  M.send({ type = "prompt", message = message })
end

function M.abort()
  M.send({ type = "abort" })
end

function M.on_event(event)
  -- Route events to chat buffer:
  -- text_delta → append to chat display
  -- tool_execution_start → show "Editing file.lua..."
  -- tool_execution_end → show result
  -- agent_end → notify "Done. :DiffviewOpen to review."
end
```

## Prompt flow

1. User types in chat buffer, hits `:w`
2. `chat.lua` gathers Neovim context (open buffers, LSP, project context)
3. Prepends context to user message
4. Sends `{"type": "prompt", "message": "<context>\n\n<user message>"}` to pi
5. Pi streams back events → chat buffer displays them live
6. Pi calls tools (edit, write) → files change on disk
7. On `agent_end` → notify user to run `:DiffviewOpen`

## TODO scanning flow

1. `scanner.lua` finds `TODO: @ai` comments
2. Each TODO becomes a prompt: "Resolve this TODO in <file>:<line>: <instruction>"
3. Context (file content, surrounding code, LSP) is prepended
4. Sent to pi as a normal prompt
5. Pi edits the files directly

## Planning behavior

Use pi's `--append-system-prompt` at startup:

```
When the user asks you to make changes, first propose a plan listing which
files you'll modify and what you'll do in each. Wait for the user to approve
before making any edits. Keep plans concise — bullet list, not essay.
```

Or create a pi skill at `.pi/agent/skills/plan-first/SKILL.md`.

## Configuration

```lua
require('todo-ai').setup({
  -- Pi settings
  pi_provider = 'anthropic',
  pi_model = 'sonnet',
  pi_thinking = 'medium',
  pi_extra_args = {},  -- additional CLI args

  -- Context
  include_open_buffers = true,
  include_lsp_diagnostics = true,
  include_project_context = true,

  -- UI
  chat_window_width = 60,
  chat_window_position = 'right',
})
```

## Keybindings

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>tc` | `:TodoAIChat` | Open chat |
| `<leader>ts` | `:TodoAIScan` | Scan buffer TODOs → send to pi |
| `<leader>tS` | `:TodoAIScanProject` | Scan project TODOs |
| `<leader>td` | `:DiffviewOpen` | Review changes |
| `<leader>ti` | `:TodoAIVisual` | Process visual selection |
| `<leader>tx` | `:TodoAIAbort` | Abort current pi operation |

## Dependencies

- [pi coding agent](https://github.com/mariozechner/pi-coding-agent) — required, must be in PATH
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) — optional, for reviewing changes
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) — for tests

## Implementation phases

### Phase 1: Pi RPC client
- New `pi_client.lua` — spawn pi, send prompts, handle events
- Wire chat buffer `:w` → pi prompt
- Stream responses back to chat buffer display
- Show tool execution status (editing file X, running command Y)

### Phase 2: Context injection
- Gather open buffer paths, LSP diagnostics, project context
- Prepend to user message before sending to pi
- Plan-first system prompt via `--append-system-prompt`

### Phase 3: Delete old backend
- Remove `rust/` entirely
- Remove `diff.lua`, `search_replace.lua`, `backend.lua`, `unified_prompt.lua`
- Remove `build-rust` from Makefile
- Update tests, README

### Phase 4: TODO scanning via pi
- Scan finds TODOs → formats as prompts → sends to pi
- Pi edits files directly
- User reviews with diffview
