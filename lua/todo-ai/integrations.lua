---@class Integrations
local M = {}

local logger = require('todo-ai.logger')

---Setup integration with todo-comments.nvim if available
function M.setup_todo_comments()
  local config = require('todo-ai.config')
  local integration_config = config.get('integrations.todo_comments') or {}

  -- Check if integration is disabled
  if integration_config.enabled == false then
    logger.debug('integrations', 'todo-comments integration disabled by user config')
    return false
  end

  local has_todo_comments, todo_comments = pcall(require, 'todo-comments')

  if not has_todo_comments then
    logger.debug('integrations', 'todo-comments.nvim not found - DRY tags will not be highlighted')
    return false
  end

  -- Skip auto-setup if user disabled it
  if integration_config.auto_setup == false then
    logger.debug('integrations', 'todo-comments auto-setup disabled by user')
    return false
  end

  -- Define TodoAI DRY tag configurations with fun cyberpunk icons
  local todo_ai_keywords = {
    DRY = {
      icon = "⚡", -- Lightning for power/efficiency
      color = "hint",
      alt = { "REUSE", "RECYCLE" },
    },
    UTIL = {
      icon = "🚀", -- Rocket for utility functions
      color = "info",
      alt = { "UTILITY", "TOOL" },
    },
    HELPER = {
      icon = "🔮", -- Crystal ball for helpers
      color = "test",
      alt = { "ASSIST", "SUPPORT" },
    },
    PATTERN = {
      icon = "💎", -- Diamond for valuable patterns
      color = "warning",
      alt = { "TEMPLATE", "BLUEPRINT" },
    },
    COMMON = {
      icon = "🌐", -- Globe for common/shared
      color = "default",
      alt = { "SHARED", "GLOBAL" },
    },
    SHARED = {
      icon = "⚙️", -- Gear for shared components
      color = "error",
      alt = { "COMMON", "MODULE" },
    },
  }

  -- Get current todo-comments config
  local current_config = todo_comments.config or {}
  local current_keywords = current_config.keywords or {}

  -- Add user custom keywords first
  local custom_keywords = integration_config.custom_keywords or {}
  for keyword, config in pairs(custom_keywords) do
    current_keywords[keyword] = config
    logger.debug('integrations', 'Added custom DRY tag: ' .. keyword)
  end

  -- Merge TodoAI keywords with existing ones (user config takes precedence)
  for keyword, config in pairs(todo_ai_keywords) do
    if not current_keywords[keyword] then
      current_keywords[keyword] = config
      logger.debug('integrations', 'Added DRY tag highlighting for: ' .. keyword)
    else
      logger.debug('integrations', 'User override found for: ' .. keyword)
    end
  end

  -- Update the configuration
  local updated_config = vim.tbl_deep_extend('force', current_config, {
    keywords = current_keywords,
    highlight = {
      multiline = true,
      before = "",
      keyword = "wide",
      after = "fg",
      pattern = [[.*<(KEYWORDS)\s*:]],
      comments_only = true,
    }
  })

  -- Apply the updated configuration
  todo_comments.setup(updated_config)

  logger.info('integrations', 'Enhanced todo-comments with TodoAI DRY tags')
  return true
end

---Setup integration with render-markdown.nvim if available
function M.setup_render_markdown()
  local has_render_markdown, render_markdown = pcall(require, 'render-markdown')

  if not has_render_markdown then
    logger.debug('integrations', 'render-markdown.nvim not found - markdown rendering disabled')
    return false
  end

  -- TodoAI already uses render-markdown, just ensure it's configured
  logger.debug('integrations', 'render-markdown.nvim integration ready')
  return true
end

---Setup all available integrations
function M.setup_all()
  logger.info('integrations', 'Setting up optional integrations...')

  local results = {
    todo_comments = M.setup_todo_comments(),
    render_markdown = M.setup_render_markdown(),
  }

  local enabled_count = 0
  for integration, enabled in pairs(results) do
    if enabled then
      enabled_count = enabled_count + 1
    end
  end

  logger.info('integrations', string.format('Setup complete: %d/%d integrations enabled',
    enabled_count, vim.tbl_count(results)))

  return results
end

---Check if todo-comments integration is available
---@return boolean
return M