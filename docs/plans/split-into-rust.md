# Branch: taran/split-into-rust

Split todo-ai Neovim plugin from 100% Lua into Rust backend + Lua frontend.

Rust handles: schemas, LLM communication, parsing, validation, context gathering.
Lua handles: Neovim display (chat UI, diff, keymaps, buffer management).

IPC: JSON-RPC 2.0 over Unix domain sockets.

## Completed

### Phase 0: Scaffolding
- `rust/Cargo.toml` — binary crate with serde, serde_json, tokio, clap, chrono
- `rust/src/main.rs` — tokio runtime, Unix socket listener, JSON-RPC dispatch loop
- `rust/src/rpc.rs` — RpcRequest/RpcResponse/RpcError types, Handler with dispatch
- `lua/todo-ai/backend.lua` — IPC client (start/stop sidecar, request/notify over socket)
- Makefile targets: `build-rust`, `test-rust`

### Phase 1: Config + Logger
- `rust/src/config.rs` — Config struct with defaults, from_params() overlay merge, get/set, project config loading (4 tests)
- `rust/src/logger.rs` — File logging to /tmp/todo-ai.log with levels, handles forwarded Lua logs (2 tests)
- `rpc.rs` updated — Handler holds Config + Logger state, initialize/shutdown/get_config/set_config/log methods (5 tests)
- `lua/todo-ai/logger.lua` — forwards to Rust backend when available

### Phase 2: Schema + Prompt Config
- `rust/src/schema.rs` — validate_response() for mode/filename/changes/explanation, format_validation_errors() (11 tests)
- `rust/src/prompt.rs` — get_system_prompt(), build_user_prompt() with visual/todo/project_scan/chat builders (8 tests)
- `rust/prompts/*.md` — 5 markdown files loaded via include_str!() at compile time:
  - `system.md` — main system prompt (mode detection, JSON schema, file handling)
  - `search_replace_rules.md` — numbered rules for search/replace
  - `examples.md` — good/bad response examples
  - `todo_instructions.md` — TODO-specific instructions
  - `project_scan_instructions.md` — project scan instructions

### Phase 3: Parser
- `rust/src/parser.rs` — full port of parser.lua (~490 lines → ~420 lines Rust)
- `ParseResult` struct with all fields (mode, filename, changes, code, thinking, etc.)
- `detect_format()` — JSON, XML, markdown, plain code, mixed format detection
- `extract_thinking_tags()` / `remove_thinking_tags()` / `format_thinking()` — 11 tag types
- `parse_json_response()` — direct field assignment, incomplete/invalid JSON error handling
- `parse_xml_structured()` — code/explanation extraction, all-tags section parsing
- `parse_markdown_formatted()` — code blocks, JSON-in-markdown detection with warning
- `parse_generic()` — fallback code/explanation separation
- `looks_like_code()` — heuristic with 22 code patterns
- Claude hint handling for format detection override
- Added `regex = "1"` to Cargo.toml
- 24 parser tests

### Phase 4: Providers + HTTP
- `rust/src/http.rs` — reqwest-based async HTTP client with timeout and redirect support
- `rust/src/retry.rs` — exponential backoff with jitter, retryable error detection (timeout, 429, 502-504)
- `rust/src/providers/mod.rs` — `Provider` async trait (`complete` + `chat`), `get_provider()` registry
- `rust/src/providers/claude.rs` — Anthropic API (x-api-key, anthropic-version header, content extraction)
- `rust/src/providers/openai.rs` — OpenAI API (Bearer token, chat/completions endpoint)
- `rust/src/providers/ollama.rs` — Ollama API (generate + chat endpoints, no auth)
- `rust/src/providers/claude_cli.rs` — Claude CLI provider (spawns `claude -p` via tokio::process, stdin piping)
- `rust/src/rpc.rs` — added async `complete` RPC: context → build prompt → call provider → parse → validate → return
  - dispatch() is now async
  - Returns validation_errors in result if schema fails (Lua handles display)
- `lua/todo-ai/unified_prompt.lua` — `send_to_provider()` now uses Rust backend when available, falls back to Lua providers
- Added deps: `reqwest` (rustls-tls), `rand`, `async-trait`
- 10 new tests (4 claude_cli, 4 retry, 1 http, 1 rpc complete)

**Current test count: 64 passing**

### Other changes
- `lua/todo-ai/providers/claude_cli.lua` — new provider using `claude -p` CLI (OAuth subscription auth, stdin piping for large prompts)
- `lua/todo-ai/providers/init.lua` — added claude-cli to registry
- `lua/todo-ai/config.lua` — added claude-cli to valid_providers, model now required (no default)
- `plugin/todo-ai.vim` — commented out premature setup() call (conflicts with lazy.nvim)

### Lua Cleanup (post Phase 4)
- Deleted 12 Lua modules now handled by Rust:
  - `providers/claude.lua`, `providers/openai.lua`, `providers/ollama.lua`, `providers/claude_cli.lua`, `providers/init.lua`
  - `provider_base.lua`, `http_client.lua`, `retry_manager.lua`
  - `parser.lua`, `schema_validator.lua`, `prompt_builder.lua`, `prompt_config.lua`
- Removed `lua/todo-ai/providers/` directory entirely
- `lua/todo-ai/init.lua` — backend.start() is now required (error if binary not found), removed providers require/setup
- `lua/todo-ai/unified_prompt.lua` — removed `build_complete_prompt()`, removed Lua fallback path from `send_to_provider()` (error if backend not available), removed `parser`/`schema_validator` from `handle_response()` (Rust does parsing + validation)
- `lua/todo-ai/dry_tagger.lua` — routes through `unified_prompt.send_to_provider()` instead of direct provider calls

### Phase 5: Context + Scanner
- `rust/src/context.rs` — project context generation (port of context_compact.lua)
  - `generate_compact()` — tech stack, language file counts, dirs, configs, test frameworks, package managers, recent changes, dependency summary
  - `encode_for_llm()` — strip markdown, truncate to 2000 chars
  - 5 tests
- `rust/src/scanner.rs` — TODO @ai regex matching (port of scanner.lua)
  - `parse_line()` — 9 comment style patterns (Lua, C, Python, HTML, Vim, Lisp, LaTeX, Jinja, C block)
  - `extract_multiline_todo()` — continuation line support
  - `find_todos()` — scan lines for all matches
  - `scan_project()` — walk project files via git ls-files / find
  - `format_project_todos()` — format for LLM context
  - 12 tests (including real project scan test)
- `rpc.rs` — added `scan_project_context` and `scan_todos` RPC methods

**Current test count: 81 passing**

### Phase 6: Chat Persistence
- `rust/src/chat_store.rs` — save/load/list `.todoai/chats/*.md`
  - `save_chat()` — serialize messages to markdown, skip thinking messages
  - `load_chat()` — parse markdown back into messages with role/content/timestamp
  - `list_chats()` — enumerate sessions sorted newest first
  - `cleanup_old_sessions()` — remove excess sessions beyond max count
  - 7 tests
- `rpc.rs` — added `save_chat`, `load_chat`, `list_chats` RPC methods
- `lua/todo-ai/chat.lua` — replaced file I/O with backend RPC calls for save/load/list

**Current test count: 88 passing**

## All Phases Complete

## Architecture Notes

- search_replace.lua stays in Lua (user request)
- Binary found relative to plugin dir: `<plugin>/rust/target/release/todo-ai-backend`
- Socket path: `/tmp/todo-ai-<pid>.sock`
- Lua spawns via jobstart, connects via vim.loop.new_pipe()
- All callbacks dispatched via vim.schedule()
- Config split: backend config sent to Rust, UI config stays in Lua
