# Installation

## Prerequisites

### 1. Pi coding agent

```bash
npm install -g @mariozechner/pi-coding-agent
```

Verify: `pi --version`

Set up a provider API key:

```bash
# Pick one
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...
export GOOGLE_API_KEY=...
```

See [pi docs](https://github.com/mariozechner/pi-coding-agent) for all supported providers.

### 2. Neovim

Neovim **0.10+** required.

## Plugin setup

### lazy.nvim

```lua
{
  "tpabla/todo-ai",
  dependencies = {
    "sindrets/diffview.nvim",
  },
  config = function()
    require("todo-ai").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "tpabla/todo-ai",
  requires = {
    "sindrets/diffview.nvim",
  },
  config = function()
    require("todo-ai").setup()
  end,
}
```

### Manual

```bash
git clone https://github.com/tpabla/todo-ai.git \
  ~/.local/share/nvim/site/pack/plugins/start/todo-ai
git clone https://github.com/sindrets/diffview.nvim.git \
  ~/.local/share/nvim/site/pack/plugins/start/diffview.nvim
```

Add to your `init.lua`:

```lua
require("todo-ai").setup()
```

## Configuration

Provider, model, and thinking are configured through pi itself (see [pi docs](https://github.com/mariozechner/pi-coding-agent)). The settings below are todo-ai-specific:

```lua
require("todo-ai").setup({
  pi_extra_args = {},            -- Additional CLI args for pi
                                 --   { "--continue" }    resume last session
                                 --   { "--no-session" }  ephemeral session

  -- UI
  pi_position = "right",        -- Terminal position: "right" or "left"
  pi_width = 80,                -- Terminal width in columns

  -- @ai tag highlighting
  ai_highlight = {
    enabled = true,
    fg = "#ff79c6",
    bg = "#1a1a2e",
    bold = true,
  },
})
```

## Verify installation

1. Open Neovim
2. Run `:TodoAI`
3. Pi should open in a right-side terminal split
4. Type a message — pi should respond
5. Check pi's footer for `🟢 nvim` — confirms Neovim integration is active

## Keybindings

| Default | Command | Description |
|---------|---------|-------------|
| `<leader>tc` | `:TodoAI` | Open/show pi terminal |
| `<leader>tf` | `:TodoAIFocus` | Focus pi terminal (enters terminal mode) |
| `<leader>ti` | `:TodoAIVisual` | Send visual selection to pi |

Override in your config:

```lua
vim.keymap.set("n", "<leader>ai", ":TodoAI<CR>")
vim.keymap.set("v", "<leader>ai", ":TodoAIVisual<CR>")
```

## Using in your projects

### TODO scanning

Add `TODO: @ai` comments in any language:

```python
# TODO: @ai add retry logic with exponential backoff
def fetch(url):
    return requests.get(url).json()
```

```typescript
// TODO: @ai extract this into a reusable hook
function useAuth() { ... }
```

In pi's terminal, type `/scan`. Pi greps for all `TODO: @ai` comments and resolves them.

### Project context

Pi reads your files directly. For project-specific instructions, add a `CLAUDE.md` (or similar) to your project root — pi picks it up automatically.

### Visual mode workflow

1. Select code in visual mode
2. Press `<leader>ti`
3. Type what you want (e.g., "add error handling", "convert to TypeScript")
4. Pi edits the file directly
5. `:DiffviewOpen` to review

## Troubleshooting

### `pi` not found

```
Error: pi not found in PATH
```

Install: `npm install -g @mariozechner/pi-coding-agent`

### No `🟢 nvim` in pi's footer

The extension isn't loading. Check:

- Extension file exists: `ls <plugin-path>/extension/neovim.ts`
- Test manually: `pi -e <plugin-path>/extension/neovim.ts`
- The `$NVIM` environment variable is set (automatic inside Neovim's `:terminal`)

### Buffers not reloading after edits

The extension calls `:checktime` automatically. If it's not working:

- Run `:checktime` manually
- Ensure `autoread` is on (the plugin sets this in `setup()`)

### Diffview not opening

diffview.nvim is a required dependency. If using lazy.nvim or packer, it should be installed automatically. For manual installs:

```bash
git clone https://github.com/sindrets/diffview.nvim.git \
  ~/.local/share/nvim/site/pack/plugins/start/diffview.nvim
```
