local M = {}

M.defaults = {
    -- Pi coding agent settings
    pi_provider = nil,       -- e.g. 'anthropic', 'openai', 'google' (nil = pi default)
    pi_model = nil,          -- e.g. 'sonnet', 'gpt-4o' (nil = pi default)
    pi_thinking = nil,       -- e.g. 'medium', 'high' (nil = pi default)
    pi_system_prompt = nil,  -- appended to pi's system prompt
    pi_extra_args = {},      -- additional CLI args for pi

    -- Plugin behavior
    auto_scan = false,       -- Auto-scan on buffer write

    -- UI settings
    chat_window_width = 60,
    chat_window_position = 'right', -- 'right', 'left', 'bottom'

    -- @ai highlighting
    ai_highlight = {
        enabled = true,
        fg = '#ff79c6',
        bg = '#1a1a2e',
        bold = true,
    },

    -- Integration settings
    integrations = {
        todo_comments = {
            enabled = true,
            auto_setup = true,
            custom_keywords = {},
        },
        render_markdown = {
            enabled = true,
        }
    },

    -- Debug settings
    log_level = 'INFO',
}

M.config = {}

function M.setup(opts)
    M.config = vim.tbl_deep_extend('force', M.defaults, opts or {})
end

function M.get(key)
    return M.config[key]
end

function M.set(key, value)
    M.config[key] = value
end

return M
