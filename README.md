# 🤖 TodoAI - AI-Powered Code Assistant for Neovim

A Neovim plugin that brings AI code assistance through TODO comments, interactive chat, and visual selection — using aider-style SEARCH/REPLACE blocks for precise code changes.

## ✨ Features

- **📝 TODO Scanning**: Detects `TODO: @ai` comments and resolves them with AI
- **💬 Interactive Chat**: Vim-native chat buffer (`:w` to send messages)
- **👁️ Visual Mode**: Select code, get AI-powered refactoring/explanation
- **🎨 Visual Diffs**: Inline diff display using native Neovim `DiffAdd`/`DiffDelete` highlighting with per-change accept/reject
- **🔍 Context-Aware**: Includes LSP diagnostics, project context, and file content
- **📊 Multi-Provider**: Claude, OpenAI, Ollama, and Claude CLI
- **⚡ Rust Backend**: Async Rust process communicates via Unix socket for non-blocking LLM calls

## 🏗️ Architecture

```
User Input → unified_prompt.process() → Rust Backend (Unix socket)
                                              ↓
                                        LLM Provider (Claude/OpenAI/Ollama)
                                              ↓
                                        JSON Response {mode: "chat"|"changes"}
                                              ↓
                                        SEARCH/REPLACE blocks → Visual Diff
```

**Key design decisions:**
- **Single entry point**: All requests flow through `unified_prompt.process()`
- **Aider-style SEARCH/REPLACE**: Exact text matching for code changes — no line numbers or complex diffs
- **Fail fast**: No silent failures, no fallback behavior, no guessing
- **Native Neovim diff**: Uses `DiffAdd`/`DiffDelete` highlighting for visual diffs

### Core Components

| Component | Description |
|-----------|-------------|
| `unified_prompt.lua` | Single entry point for all AI requests |
| `backend.lua` | Manages Rust backend process via Unix socket |
| `search_replace.lua` | Applies SEARCH/REPLACE text transformations |
| `diff.lua` | Visual diff display with accept/reject per change |
| `chat.lua` | Interactive chat buffer with edit queue |
| `scanner.lua` | Finds `TODO: @ai` comments in buffers |
| `visual.lua` | Visual mode selection processing |
| `lsp_context.lua` | Collects LSP diagnostics for context |
| `context_compact.lua` | Project context generation |
| **Rust backend** | Async LLM communication, prompt building, response parsing |

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tpabla/todo-ai",
  build = "make build-rust",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("todo-ai").setup({
      provider = "claude",
      model = "claude-opus-4-6",
    })
  end,
}
```

### Manual

```bash
git clone https://github.com/tpabla/todo-ai.git \
  ~/.local/share/nvim/site/pack/plugins/start/todo-ai
cd ~/.local/share/nvim/site/pack/plugins/start/todo-ai
make build-rust
```

## 🔧 Configuration

### API Keys

```bash
# Claude
export ANTHROPIC_API_KEY="sk-ant-..."

# OpenAI
export OPENAI_API_KEY="sk-..."

# Ollama (no key needed)
ollama serve
```

### Setup

```lua
require('todo-ai').setup({
  provider = 'claude',           -- 'claude', 'openai', 'ollama'
  model = 'claude-opus-4-6',
  temperature = 0.7,
  max_tokens = 8192,

  -- UI
  diff_style = 'inline',
  chat_window_width = 60,
  chat_window_position = 'right',

  -- @ai tag highlighting
  ai_highlight = {
    enabled = true,
    fg = '#ff79c6',
    bg = '#1a1a2e',
    bold = true,
  },
})
```

## 🎮 Usage

### Keybindings

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>ts` | `:TodoAIScan` | Scan buffer for `TODO: @ai` comments |
| `<leader>tc` | `:TodoAIChat` | Open interactive chat |
| `<leader>ta` | `:TodoAIAccept` | Accept current change |
| `<leader>tr` | `:TodoAIReject` | Reject current change |
| `<leader>ti` | `:TodoAIVisual` | Process visual selection |
| `<leader>tg` | `:TodoAIGenerateContext` | Generate project context |
| `<leader>td` | `:TodoAISuggestDryTags` | Suggest DRY tags |
| `<leader>tS` | `:TodoAIScanProject` | Scan entire project |
| `<leader>ea` | `:TodoAIEditAccept` | Accept current edit in queue |
| `<leader>er` | `:TodoAIEditReject` | Reject current edit in queue |
| `<leader>en` | `:TodoAIEditNext` | Next edit in queue |

### TODO Scanning

```python
# TODO: @ai Add error handling for API calls
def fetch_data(url):
    return requests.get(url).json()
```

Press `<leader>ts` — the AI reads the TODO, generates a SEARCH/REPLACE block, and shows an inline diff you can accept or reject.

### Interactive Chat

1. `<leader>tc` opens the chat buffer
2. Type your message like normal vim editing
3. `:w` sends the message
4. AI responds with either chat text or code changes
5. Code changes appear as inline diffs in the target buffer

### Visual Mode

Select code → `<leader>ti` → type instruction in floating window → AI processes selection.

## 🛠️ Development

### Project Structure

```
todo-ai/
├── lua/todo-ai/
│   ├── init.lua              # Entry point & command registration
│   ├── unified_prompt.lua    # Single entry point for all AI requests
│   ├── backend.lua           # Rust backend process management
│   ├── search_replace.lua    # SEARCH/REPLACE text transformation
│   ├── diff.lua              # Visual diff with DiffAdd/DiffDelete
│   ├── chat.lua              # Chat buffer & edit queue
│   ├── scanner.lua           # TODO: @ai detection
│   ├── visual.lua            # Visual mode processing
│   ├── config.lua            # Configuration management
│   ├── lsp_context.lua       # LSP diagnostics collection
│   ├── context_compact.lua   # Project context generation
│   ├── dry_tagger.lua        # DRY tag suggestions
│   ├── integrations.lua      # Optional plugin integrations
│   ├── logger.lua            # Debug logging
│   └── dependencies.lua      # Dependency checking
├── rust/
│   └── src/
│       ├── main.rs           # Unix socket server
│       ├── rpc.rs            # JSON-RPC handler
│       ├── providers/        # Claude, OpenAI, Ollama, Claude CLI
│       ├── prompt.rs         # Prompt building
│       ├── parser.rs         # Response parsing
│       ├── schema.rs         # JSON schema validation
│       └── ...
├── plugin/todo-ai.vim        # Vim commands & keymaps
├── tests/                    # Plenary.nvim tests
└── Makefile
```

### Building

```bash
make build-rust    # Build Rust backend
make test          # Run Lua tests
make test-rust     # Run Rust tests
```

### Running Tests

```bash
# All tests
make test

# Single test file
make test-single FILE=tests/plenary/some_spec.lua

# In Neovim
:PlenaryBustedFile %
```

### Debug Logging

```lua
require('todo-ai').setup({ log_level = 'DEBUG' })
```

```vim
:TodoAILogs
" or
tail -f /tmp/todo-ai.log
```

## 📄 License

MIT

## 🙏 Credits

**Inspired by:** [aider](https://github.com/paul-gauthier/aider) (SEARCH/REPLACE approach), [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim)

**Built with:** [Neovim](https://neovim.io/), [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim), [Claude](https://anthropic.com), [OpenAI](https://openai.com), [Ollama](https://ollama.ai)
