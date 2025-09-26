local M = {}

M.defaults = {
    -- Provider settings
    provider = 'claude',     -- 'claude', 'openai', 'ollama'
    model = 'claude-sonnet-4-20250514', -- Latest Claude 4 Sonnet (user can override)

    -- API settings (automatically uses environment variables)
    api_key = nil, -- For Claude/OpenAI (defaults to ANTHROPIC_API_KEY or OPENAI_API_KEY)
    endpoint = nil, -- For Ollama (defaults to http://localhost:11434)

    -- Model parameters
    temperature = 0.7,
    max_tokens = 4096,

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
}

M.config = {}

function M.setup(opts)
    M.config = vim.tbl_deep_extend('force', M.defaults, opts or {})

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
    -- Check if provider requires API key
    if (M.config.provider == 'claude' or M.config.provider == 'openai') and not M.config.api_key then
        vim.notify(
            string.format('Warning: %s provider requires an API key. Set it in config or environment.', M.config
            .provider),
            vim.log.levels.WARN
        )
    end

    -- Validate provider
    local valid_providers = { 'claude', 'openai', 'ollama' }
    if not vim.tbl_contains(valid_providers, M.config.provider) then
        vim.notify(
            string.format('Invalid provider: %s. Using claude.', M.config.provider),
            vim.log.levels.WARN
        )
        M.config.provider = 'claude'
    end
end

function M.get(key)
    return M.config[key]
end

function M.set(key, value)
    M.config[key] = value
end

-- Load project-specific config if exists
function M.load_project_config()
    local project_config_path = vim.fn.getcwd() .. '/.todoai/config.json'
    if vim.fn.filereadable(project_config_path) == 1 then
        local file = io.open(project_config_path, 'r')
        if file then
            local content = file:read('*all')
            file:close()
            local project_config = vim.fn.json_decode(content)
            if project_config then
                M.config = vim.tbl_deep_extend('force', M.config, project_config)
                vim.notify('Loaded project-specific Todo-AI config', vim.log.levels.INFO)
            end
        end
    end
end

return M
