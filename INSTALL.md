# Installation

## Prerequisites

### 1. tmux

Neovim must run inside a tmux session. todo-ai opens pi in a tmux pane alongside Neovim.

```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux
```

### 2. Pi coding agent

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

See [pi docs](https://github.com/mariozechner/pi-coding-agent) for all supported providers and configuration.

### 3. Neovim

Neovim **0.10+** required.

### 4. diffview.nvim

Required for reviewing changes pi makes:

```lua
{ "sindrets/diffview.nvim" }
```

## Plugin setup

### lazy.nvim

```lua
{
  "tpabla/todo-ai",
  dependencies = { "sindrets/diffview.nvim" },
  config = function()
    require("todo-ai").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "tpabla/todo-ai",
  requires = { "sindrets/diffview.nvim" },
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

Provider, model, and thinking level are configured through pi directly (see [pi docs](https://github.com/mariozechner/pi-coding-agent)). The settings below are todo-ai-specific:

```lua
require("todo-ai").setup({
  tag = "AGENT",                 -- Comment tag for scanning (AGENT:)
  pi_extra_args = {},            -- Additional CLI args passed to pi
                                 --   { "--no-session" }  ephemeral mode
  pi_width = 80,                -- Tmux pane width in columns
})
```

## Verify installation

1. Start tmux: `tmux`
2. Open Neovim: `nvim`
3. Run `:TodoAI`
4. Pi should open in a tmux pane to the right with a session selector
5. Start a new session or pick an existing one
6. Type a message — pi should respond
7. Check pi's footer for `🟢 nvim` — confirms Neovim integration is active

## Keybindings

| Default | Command | Description |
|---------|---------|-------------|
| `<leader>tc` | `:TodoAI` | Open pi in a tmux pane (reuses existing) |
| `<leader>tf` | `:TodoAIFocus` | Switch tmux focus to pi's pane |
| `<leader>ts` | `:TodoAIScan` | Find `AGENT:` comments, send to pi |
| `<leader>ti` | `:TodoAIVisual` | Send visual selection to pi |

Override:

```lua
vim.keymap.set("n", "<leader>ai", ":TodoAI<CR>")
vim.keymap.set("v", "<leader>ai", ":TodoAIVisual<CR>")
```

## Using in your projects

### AGENT scanning

Add `AGENT:` comments in any language:

```python
# AGENT: add retry logic with exponential backoff
def fetch(url):
    return requests.get(url).json()
```

```typescript
// AGENT: extract this into a reusable hook
function useAuth() { ... }
```

Press `<leader>ts` or run `:TodoAIScan`. Pi finds all `AGENT:` comments and resolves them. Also available as `/scan` in pi's pane.

### Project context

Pi reads your project files directly. For project-specific instructions, add an `AGENTS.md` to your project root — pi picks it up automatically.

### Visual mode

1. Select code in visual mode
2. Press `<leader>ti`
3. Type your instruction
4. Pi processes it and edits the file
5. `:DiffviewOpen` to review

## Troubleshooting

### `todo-ai requires tmux`

Neovim must run inside a tmux session:

```bash
tmux
nvim
```

### `pi` not found

Install pi: `npm install -g @mariozechner/pi-coding-agent`

### No `🟢 nvim` in pi's footer

The extension isn't loading or can't find Neovim. Check:

- Extension file exists: the plugin ships it at `extension/neovim.ts`
- Neovim has called `setup()` (writes socket to state dir)
- If pi was started outside `:TodoAI`, run it in the same CWD as Neovim — the extension auto-discovers the socket via matching CWD hash
- Test manually: `NVIM=/tmp/nvimXXXX/0 pi -e /path/to/todo-ai/extension/neovim.ts`

### Buffers not reloading after edits

The extension calls `:checktime` automatically. If not working:

- Run `:checktime` manually
- Ensure `autoread` is on (the plugin sets this in `setup()`)

### Diffview not opening

Install [diffview.nvim](https://github.com/sindrets/diffview.nvim). It's listed as a dependency — plugin managers should install it automatically.
