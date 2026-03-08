# 🤖 TodoAI - AI-Powered Code Assistant for Neovim

A Neovim plugin that wraps the [pi coding agent](https://github.com/mariozechner/pi-coding-agent) with a vim-native chat UI, TODO scanning, and Neovim context injection. Pi handles all file editing — you review changes with [diffview.nvim](https://github.com/sindrets/diffview.nvim).

## How it works

```
Neovim (todo-ai)                    pi (RPC subprocess)
┌──────────────┐                   ┌──────────────────┐
│ Chat buffer  │──── prompt ──────→│                  │
│              │←── streaming ─────│  LLM + Tools     │
│ TODO scanner │                   │  (read, write,   │
│ Open buffers │                   │   edit, bash)    │
│ LSP diags    │                   │                  │
└──────────────┘                   └──────────────────┘
                                          │
                                    edits files on disk
                                          │
                                    :DiffviewOpen to review
```

**Todo-ai gathers context from Neovim** (open buffers, LSP diagnostics, project structure, TODO comments) and sends it to pi. **Pi does the actual work** — reading files, making edits, running commands. You review changes with diffview and commit when satisfied.

## ✨ Features

- **💬 Chat UI**: Vim-native buffer — type, `:w` to send, streaming responses
- **📝 TODO Scanning**: Detects `TODO: @ai` comments and sends them to pi for resolution
- **🔍 Context Injection**: Open buffer paths, LSP diagnostics, and project context included automatically
- **👁️ Visual Mode**: Select code, describe what you want, pi handles it
- **⚡ Streaming**: Live response display as pi generates output
- **🔧 Tool Feedback**: See what pi is doing — editing files, running commands, reading code

## 📦 Installation

Requires [pi coding agent](https://github.com/mariozechner/pi-coding-agent) (`npm install -g @mariozechner/pi-coding-agent`).

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tpabla/todo-ai",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",  -- optional, for reviewing changes
  },
  config = function()
    require("todo-ai").setup({
      pi_provider = "anthropic",
      pi_model = "sonnet",
    })
  end,
}
```

## 🔧 Configuration

```lua
require('todo-ai').setup({
  -- Pi settings (all optional — uses pi defaults if omitted)
  pi_provider = 'anthropic',     -- any pi provider: anthropic, openai, google, ollama, etc.
  pi_model = 'sonnet',           -- model name or pattern
  pi_thinking = 'medium',        -- off, minimal, low, medium, high
  pi_system_prompt = nil,        -- appended to pi's system prompt
  pi_extra_args = {},             -- additional CLI args for pi

  -- Plugin behavior
  auto_scan = false,              -- auto-scan for TODOs on save

  -- UI
  chat_window_width = 60,
  chat_window_position = 'right', -- right, left, bottom

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
| `<leader>tc` | `:TodoAIChat` | Open chat |
| `<leader>ts` | `:TodoAIScan` | Scan buffer for `TODO: @ai` |
| `<leader>tS` | `:TodoAIScanProject` | Scan project for TODOs |
| `<leader>ti` | `:TodoAIVisual` | Process visual selection |
| `<leader>tx` | `:TodoAIAbort` | Abort current pi operation |
| `<leader>tg` | `:TodoAIGenerateContext` | Generate project context |

### Chat

1. `<leader>tc` opens the chat buffer
2. Type your message
3. `:w` or `Enter` sends it
4. Pi streams its response and edits files directly
5. `:DiffviewOpen` to review changes, `git checkout -- .` to revert

### TODO Scanning

```python
# TODO: @ai Add error handling for API calls
def fetch_data(url):
    return requests.get(url).json()
```

`<leader>ts` finds the TODO, sends it to pi with file context. Pi edits the file directly.

### Visual Mode

Select code → `<leader>ti` → type instruction → pi processes it.

## 🛠️ Development

### Project Structure

```
todo-ai/
├── lua/todo-ai/
│   ├── init.lua              # Setup, commands, TODO processing
│   ├── pi_client.lua         # Pi RPC client (spawn, send, receive)
│   ├── chat.lua              # Chat buffer UI with streaming
│   ├── context.lua           # Neovim context gathering
│   ├── scanner.lua           # TODO: @ai detection
│   ├── visual.lua            # Visual mode processing
│   ├── config.lua            # Configuration
│   ├── context_compact.lua   # Project context generation
│   ├── integrations.lua      # Optional plugin integrations
│   ├── dry_tagger.lua        # DRY tag suggestions
│   └── logger.lua            # Debug logging
├── plugin/todo-ai.vim        # Vim commands & keymaps
├── tests/                    # Plenary.nvim tests
├── scripts/find_dead_code.sh # Dead code detection
└── Makefile
```

### Make Targets

```bash
make test            # Run all tests
make test-single FILE=tests/plenary/some_spec.lua
make lint            # Find dead Lua code
make install         # Install to Neovim packages dir
make dev             # Symlink for development
make help            # Show all targets
```

### Debug Logging

```vim
:TodoAILogs
" or
tail -f /tmp/todo-ai.log
```

## Dependencies

- **Required**: [pi coding agent](https://github.com/mariozechner/pi-coding-agent)
- **Required**: [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for tests)
- **Optional**: [diffview.nvim](https://github.com/sindrets/diffview.nvim) (for reviewing changes)
- **Optional**: [render-markdown.nvim](https://github.com/MeanderingProgrammer/markdown.nvim) (chat formatting)

## 📄 License

MIT

## 🙏 Credits

**Built on**: [pi coding agent](https://github.com/mariozechner/pi-coding-agent), [Neovim](https://neovim.io/), [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
