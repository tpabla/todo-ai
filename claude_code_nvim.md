# Technical Design: Multi-Harness Neovim Integration

## Overview

Extend todo-ai to support multiple AI agent harnesses (pi, Claude Code) behind a unified Neovim interface. The user selects their harness in config; the plugin adapts its launch strategy, communication mechanism, and integration layer accordingly.

The Neovim-side experience stays identical regardless of harness: same keybindings, same commands, same state directory contract. What changes is the _adapter_ — how the plugin talks to the agent and how the agent talks back to Neovim.

## Goals

1. **Harness-agnostic Neovim plugin** — `:TodoAI`, `:TodoAIScan`, visual mode, etc. work the same regardless of harness.
2. **Swappable adapters** — a `harness` config key selects `"pi"` or `"claude_code"`, each with its own launch and integration strategy.
3. **Feature parity** — both harnesses get: file opening, buffer auto-reload, diff review, context injection, and scan.
4. **Minimal Lua changes** — the existing Lua core handles tmux, state, and socket management. Adapter differences live in the integration layer (extension for pi, hooks/MCP/skills for Claude Code).

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Neovim Plugin (Lua)                  │
│                                                         │
│  config.lua ── harness = "claude_code" | "pi"           │
│  init.lua   ── state dir, socket, tmux, remote_*()      │
│  visual.lua ── selection capture                        │
│                                                         │
│  Adapter dispatch:                                      │
│    _build_cmd()  → delegates to harness-specific launch │
│    send_prompt() → writes prompt.md (pi) or noop (cc)   │
│    scan()        → writes __SCAN__ (pi) or noop (cc)    │
└────────────┬──────────────────────────┬─────────────────┘
             │                          │
     ┌───────▼───────┐         ┌───────▼────────┐
     │  Pi Adapter    │         │ Claude Code    │
     │               │         │ Adapter         │
     │ extension/    │         │                │
     │  neovim.ts    │         │ Hooks:         │
     │               │         │  PostToolUse   │
     │ - polls state │         │  → checktime   │
     │ - registers   │         │  → open buffer │
     │   tools       │         │                │
     │ - injects     │         │ MCP Server:    │
     │   context     │         │  neovim tool   │
     │ - auto-reload │         │  get_context   │
     │               │         │                │
     │ (unchanged    │         │ Skill:         │
     │  from today)  │         │  /scan         │
     └───────────────┘         │                │
                               │ CLAUDE.md:     │
                               │  workflow rules│
                               └────────────────┘
```

## State Directory Contract

Both adapters share the same state directory layout. This is the interface between Neovim and the agent.

```
/tmp/todo-ai-<sha256(cwd)[:16]>/
├── nvim-socket    # Neovim's RPC server address (written by Lua, read by adapter)
├── pane-id        # Tmux pane ID of the agent (written by both sides)
├── prompt.md      # Prompt from Neovim → agent (pi adapter only)
└── prompt.md.tmp  # Atomic write staging
```

Claude Code does not use `prompt.md` — the user types directly into the Claude Code CLI. The socket and pane-id files are shared.

## Configuration

### Lua Config Changes

```lua
-- config.lua
M.defaults = {
    harness = 'claude_code',  -- 'pi' | 'claude_code'
    tag = 'AGENT',
    pane_width = 80,

    -- Pi-specific
    pi_extra_args = {},

    -- Claude Code-specific
    claude_extra_args = {},
    claude_model = nil,       -- override model, e.g. 'sonnet'
}
```

### Claude Code Settings

The Claude Code adapter is delivered as a **plugin** that bundles hooks, an MCP server, and a skill. Users install it and the plugin registers everything automatically.

```
todo-ai/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── hooks.json
├── mcp-server/
│   ├── package.json
│   └── server.ts
├── skills/
│   └── scan/
│       └── SKILL.md
├── .mcp.json
├── extension/
│   └── neovim.ts         # (existing pi adapter, unchanged)
├── lua/
│   └── todo-ai/
│       ├── init.lua
│       ├── config.lua
│       └── visual.lua
└── plugin/
    └── todo-ai.vim
```

## Claude Code Adapter — Component Design

### 1. PostToolUse Hook — Buffer Auto-Reload

When Claude Code edits or writes a file, trigger `:checktime` in Neovim so buffers refresh.

**`hooks/hooks.json`:**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-edit.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**`hooks/post-edit.sh`:**

```bash
#!/bin/bash
set -euo pipefail

# Derive state dir the same way Lua does (sha256 of cwd, first 16 chars)
CWD=$(jq -r '.cwd' < /dev/stdin)
HASH=$(printf '%s' "$CWD" | shasum -a 256 | cut -c1-16)
STATE_DIR="/tmp/todo-ai-${HASH}"
SOCKET_FILE="${STATE_DIR}/nvim-socket"

[ -f "$SOCKET_FILE" ] || exit 0

NVIM_SOCKET=$(cat "$SOCKET_FILE")
[ -n "$NVIM_SOCKET" ] || exit 0

# Reload buffers
nvim --server "$NVIM_SOCKET" --remote-expr 'execute("silent! checktime")' 2>/dev/null || true

# Also open the edited file in Neovim
FILE_PATH=$(echo "$CWD" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
# Note: stdin is already consumed; file_path extraction needs restructuring
# See implementation notes below

exit 0
```

**Implementation note:** The hook receives JSON on stdin. Since stdin can only be read once, the script should read it into a variable first, then extract both `cwd` and `tool_input.file_path`:

```bash
#!/bin/bash
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
HASH=$(printf '%s' "$CWD" | shasum -a 256 | cut -c1-16)
STATE_DIR="/tmp/todo-ai-${HASH}"
SOCKET_FILE="${STATE_DIR}/nvim-socket"

[ -f "$SOCKET_FILE" ] || exit 0
NVIM_SOCKET=$(cat "$SOCKET_FILE")
[ -n "$NVIM_SOCKET" ] || exit 0

# Reload all buffers
nvim --server "$NVIM_SOCKET" --remote-expr 'execute("silent! checktime")' 2>/dev/null || true

# Open the specific file if we have a path
if [ -n "$FILE_PATH" ]; then
    ESCAPED=$(printf '%s' "$FILE_PATH" | sed "s/'/\\\\'/g")
    nvim --server "$NVIM_SOCKET" --remote-expr \
        "execute(\"lua require('todo-ai').remote_open('${ESCAPED}', 1)\")" 2>/dev/null || true
fi

exit 0
```

### 2. MCP Server — Neovim Tool

An MCP server gives Claude Code the ability to **proactively** interact with Neovim: open files at specific lines, trigger diff review, and query editor context.

**Transport:** stdio (local process, launched by Claude Code)

**`.mcp.json`:**

```json
{
    "mcpServers": {
        "neovim": {
            "type": "stdio",
            "command": "node",
            "args": ["${CLAUDE_PLUGIN_ROOT}/mcp-server/dist/server.js"],
            "env": {
                "TODO_AI_TAG": "AGENT"
            }
        }
    }
}
```

**Tools exposed:**

#### `neovim_open_file`

Opens a file in the connected Neovim instance, optionally jumping to a line or searching for a pattern.

```
Parameters:
  path:   string (required) — file path to open
  line:   number (optional) — line number to jump to
  search: string (optional) — pattern to search for (overrides line if found)

Returns:
  "Opened <path> at line <N>" | "Neovim not connected" | "Error: ..."
```

#### `neovim_diff_review`

Triggers `:DiffviewOpen` in Neovim.

```
Parameters: (none)

Returns:
  "Opened diff review in Neovim" | "Neovim not connected"
```

#### `neovim_get_context`

Returns the current editor state as structured data. Claude Code can use this to understand what the user is looking at.

```
Parameters: (none)

Returns: JSON
  {
    "current_file": "/path/to/file.ts",
    "cursor_line": 42,
    "open_files": ["/path/to/a.ts", "/path/to/b.ts"],
    "diagnostics": [
      { "line": 10, "severity": "ERROR", "message": "Type mismatch" }
    ]
  }
```

**Server implementation sketch (`mcp-server/server.ts`):**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";

function deriveStateDir(): string {
    const cwd = process.cwd();
    const hash = createHash("sha256").update(cwd).digest("hex").slice(0, 16);
    return `/tmp/todo-ai-${hash}`;
}

function getNvimSocket(): string | null {
    const socketFile = `${deriveStateDir()}/nvim-socket`;
    if (!existsSync(socketFile)) return null;
    const socket = readFileSync(socketFile, "utf-8").trim();
    return socket || null;
}

function nvimExec(socket: string, luaCode: string): void {
    const escaped = luaCode.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    execFileSync(
        "nvim",
        ["--server", socket, "--remote-expr", `execute("lua ${escaped}")`],
        { timeout: 5000 }
    );
}

function nvimEval(socket: string, luaExpr: string): string {
    const escaped = luaExpr.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    return execFileSync(
        "nvim",
        ["--server", socket, "--remote-expr", `luaeval("${escaped}")`],
        { timeout: 3000, encoding: "utf-8" }
    ).trim();
}

const server = new McpServer({
    name: "neovim",
    version: "1.0.0",
});

server.tool(
    "neovim_open_file",
    "Open a file in the connected Neovim editor at a specific line or search pattern",
    {
        path: z.string().describe("File path to open"),
        line: z.number().optional().describe("Line number to jump to"),
        search: z.string().optional().describe("Pattern to search for (more reliable than line numbers)"),
    },
    async ({ path, line, search }) => {
        const socket = getNvimSocket();
        if (!socket) return { content: [{ type: "text", text: "Neovim not connected" }] };

        let targetLine = line || 1;
        if (search) {
            try {
                const out = execFileSync("grep", ["-n", "-m", "1", search, path], {
                    encoding: "utf-8",
                    timeout: 3000,
                });
                const match = out.match(/^(\d+):/);
                if (match) targetLine = parseInt(match[1], 10);
            } catch {}
        }

        const safePath = path.replace(/'/g, "\\'");
        nvimExec(socket, `require('todo-ai').remote_open('${safePath}', ${targetLine})`);
        return { content: [{ type: "text", text: `Opened ${path} at line ${targetLine}` }] };
    }
);

server.tool(
    "neovim_diff_review",
    "Trigger a git diff review in Neovim using DiffviewOpen",
    {},
    async () => {
        const socket = getNvimSocket();
        if (!socket) return { content: [{ type: "text", text: "Neovim not connected" }] };

        nvimExec(socket, "require('todo-ai').remote_diff_review()");
        return { content: [{ type: "text", text: "Opened diff review in Neovim" }] };
    }
);

server.tool(
    "neovim_get_context",
    "Get current Neovim editor state: active file, cursor position, open buffers, LSP diagnostics",
    {},
    async () => {
        const socket = getNvimSocket();
        if (!socket) return { content: [{ type: "text", text: "Neovim not connected" }] };

        const json = nvimEval(socket, "require('todo-ai').remote_get_context()");
        return { content: [{ type: "text", text: json }] };
    }
);

async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}

main().catch(console.error);
```

### 3. Skill — `/scan`

Finds `AGENT:` comments in the project and presents them to Claude Code.

**`skills/scan/SKILL.md`:**

```markdown
---
name: scan
description: Find AGENT tag comments in the project and resolve them
argument-hint: "[tag]"
allowed-tools: "Bash(rg:*) Bash(grep:*) Grep"
---

Find and resolve all AGENT: (or custom tag) comments in this project.

Tag to scan for: ${1:-AGENT}

Results:

!`rg -n "${1:-AGENT}:" . 2>/dev/null || grep -rn "${1:-AGENT}:" . --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null || echo "No matches found"`

Resolve each of the above comments by implementing what they describe. After resolving each one, remove the comment.
```

### 4. Context Injection — CLAUDE.md Rules

Pi injects editor state into the system prompt on every turn via `before_agent_start`. Claude Code has no per-turn hook equivalent. Instead, we use two mechanisms:

**a) Workflow rules via CLAUDE.md (static):**

The plugin contributes a rules file that gets loaded when working in a project with todo-ai enabled.

**`.claude/rules/neovim-workflow.md`:**

```markdown
---
paths:
    - "**/*"
---

# Neovim Integration

You have access to a connected Neovim editor via the `neovim_*` MCP tools.

## Workflow Rules

- Use `neovim_open_file` when referencing specific code during conversation.
- Use `neovim_diff_review` only when the user asks to see the diff.
- Do NOT run `git commit`. The user reviews diffs in Neovim and commits manually.
- When starting work on a request, call `neovim_get_context` to see what file the user is looking at, their cursor position, open buffers, and any LSP diagnostics. Use this to inform your understanding of their intent.
```

**b) Context on demand (dynamic):**

Claude Code can call `neovim_get_context` at any time. The workflow rules above instruct it to do so at the start of each task. This is not automatic like pi's `before_agent_start`, but achieves similar results — Claude sees the current file, cursor, buffers, and diagnostics.

**Trade-off vs pi:** Pi injects context silently on every turn. With Claude Code, context is fetched on-demand via tool call, which costs a tool use but gives Claude the choice of when it's relevant. In practice, the CLAUDE.md rule ensures it checks context at the start of each task.

## Lua Changes

### `config.lua` — Add harness option

```lua
M.defaults = {
    harness = 'claude_code',  -- 'pi' | 'claude_code'
    tag = 'AGENT',
    pane_width = 80,
    pi_extra_args = {},
    claude_extra_args = {},
    claude_model = nil,
}
```

### `init.lua` — Harness-aware launch

The key change is in `_build_cmd()` and `open_pi()` (renamed to `open_agent()`). The rest of init.lua stays the same — state dir, socket, remote functions, tmux pane management are all harness-agnostic.

```lua
function M._build_cmd(initial_prompt)
    local cfg = config.config
    local harness = cfg.harness or 'claude_code'

    if harness == 'pi' then
        local cmd = { 'pi', '-e', M._extension_path(), '--resume' }
        if cfg.pi_extra_args then
            for _, arg in ipairs(cfg.pi_extra_args) do
                table.insert(cmd, arg)
            end
        end
        if initial_prompt then
            table.insert(cmd, initial_prompt)
        end
        return cmd

    elseif harness == 'claude_code' then
        local cmd = { 'claude' }
        if cfg.claude_model then
            table.insert(cmd, '--model')
            table.insert(cmd, cfg.claude_model)
        end
        if cfg.claude_extra_args then
            for _, arg in ipairs(cfg.claude_extra_args) do
                table.insert(cmd, arg)
            end
        end
        if initial_prompt then
            table.insert(cmd, '--prompt')
            table.insert(cmd, initial_prompt)
        end
        return cmd
    end

    error('todo-ai: unknown harness: ' .. harness)
end
```

The `open_pi()` function becomes `open_agent()` with backward-compatible alias:

```lua
function M.open_agent(initial_prompt)
    if not M._in_tmux() then
        error('todo-ai requires tmux. Start Neovim inside a tmux session.')
    end

    local dir = M._state_dir()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ vim.v.servername }, dir .. '/nvim-socket')

    if M._is_pane_alive() then
        if initial_prompt then
            local harness = config.get('harness') or 'claude_code'
            if harness == 'pi' then
                -- Pi reads prompt.md from state dir
                M._write_prompt(initial_prompt)
            end
            -- Claude Code: user types directly; initial_prompt only used at launch
        end
        vim.fn.system({ 'tmux', 'select-pane', '-t', M.state.tmux_pane })
        return
    end

    local cmd = M._build_cmd(initial_prompt)
    local socket = vim.v.servername
    local width = config.get('pane_width') or 80
    local tag = config.get('tag')

    local parts = {
        'env',
        'NVIM=' .. socket,
        'TODO_AI_STATE_DIR=' .. dir,
        'TODO_AI_TAG=' .. tag,
    }
    for _, arg in ipairs(cmd) do
        table.insert(parts, arg)
    end
    local shell_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, parts), ' ')

    local result = vim.trim(vim.fn.system({
        'tmux', 'split-window', '-h', '-l', tostring(width),
        '-P', '-F', '#{pane_id}',
        shell_cmd,
    }))
    if vim.v.shell_error ~= 0 or not result:match('^%%') then
        error('todo-ai: failed to create tmux pane: ' .. result)
    end
    M.state.tmux_pane = result
    vim.fn.writefile({ result }, dir .. '/pane-id')
end

-- Backward compatibility
M.open_pi = M.open_agent
```

### `send_prompt()` — Harness-aware dispatch

```lua
function M.send_prompt(text)
    local harness = config.get('harness') or 'claude_code'

    if not M._is_pane_alive() then
        M.open_agent(text)
        return
    end

    if harness == 'pi' then
        M._write_prompt(text)
    elseif harness == 'claude_code' then
        -- Send text directly to the Claude Code tmux pane via send-keys
        local escaped = text:gsub("'", "'\\''")
        vim.fn.system({ 'tmux', 'send-keys', '-t', M.state.tmux_pane, escaped, 'Enter' })
    end
end
```

### `scan()` — Harness-aware dispatch

```lua
function M.scan()
    local harness = config.get('harness') or 'claude_code'

    if not M._is_pane_alive() then
        M.open_agent()
    end

    if harness == 'pi' then
        M._write_prompt('__SCAN__')
    elseif harness == 'claude_code' then
        -- Send the /scan skill invocation to Claude Code's pane
        vim.fn.system({ 'tmux', 'send-keys', '-t', M.state.tmux_pane, '/scan', 'Enter' })
    end
end
```

### `visual.lua` — No changes needed

`visual.lua` calls `M.open_pi(prompt)` which becomes `M.open_agent(prompt)`. The prompt formatting is harness-agnostic. For Claude Code, the prompt is either passed at launch (`--prompt`) or sent via `tmux send-keys`.

## Plugin Manifest

**`.claude-plugin/plugin.json`:**

```json
{
    "name": "todo-ai-nvim",
    "description": "Neovim integration for Claude Code — open files, auto-reload buffers, diff review, and editor context via MCP",
    "version": "1.0.0",
    "author": {
        "name": "todo-ai"
    },
    "license": "MIT"
}
```

## Feature Parity Matrix

| Feature | Pi Adapter | Claude Code Adapter |
|---------|-----------|-------------------|
| Open file in Neovim | `registerTool("neovim")` → `nvimExec` | MCP tool `neovim_open_file` |
| Auto-reload buffers | `tool_execution_end` hook → `checktime` | `PostToolUse` hook → `checktime` |
| Diff review | `registerTool("neovim")` → `DiffviewOpen` | MCP tool `neovim_diff_review` |
| Editor context | `before_agent_start` → system prompt | MCP tool `neovim_get_context` (on-demand) |
| Scan for tags | `registerCommand("scan")` → `grepTag` | Skill `/scan` → `rg` |
| Send prompt from Neovim | `prompt.md` file polling | `tmux send-keys` |
| Reconnection | Socket polling (500ms) | Hook reads socket per-invocation (stateless) |
| Status indicator | `session_start` → `setStatus` | N/A (no status API in Claude Code) |
| Workflow rules | `before_agent_start` → system prompt append | CLAUDE.md / `.claude/rules/` |
| Launch agent | `pi -e neovim.ts --resume` | `claude [--model X]` |

## Communication Flow Comparison

### Pi Flow (existing)

```
Neovim ──write──→ prompt.md ──poll──→ Pi Extension
                                          │
Pi Extension ──nvim --server──→ Neovim    │
                                          │
Pi Extension ──before_agent_start──→ Pi Core (context injection)
Pi Extension ──tool_execution_end──→ Neovim (checktime)
```

### Claude Code Flow (new)

```
Neovim ──tmux send-keys──→ Claude Code CLI
                                │
Claude Code ──MCP tool call──→ MCP Server ──nvim --server──→ Neovim
Claude Code ──PostToolUse──→ Hook script ──nvim --server──→ Neovim (checktime)
Claude Code ──reads──→ CLAUDE.md (workflow rules)
Claude Code ──MCP tool call──→ MCP Server (get_context) ──nvim --server──→ Neovim
```

## Open Questions

1. **`tmux send-keys` reliability** — Sending multi-line prompts to Claude Code via `tmux send-keys` may have escaping issues with complex content (code blocks, special characters). Alternative: write to a temp file and send `cat /tmp/prompt.txt` via send-keys, or use Claude Code's `--prompt` flag (only works at launch).

2. **Context injection frequency** — Pi injects context on every turn automatically. Claude Code relies on the model choosing to call `neovim_get_context`. The CLAUDE.md rule nudges this, but it's not guaranteed. If this proves unreliable, a `PreToolUse` or `UserPromptSubmit` hook could inject context via `additionalContext` in the hook response.

3. **Visual mode with Claude Code** — When the user selects code and types an instruction, sending multi-line formatted prompts via `tmux send-keys` may need special handling. Consider base64-encoding or a file-based handoff.

4. **Claude Code `--resume`** — Pi supports `--resume` to continue an existing session. Claude Code supports `--resume` with a session ID. The plugin may need to persist the session ID in the state directory to reconnect to the same conversation.

5. **Plugin distribution** — The Claude Code plugin bundles an MCP server that needs `node_modules`. Options: ship as an npm package users install globally, use `npx` to run from registry, or bundle dependencies.

## Implementation Plan

### Phase 1: Lua Refactor (harness abstraction)

- Add `harness` to config with `'pi'` and `'claude_code'` options
- Rename `open_pi` → `open_agent`, keep alias
- Branch `_build_cmd`, `send_prompt`, `scan` on harness
- Update `plugin/todo-ai.vim` commands (keep same names/bindings)
- Update tests for new config and branching logic

### Phase 2: Claude Code MCP Server

- Scaffold `mcp-server/` with `@modelcontextprotocol/sdk`
- Implement `neovim_open_file`, `neovim_diff_review`, `neovim_get_context`
- Reuse `nvimExec`/`nvimEval`/`deriveStateDir` from existing `neovim.ts`
- Test against a running Neovim instance

### Phase 3: Claude Code Hooks

- Write `post-edit.sh` for buffer auto-reload
- Write `hooks.json` wiring `PostToolUse` → `Edit|Write`
- Test hook fires correctly and buffers reload

### Phase 4: Claude Code Skill + Rules

- Write `/scan` skill
- Write `.claude/rules/neovim-workflow.md`
- Test skill invocation and rule loading

### Phase 5: Plugin Packaging

- Create `.claude-plugin/plugin.json`
- Wire `.mcp.json` to launch MCP server from plugin root
- Bundle hooks, skills, rules under plugin structure
- Test with `claude --plugin-dir ./`
- Document installation in README/INSTALL.md

### Phase 6: Polish

- Handle edge cases in `tmux send-keys` (escaping, multi-line)
- Add `--resume` session persistence for Claude Code
- Update README with dual-harness setup instructions
