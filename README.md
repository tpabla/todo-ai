# Todo-AI

A Neovim plugin that integrates AI-powered code completion directly into your editor through TODO comments. Works with multiple LLM providers including local models (Ollama), Claude (via API or Claude Code subscription), OpenAI, and custom endpoints.

## Features

- **Inline AI completions**: Write `# TODO: @ai <instruction>` and get AI-generated code
- **Multiple providers**: Support for Ollama, Claude, OpenAI, and custom endpoints
- **Claude Code integration**: Use your Claude Pro/Max subscription without API keys
- **Interactive refinement**: Chat pane for refining generated code
- **Visual diffs**: See proposed changes inline with accept/reject options
- **Project context**: Automatically gathers relevant context from your project
- **Smart caching**: Stores context in `.todoai/` for faster responses

## Installation

### Prerequisites

- Neovim 0.8+
- Python 3.8+
- One of the following:
  - Ollama (for local models)
  - Claude Code CLI (for Claude Pro/Max users)
  - API keys for Claude or OpenAI

### Install with Package Manager

#### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'todo-ai',
  build = './install.sh',
  config = function()
    require('todo-ai').setup({
      provider = 'ollama',  -- or 'claude', 'openai', 'custom'
      model = 'llama3.2'
    })
  end
}
```

#### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'todo-ai',
  run = './install.sh',
  config = function()
    require('todo-ai').setup({
      provider = 'ollama',
      model = 'llama3.2'
    })
  end
}
```

### Manual Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/todo-ai.git ~/.config/nvim/pack/plugins/start/todo-ai
```

2. Run the installation script:
```bash
cd ~/.config/nvim/pack/plugins/start/todo-ai
./install.sh
```

3. Add configuration to your `init.lua`:
```lua
require('todo-ai').setup({
  provider = 'ollama',
  model = 'llama3.2'
})
```

## Configuration

### Basic Configuration

```lua
require('todo-ai').setup({
  -- Provider settings
  provider = 'ollama',        -- 'claude', 'openai', 'ollama', 'custom'
  model = 'llama3.2',         -- Model varies by provider

  -- API settings
  api_key = nil,              -- For Claude/OpenAI (or use env vars)
  endpoint = 'http://localhost:11434',  -- For Ollama/custom

  -- Behavior
  auto_scan = false,          -- Auto-scan on save
  auto_open_chat = true,      -- Open chat pane automatically
  highlight_todos = true,     -- Highlight TODO: @ai comments
})
```

### Provider-Specific Setup

#### Ollama (Local Models)

```lua
require('todo-ai').setup({
  provider = 'ollama',
  model = 'llama3.2',  -- or 'codellama', 'mistral', etc.
  endpoint = 'http://localhost:11434'
})
```

Make sure Ollama is running:
```bash
ollama serve
ollama pull llama3.2  # Download the model first
```

#### Claude (API Key)

```lua
require('todo-ai').setup({
  provider = 'claude',
  model = 'claude-3-sonnet-20240229',
  api_key = vim.env.ANTHROPIC_API_KEY  -- Or set directly
})
```

#### Claude (Claude Code - Pro/Max Subscription)

If you have Claude Code CLI installed and a Pro/Max subscription:

```lua
require('todo-ai').setup({
  provider = 'claude',
  -- No API key needed! Uses your Claude Code subscription
})
```

Or set environment variable:
```bash
export USE_CLAUDE_CODE=true
```

#### OpenAI

```lua
require('todo-ai').setup({
  provider = 'openai',
  model = 'gpt-4',
  api_key = vim.env.OPENAI_API_KEY
})
```

#### Custom Endpoint

```lua
require('todo-ai').setup({
  provider = 'custom',
  endpoint = 'https://your-api.com',
  api_key = 'your-key',  -- Optional
  custom_headers = {      -- Optional
    ['X-Custom-Header'] = 'value'
  }
})
```

### Project-Specific Configuration

Create `.todoai/config.json` in your project root:

```json
{
  "provider": "claude",
  "model": "claude-3-opus-20240229",
  "temperature": 0.5,
  "max_tokens": 8192
}
```

## Usage

### Basic Workflow

1. Write a TODO comment with the `@ai` tag:
```python
# TODO: @ai implement binary search for this sorted list
def find_item(items, target):
    pass
```

2. Run `:TodoAIScan` or press `<leader>ts`

3. Review the generated code diff

4. Accept with `<leader>ta` or reject with `<leader>tr`

5. Optionally refine with chat using `<leader>tc`

### Commands

- `:TodoAIScan` - Scan buffer for TODO: @ai comments
- `:TodoAIAccept` - Accept proposed changes
- `:TodoAIReject` - Reject proposed changes
- `:TodoAIChat` - Open chat pane for refinement
- `:TodoAIConfig` - Open configuration file
- `:TodoAIInstall` - Install/update backend

### Default Keymaps

- `<leader>ts` - Scan for TODOs
- `<leader>ta` - Accept changes
- `<leader>tr` - Reject changes
- `<leader>tc` - Open chat

### Examples

#### Python
```python
# TODO: @ai create a decorator that logs function execution time
def slow_function():
    time.sleep(1)
```

#### JavaScript
```javascript
// TODO: @ai implement debounce function with 500ms delay
function handleInput(value) {
    console.log(value);
}
```

#### Go
```go
// TODO: @ai add error handling and retry logic with exponential backoff
func fetchData(url string) []byte {
    resp, _ := http.Get(url)
    body, _ := ioutil.ReadAll(resp.Body)
    return body
}
```

## Project Cache

Todo-AI creates a `.todoai/` directory in your project root to cache:
- Project structure and context
- Previous interactions history
- Project-specific configuration

Add `.todoai/` to your `.gitignore`:
```
.todoai/
```

## Troubleshooting

### Server not starting

1. Check Python installation:
```bash
python3 --version  # Should be 3.8+
```

2. Reinstall backend:
```vim
:TodoAIInstall
```

3. Check server logs:
```bash
tail -f ~/.local/share/nvim/todo-ai/server.log
```

### Claude Code not working

1. Verify Claude Code is installed:
```bash
claude --version
```

2. Check you're logged in:
```bash
claude auth status
```

3. Set the environment variable:
```bash
export USE_CLAUDE_CODE=true
```

### Ollama connection issues

1. Verify Ollama is running:
```bash
curl http://localhost:11434/api/tags
```

2. Check available models:
```bash
ollama list
```

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Built for Neovim users who want AI assistance without leaving their editor
- Inspired by GitHub Copilot and similar tools
- Supports multiple providers for maximum flexibility