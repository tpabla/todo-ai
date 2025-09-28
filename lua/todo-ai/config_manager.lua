---@class ConfigManager
---@field config table
---@field defaults table
---@field config_path string
---@field project_config_path string
local M = {}

-- Config file paths
M.global_config_path = vim.fn.stdpath('config') .. '/todo-ai.json'
M.project_config_name = '.todoai.json'

-- Default configuration with types
---@type table<string, any>
M.defaults = {
  -- Provider settings
  provider = 'claude',
  model = 'claude-3-5-sonnet-20241022',
  temperature = 0.7,
  max_tokens = 4096,

  -- API endpoints
  endpoints = {
    claude = 'https://api.anthropic.com/v1/messages',
    openai = 'https://api.openai.com/v1/chat/completions',
    ollama = 'http://localhost:11434',
  },

  -- UI settings
  diff_style = 'inline',  -- 'inline' or 'split'
  auto_open_chat = true,
  highlight_todos = true,
  chat_window_width = 80,
  chat_window_height = 30,
  floating_window = true,

  -- Performance settings
  cache_ttl = 300,  -- 5 minutes
  max_context_size = 10000,
  max_message_length = 5000,
  max_messages = 100,
  context_lines = 20,

  -- Rate limiting
  rate_limits = {
    claude = { max_requests = 5, window_seconds = 60 },
    openai = { max_requests = 20, window_seconds = 60 },
    ollama = { max_requests = 100, window_seconds = 60 },
  },

  -- Security
  allowed_commands = {
    'curl', 'git', 'find', 'grep', 'rg', 'tree', 'ls',
    'cat', 'head', 'tail', 'wc', 'make',
  },

  -- Logging
  log_level = 'INFO',  -- DEBUG, INFO, WARN, ERROR
  log_file = '/tmp/todo-ai.log',

  -- Features
  auto_scan_on_save = true,
  auto_generate_context = false,
  show_thinking = true,

  -- Keybindings (can be overridden)
  keymaps = {
    scan = '<leader>ts',
    accept = '<leader>ta',
    reject = '<leader>tr',
    chat = '<leader>tc',
    context = '<leader>tg',
    visual = '<leader>ti',
  },
}

-- Current configuration
M.config = {}

---Load configuration from file
---@param path string
---@return table|nil config, string|nil error
local function load_config_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, nil  -- File doesn't exist, not an error
  end

  local file = io.open(path, 'r')
  if not file then
    return nil, "Failed to open config file: " .. path
  end

  local content = file:read('*all')
  file:close()

  if content == '' then
    return {}, nil
  end

  local ok, config = pcall(vim.fn.json_decode, content)
  if not ok then
    return nil, "Invalid JSON in config file: " .. path
  end

  return config, nil
end

---Save configuration to file
---@param config table
---@param path string
---@return boolean success, string|nil error
local function save_config_file(config, path)
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(dir, 'p')

  local json_str = vim.fn.json_encode(config)
  if not json_str then
    return false, "Failed to encode configuration"
  end

  local file = io.open(path, 'w')
  if not file then
    return false, "Failed to open config file for writing: " .. path
  end

  file:write(json_str)
  file:close()

  return true, nil
end

---Initialize configuration
function M.init()
  -- Start with defaults
  M.config = vim.deepcopy(M.defaults)

  -- Load global config
  local global_config, err = load_config_file(M.global_config_path)
  if err then
    vim.notify("Error loading global config: " .. err, vim.log.levels.WARN)
  elseif global_config then
    M.config = M.merge_configs(M.config, global_config)
  end

  -- Load project config
  local project_config_path = vim.fn.getcwd() .. '/' .. M.project_config_name
  local project_config, err2 = load_config_file(project_config_path)
  if err2 then
    vim.notify("Error loading project config: " .. err2, vim.log.levels.WARN)
  elseif project_config then
    M.config = M.merge_configs(M.config, project_config)
  end

  -- Apply environment variables (highest priority)
  M.apply_env_overrides()

  return M.config
end

---Merge two config tables
---@param base table
---@param override table
---@return table merged
function M.merge_configs(base, override)
  local result = vim.deepcopy(base)

  for key, value in pairs(override) do
    if type(value) == 'table' and type(result[key]) == 'table' then
      result[key] = M.merge_configs(result[key], value)
    else
      result[key] = value
    end
  end

  return result
end

---Apply environment variable overrides
function M.apply_env_overrides()
  -- Provider from env
  if vim.env.TODOAI_PROVIDER then
    M.config.provider = vim.env.TODOAI_PROVIDER
  end

  -- Model from env
  if vim.env.TODOAI_MODEL then
    M.config.model = vim.env.TODOAI_MODEL
  end

  -- Log level from env
  if vim.env.TODOAI_LOG_LEVEL then
    M.config.log_level = vim.env.TODOAI_LOG_LEVEL
  end
end

---Get a configuration value
---@param key string Dot-separated path (e.g., "rate_limits.claude.max_requests")
---@return any value
function M.get(key)
  if not key then
    return M.config
  end

  local parts = vim.split(key, '.', { plain = true })
  local current = M.config

  for _, part in ipairs(parts) do
    if type(current) ~= 'table' then
      return nil
    end
    current = current[part]
  end

  return current
end

---Set a configuration value
---@param key string Dot-separated path
---@param value any
---@param persist boolean|nil Whether to save to file
function M.set(key, value, persist)
  if not key then
    return false
  end

  local parts = vim.split(key, '.', { plain = true })
  local current = M.config
  local parent = nil
  local last_key = nil

  -- Navigate to parent
  for i, part in ipairs(parts) do
    if i == #parts then
      last_key = part
      parent = current
    else
      if type(current[part]) ~= 'table' then
        current[part] = {}
      end
      current = current[part]
    end
  end

  -- Set value
  if parent and last_key then
    parent[last_key] = value

    -- Persist if requested
    if persist then
      M.save()
    end

    return true
  end

  return false
end

---Save current configuration
---@param scope string|nil 'global' or 'project' (default: 'project')
---@return boolean success, string|nil error
function M.save(scope)
  scope = scope or 'project'

  local path
  if scope == 'global' then
    path = M.global_config_path
  else
    path = vim.fn.getcwd() .. '/' .. M.project_config_name
  end

  -- Filter out defaults to save space
  local config_to_save = {}
  for key, value in pairs(M.config) do
    if not vim.deep_equal(value, M.defaults[key]) then
      config_to_save[key] = value
    end
  end

  return save_config_file(config_to_save, path)
end

---Reset configuration to defaults
---@param scope string|nil 'all', 'global', or 'project'
function M.reset(scope)
  scope = scope or 'all'

  if scope == 'all' or scope == 'global' then
    -- Remove global config file
    if vim.fn.filereadable(M.global_config_path) == 1 then
      os.remove(M.global_config_path)
    end
  end

  if scope == 'all' or scope == 'project' then
    -- Remove project config file
    local project_path = vim.fn.getcwd() .. '/' .. M.project_config_name
    if vim.fn.filereadable(project_path) == 1 then
      os.remove(project_path)
    end
  end

  -- Reinitialize
  M.init()
end

---Open configuration in editor
---@param scope string|nil 'global' or 'project'
function M.open_in_editor(scope)
  scope = scope or 'project'

  local path
  if scope == 'global' then
    path = M.global_config_path
  else
    path = vim.fn.getcwd() .. '/' .. M.project_config_name
  end

  -- Ensure file exists with current config
  if vim.fn.filereadable(path) ~= 1 then
    M.save(scope)
  end

  -- Open in split
  vim.cmd('split ' .. path)
  vim.bo.filetype = 'json'

  -- Set up autocmd to reload on save
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = vim.api.nvim_get_current_buf(),
    once = true,
    callback = function()
      M.init()
      vim.notify("Configuration reloaded", vim.log.levels.INFO)
    end,
  })
end

---Validate configuration
---@return boolean valid, string[]|nil errors
function M.validate()
  local errors = {}

  -- Validate provider
  local valid_providers = {'claude', 'openai', 'ollama'}
  if not vim.tbl_contains(valid_providers, M.config.provider) then
    table.insert(errors, "Invalid provider: " .. tostring(M.config.provider))
  end

  -- Validate temperature
  if type(M.config.temperature) ~= 'number' or
     M.config.temperature < 0 or M.config.temperature > 2 then
    table.insert(errors, "Temperature must be between 0 and 2")
  end

  -- Validate max_tokens
  if type(M.config.max_tokens) ~= 'number' or
     M.config.max_tokens < 1 or M.config.max_tokens > 100000 then
    table.insert(errors, "Invalid max_tokens value")
  end

  -- Validate log level
  local valid_levels = {'DEBUG', 'INFO', 'WARN', 'ERROR'}
  if not vim.tbl_contains(valid_levels, M.config.log_level) then
    table.insert(errors, "Invalid log_level: " .. tostring(M.config.log_level))
  end

  -- Check for API keys
  if M.config.provider == 'claude' and not vim.env.ANTHROPIC_API_KEY then
    table.insert(errors, "ANTHROPIC_API_KEY not set for Claude provider")
  elseif M.config.provider == 'openai' and not vim.env.OPENAI_API_KEY then
    table.insert(errors, "OPENAI_API_KEY not set for OpenAI provider")
  end

  return #errors == 0, #errors > 0 and errors or nil
end

---Get configuration info
---@return table info
function M.get_info()
  return {
    global_config = M.global_config_path,
    project_config = vim.fn.getcwd() .. '/' .. M.project_config_name,
    provider = M.config.provider,
    model = M.config.model,
    has_global_config = vim.fn.filereadable(M.global_config_path) == 1,
    has_project_config = vim.fn.filereadable(vim.fn.getcwd() .. '/' .. M.project_config_name) == 1,
    is_valid = M.validate(),
  }
end

-- Initialize on module load
M.init()

return M