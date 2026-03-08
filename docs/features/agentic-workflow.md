# Agentic Workflow

Branch: `feature/agentic-workflow`

## Goal

Shift from inline diff accept/reject to a plan-then-edit workflow where:
1. User talks to the agent in the chat buffer
2. Agent proposes a **plan** before touching any files
3. User approves (or adjusts) the plan
4. Agent edits files on disk using SEARCH/REPLACE
5. User reviews all changes with **diffview.nvim** (git diff)
6. User commits when satisfied

Git becomes the undo mechanism. No more per-change accept/reject UI.

## Current Flow (what changes)

```
chat → LLM → JSON response → inline diff buffer → accept/reject per change
```

## New Flow

```
chat → LLM → plan (chat mode) → user approves → LLM → SEARCH/REPLACE → write to disk
                                                                              ↓
                                                              user runs :DiffviewOpen
                                                              reviews, commits, or reverts
```

## What stays

- **Chat buffer** — `:w` to send, same vim-native UX
- **TODO scanning** — `TODO: @ai` detection, project scan
- **Project context** — `context_compact`, open buffer paths, LSP diagnostics
- **Relevant buffer inclusion** — Rust reads files based on query relevance
- **SEARCH/REPLACE** — still the mechanism for applying changes
- **Rust backend** — prompt building, LLM calls, response parsing
- **Multi-provider** — Claude, OpenAI, Ollama, Claude CLI

## What changes

### 1. Two-phase responses: Plan → Execute

The LLM currently decides between `mode: "chat"` and `mode: "changes"`. Add a third mode:

```json
{"mode": "plan", "plan": "1. Add error handling to fetch_data...", "files": ["api.py", "tests/test_api.py"]}
```

**Flow:**
- User asks for changes → LLM responds with `mode: "plan"`
- Plan is displayed in chat buffer
- User replies "yes" / "go" / "do it" (or adjusts: "skip the tests part") → LLM responds with `mode: "changes"` and the SEARCH/REPLACE blocks
- If user just wants to chat, LLM still uses `mode: "chat"` as before

**System prompt changes:**
- When user asks for code changes, ALWAYS plan first
- Include which files will be touched and what each change does
- Keep plans concise — bullet list, not essay
- When user approves, execute with SEARCH/REPLACE
- If user asks follow-up questions about the plan, stay in chat mode

### 2. Write changes to disk (not inline diff)

After receiving `mode: "changes"`, instead of showing inline diffs:
1. Apply SEARCH/REPLACE to file contents
2. Write the modified files to disk
3. Notify user: "Applied 3 changes to 2 files. Run `:DiffviewOpen` to review."

**Revert path:** `git checkout -- .` or reject individual files in diffview.

### 3. Remove inline diff system

Delete `diff.lua` and its 800+ lines. The accept/reject/next/prev change navigation, virtual text overlays, and quickfix population are all replaced by diffview.

### 4. Multi-file support

Current SEARCH/REPLACE is single-file. Extend the response schema:

```json
{
  "mode": "changes",
  "changes": [
    {"file": "src/api.py", "search": "...", "replace": "..."},
    {"file": "src/api.py", "search": "...", "replace": "..."},
    {"file": "tests/test_api.py", "search": "...", "replace": "..."}
  ],
  "explanation": "Added error handling and tests"
}
```

For new files:
```json
{"file": "src/utils.py", "search": "", "replace": "def helper():\n    pass\n"}
```

Empty `search` = create new file with `replace` as content.

## Implementation Plan

### Phase 1: Plan mode

1. **Rust `schema.rs`** — add `"plan"` as valid mode, add `plan` and `files` fields
2. **Rust `prompts/system.md`** — update system prompt: always plan before changing
3. **Lua `unified_prompt.lua`** — handle `mode: "plan"` responses (display in chat)
4. **Lua `chat.lua`** — no structural changes, plans are just chat messages

### Phase 2: Write to disk

1. **Lua `unified_prompt.lua`** — on `mode: "changes"`, apply and write to disk instead of calling `diff.show()`
2. **Lua `search_replace.lua`** — add `apply_to_file(path, changes)` that reads file, applies changes, writes back
3. **Rust `schema.rs`** — add `file` field to change objects
4. **Rust `parser.rs`** — parse per-file change blocks

### Phase 3: Remove inline diff

1. Delete `lua/todo-ai/diff.lua`
2. Remove diff keymaps from `plugin/todo-ai.vim` (`<leader>ta`, `<leader>tr`)
3. Remove diff commands (`TodoAIAccept`, `TodoAIReject`)
4. Add `:TodoAIDiffview` command (just calls `:DiffviewOpen`)
5. Run `make lint` to catch any remaining references

### Phase 4: Clean up

1. Remove `3 changes max` rule from search_replace_rules — agent can now make as many changes as needed since diffview handles review
2. Update keybindings table
3. Update README

## Keybindings (after)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>tc` | `:TodoAIChat` | Open chat |
| `<leader>ts` | `:TodoAIScan` | Scan buffer for TODOs |
| `<leader>tS` | `:TodoAIScanProject` | Scan project for TODOs |
| `<leader>td` | `:DiffviewOpen` | Review changes |
| `<leader>tg` | `:TodoAIGenerateContext` | Generate project context |

## Dependencies

- [diffview.nvim](https://github.com/sindrets/diffview.nvim) — listed as optional dependency, error if user tries `:TodoAIDiffview` without it

## Open Questions

- Should the agent auto-stage changes or leave everything unstaged?
  - **Lean: leave unstaged.** User controls what goes in each commit.
- Should there be a way to undo the last set of changes without git?
  - **Lean: no.** Git is the undo. Keep it simple.
- Should plans require explicit approval or should there be a "just do it" mode?
  - **Lean: always plan.** User can configure `auto_approve = true` later if they want to skip.
- What about TODO scanning — should it also plan first?
  - **Lean: yes.** Scan finds TODOs → agent plans how to resolve them → user approves → changes written.
