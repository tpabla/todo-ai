# 🤖 TodoAI - AI-Powered Code Assistant for Neovim

A sophisticated Neovim plugin that brings AI assistance directly to your editor through TODO comments, interactive chat, and intelligent code understanding.

## ✨ Features

- **📝 Smart TODO Resolution**: Auto-detects and resolves TODO comments with AI
- **💬 Interactive Chat**: Vim-native chat interface (`:w` to send messages)
- **🔍 Context-Aware**: Automatic project context generation and inclusion
- **🔒 Security-First**: Safe command execution with injection prevention
- **⚡ Non-Blocking**: Async operations with provider-specific rate limiting
- **🎨 Visual Diffs**: Beautiful inline diff display with accept/reject
- **📊 Multi-Provider**: Claude, OpenAI, Ollama, and custom endpoints

## 🏗️ How It Works

### Architecture Overview

```
User Input → Parser → Context Builder → LLM Provider → Response Validator → Diff Display
     ↑                      ↓                                   ↓
     └──────── Chat Manager ←────── Async Manager ──────────────┘
```

### Core Components

1. **Schema-Based Communication**: All LLM interactions use a unified schema:
   ```lua
   {
     messages = { {role = "user", content = "..."} },
     context = { project_info = "...", files = {...} },
     config = { model = "...", temperature = 0.7 }
   }
   ```

2. **Response Validation**: Every LLM response passes through validation:
   - Sanitizes potential injection attempts
   - Validates code changes (line numbers, syntax)
   - Auto-fixes common issues (swapped line numbers, trailing commas)
   - Retries with error feedback if validation fails

3. **Context Management**: Smart context generation with compression:
   - Gathers project structure, dependencies, patterns
   - Compresses for optimal token usage
   - Caches for 5 minutes to reduce redundant processing
   - Includes DRY hints for code reuse

4. **Security Layer**: Multiple protection levels:
   - Command whitelisting (only safe commands allowed)
   - Path sanitization (no directory traversal)
   - Input validation (prevents injection)
   - Rate limiting (per-provider token buckets)

## 📦 Installation

> **Note**: No publishing required! Neovim package managers can install directly from GitHub.

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended)

```lua
{
  "tpabla/todo-ai",
  config = function()
    require("todo-ai").setup({
      provider = "claude",
      model = "claude-3-5-sonnet-20241022",
    })
  end,
  keys = {
    { "<leader>ts", desc = "Scan TODOs" },
    { "<leader>tc", desc = "Open AI Chat" },
    { "<leader>tg", desc = "Generate Context" },
    { "<leader>ta", desc = "Accept Changes" },
    { "<leader>tr", desc = "Reject Changes" },
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'tpabla/todo-ai',
  config = function()
    require('todo-ai').setup({ provider = 'claude' })
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'tpabla/todo-ai'

" Then run:
" :PlugInstall
```

### Manual Installation (if needed)

```bash
# Clone to your Neovim packages directory
git clone https://github.com/tpabla/todo-ai.git \
  ~/.local/share/nvim/site/pack/plugins/start/todo-ai
```

## 🔧 Configuration

### Required: Set API Keys

```bash
# ~/.bashrc or ~/.zshrc

# For Claude (Anthropic)
export ANTHROPIC_API_KEY="sk-ant-..."

# For OpenAI
export OPENAI_API_KEY="sk-..."

# For Ollama (no key needed, just ensure it's running)
ollama serve
```

### Plugin Configuration

```lua
require('todo-ai').setup({
  -- Provider settings
  provider = 'claude',  -- 'claude', 'openai', 'ollama'
  model = 'claude-3-5-sonnet-20241022',
  temperature = 0.7,
  max_tokens = 4096,

  -- UI settings
  diff_style = 'inline',  -- or 'split'
  floating_window = true,
  chat_window_width = 80,

  -- Features
  auto_scan_on_save = true,
  auto_generate_context = false,
  show_thinking = true,

  -- Performance
  cache_ttl = 300,  -- seconds
  max_context_size = 10000,

  -- Rate limiting
  rate_limits = {
    claude = { max_requests = 5, window_seconds = 60 },
    openai = { max_requests = 20, window_seconds = 60 },
  },
})
```

## 🎮 Usage

### Working with TODOs

```python
# TODO: Add error handling for API calls
def fetch_data(url):
    return requests.get(url).json()

# @ai: Optimize this function for performance
def process_items(items):
    # Press <leader>ts to scan and resolve
    pass
```

### Interactive Chat

1. **Open**: `<leader>tc` opens chat window
2. **Edit**: Type in the buffer like normal vim editing
3. **Send**: Save buffer (`:w`) sends message
4. **Commands**:
   - `<C-c>` - Clear input
   - `<C-d>` - Clear conversation
   - `q` - Close chat

### Visual Mode Processing

Select code and press `<leader>ti` to:
- Explain code
- Refactor selection
- Add documentation
- Fix issues

## 🛠️ Development Setup

### Local Development Installation

For active development, install the plugin directly from your local directory:

#### Using lazy.nvim

```lua
{
  dir = "~/Projects/todo-ai",  -- Your local development path
  config = function()
    require("todo-ai").setup({
      provider = "claude",
      log_level = "DEBUG",  -- Enable debug logging for development
    })
  end,
}
```

#### Using packer.nvim

```lua
use {
  '~/Projects/todo-ai',  -- Your local development path
  config = function()
    require('todo-ai').setup({
      provider = 'claude',
      log_level = 'DEBUG',
    })
  end
}
```

#### Manual symlink

```bash
# Create a symlink for development
ln -s ~/Projects/todo-ai ~/.local/share/nvim/site/pack/plugins/start/todo-ai
```

## 🏗️ Development

### Project Structure

```
todo-ai/
├── lua/todo-ai/
│   ├── init.lua                 # Entry point & command registration
│   ├── providers/               # LLM provider implementations
│   │   ├── claude.lua          # Anthropic Claude
│   │   ├── openai.lua          # OpenAI GPT
│   │   └── ollama.lua          # Local Ollama
│   ├── chat_manager.lua        # Conversation state & memory
│   ├── context_compact.lua     # Project context generation
│   ├── llm_validator.lua       # Response validation & retry
│   ├── secure_exec.lua         # Safe command execution
│   ├── async_manager.lua       # Async ops & rate limiting
│   ├── config_manager.lua      # Config persistence
│   ├── diff.lua               # Diff display & highlighting
│   └── utils.lua              # Shared utilities
├── tests/
│   ├── plenary/               # Neovim integration tests
│   ├── unit/                  # Standalone unit tests
│   └── run_plenary_tests.sh   # Test runner
└── plugin/todo-ai.vim         # Vim commands & keymaps
```

### Key Implementation Details

#### 1. **Async Flow with Validation**
```lua
-- Simplified flow
User Input
  → validate_input()
  → build_context()
  → rate_limited_request()
    → provider.chat_async()
    → validate_response()
    → retry_if_invalid()
  → display_diff()
```

#### 2. **Memory Management**
- Chat messages limited to 100 or 100k tokens
- Automatic cleanup of old messages
- Context cached with TTL
- Log rotation at 10MB

#### 3. **Provider Abstraction**
Each provider implements:
```lua
M.chat(messages, config)        -- Sync chat
M.chat_async(messages, config, callback)  -- Async chat
M.validate_config()              -- Config validation
```

#### 4. **Diff Generation**
- Parses LLM response for code blocks
- Calculates minimal diff
- Shows inline with syntax highlighting
- Handles accept/reject with undo integration

### Running Tests

#### Prerequisites

```bash
# Install Plenary.nvim (required for tests)
# Using lazy.nvim - add to your Neovim config:
{ 'nvim-lua/plenary.nvim' }

# Or manually:
git clone https://github.com/nvim-lua/plenary.nvim \
  ~/.local/share/nvim/site/pack/test/start/plenary.nvim
```

#### Test Commands

```bash
# Run all tests
make test

# Run specific test file
make test-file FILE=tests/plenary/llm_validator_spec.lua

# Alternative: Run tests directly
bash tests/run_plenary_tests.sh

# Watch mode (requires fswatch on macOS or entr on Linux)
make test-watch
```

#### Running Tests in Neovim

```vim
" Run current test file (if in a *_spec.lua file)
:PlenaryBustedFile %

" Run all tests in directory
:PlenaryBustedDirectory tests/plenary/
```

#### Debugging Failed Tests

```bash
# Run with verbose output
nvim --headless -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/plenary', {minimal_init = 'tests/minimal_init.lua', sequential = true})"

# Check test logs
tail -f /tmp/todo-ai.log
```

### Adding a New Provider

```lua
-- lua/todo-ai/providers/newprovider.lua
local M = {}

function M.setup(config)
  -- Validate API keys, endpoints
end

function M.chat_async(messages, config, callback)
  -- Implement async chat
  -- Must call: callback(response, error)
end

-- Register in providers/init.lua
providers.register('newprovider', require('todo-ai.providers.newprovider'))
```

## 🔒 Security Features

- **Command Whitelisting**: Only safe commands (ls, git, curl) allowed
- **Input Sanitization**: Removes injection attempts from all inputs
- **Path Validation**: Prevents directory traversal attacks
- **Rate Limiting**: Token bucket algorithm per provider
- **No Secret Logging**: API keys never logged or displayed

## 🧪 Testing

The plugin uses Plenary.nvim for testing, which runs tests in a real Neovim environment:

- **Test Coverage**: ~85% with 50+ tests
- **Test Location**: `tests/plenary/`
- **Framework**: Plenary.nvim (required)
- **Runtime**: ~500ms for full suite

## 🐛 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "API key not found" | Set environment variable: `export ANTHROPIC_API_KEY="..."` |
| "Rate limit exceeded" | Wait 60 seconds (automatic retry with backoff) |
| "Context generation failed" | Run `:TodoAIGenerateContext` manually |
| "Diff not showing" | Check `:messages` for errors, ensure buffer is modifiable |

### Debug Mode

```lua
require('todo-ai').setup({
  log_level = 'DEBUG',
  log_file = '/tmp/todo-ai.log'
})

-- View logs
:TodoAIViewLog
-- Or in terminal
tail -f /tmp/todo-ai.log
```

## 📊 Performance

- **Memory**: ~5-10MB resident
- **Context Generation**: <100ms (cached)
- **API Response**: 1-5s depending on provider
- **Diff Display**: <50ms
- **Test Suite**: 43 tests in ~400ms

## 🎯 Roadmap

- [ ] Streaming responses
- [ ] Multi-file refactoring
- [ ] Test generation from code
- [ ] Git integration (commit messages)
- [ ] Language server integration
- [ ] Custom prompt templates

## 📄 License

MIT - See [LICENSE](LICENSE) file

## 🙏 Credits

Built with:
- [Neovim](https://neovim.io/) - The extensible Vim-based text editor
- [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - Lua testing framework
- [Claude](https://anthropic.com), [OpenAI](https://openai.com), [Ollama](https://ollama.ai) - AI providers

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/taran/todo-ai/issues)
- **Discussions**: [GitHub Discussions](https://github.com/taran/todo-ai/discussions)

---

Made with ❤️ for the Neovim community