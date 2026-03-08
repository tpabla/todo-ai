local M = {}

M.defaults = {
    -- Provider settings
    provider = 'claude',     -- 'claude', 'openai', 'ollama'
    model = nil, -- Required: e.g. 'claude-opus-4-6', 'sonnet', 'gpt-4o'

    -- API settings (automatically uses environment variables)
    api_key = nil, -- For Claude/OpenAI (defaults to ANTHROPIC_API_KEY or OPENAI_API_KEY)
    endpoint = nil, -- For Ollama (defaults to http://localhost:11434)

    -- Model parameters
    temperature = 0.7,
    max_tokens = 8192,

    -- Plugin behavior
    auto_scan = false,   -- Auto-scan on buffer write
    auto_open_chat = true, -- Open chat pane automatically
    diff_style = 'inline', -- 'inline' or 'split'

    -- Cache settings
    cache_enabled = true,
    cache_dir = '.todoai',

    -- UI settings
    chat_window_width = 60,
    chat_window_position = 'right', -- 'right', 'left', 'bottom'
    highlight_todos = true,

    -- @ai highlighting settings
    ai_highlight = {
        enabled = true,
        fg = '#ff79c6',      -- Neon pink (cyberpunk)
        bg = '#1a1a2e',      -- Dark background
        bold = true,
    },

    -- Retry settings for API calls
    retry = {
        max_attempts = 3,
        base_delay = 1000,      -- milliseconds
        exponential_base = 2,
        max_delay = 30000,
        jitter = true,
    },

    -- HTTP request timeouts (in milliseconds)
    timeouts = {
        llm_request = 300000,  -- 5 minutes for LLM API requests
        health_check = 5000,   -- 5 seconds for health checks
        default = 30000,       -- 30 seconds default timeout
    },

    -- Integration settings
    integrations = {
        todo_comments = {
            enabled = true,
            auto_setup = true,  -- Automatically configure todo-comments if available
            custom_keywords = {}, -- User can add custom DRY tag keywords here
        },
        render_markdown = {
            enabled = true,
        }
    },

    -- LSP context settings
    lsp_context = {
        enabled = true,           -- Include LSP data in AI context
        include_diagnostics = true, -- Include errors/warnings
        include_symbols = true,    -- Include document symbols/outline
        include_hover = true,      -- Include type info at cursor
        include_all_buffers = true, -- Include LSP diagnostics from all open buffers
        max_diagnostics = 10,      -- Max number of diagnostics to include per buffer
        max_buffer_diagnostics = 5, -- Max diagnostic details per other buffer
        timeout = 1000,           -- Timeout for LSP requests in ms
    },

    -- Conversation history settings
    conversation = {
        max_messages = 50,        -- Maximum number of messages to keep in history (25 exchanges)
        max_total_chars = 50000,  -- Maximum total characters in history (~12k tokens)
        max_message_length = 4000, -- Truncate individual messages longer than this
        auto_clear_on_error = false, -- Clear history on API errors to recover
    },

    -- Debug settings
    log_level = 'DEBUG',  -- 'DEBUG', 'INFO', 'WARN', 'ERROR'
}

M.config = {}

function M.setup(opts)
    M.config = vim.tbl_deep_extend('force', M.defaults, opts or {})

    -- Ensure timeouts exist even if not provided
    if not M.config.timeouts then
        M.config.timeouts = M.defaults.timeouts
    end

    -- Try to get API keys from environment if not provided
    if not M.config.api_key then
        if M.config.provider == 'claude' then
            M.config.api_key = os.getenv('ANTHROPIC_API_KEY')
        elseif M.config.provider == 'openai' then
            M.config.api_key = os.getenv('OPENAI_API_KEY')
        end
    end

    -- Validate configuration
    M.validate()
end

function M.validate()
    -- Model is required
    if not M.config.model then
        error('todo-ai: model is required in config (e.g. model = "claude-opus-4-6")')
    end

    -- Check if provider requires API key
    if (M.config.provider == 'claude' or M.config.provider == 'openai') and not M.config.api_key then
        vim.notify(
            string.format('Warning: %s provider requires an API key. Set it in config or environment.', M.config
            .provider),
            vim.log.levels.WARN
        )
    end

    -- Validate provider
    local valid_providers = { 'claude', 'claude-cli', 'openai', 'ollama' }
    if not vim.tbl_contains(valid_providers, M.config.provider) then
        error(string.format('todo-ai: invalid provider %q. Valid: %s', M.config.provider, table.concat(valid_providers, ', ')))
    end
end

function M.get(key)
    return M.config[key]
end

function M.set(key, value)
    M.config[key] = value
end

-- Load project-specific config if exists
return M
