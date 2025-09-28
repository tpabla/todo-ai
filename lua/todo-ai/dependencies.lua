local M = {}

-- Check and setup plugin dependencies
function M.check_dependencies()
  local deps = {
    {
      name = 'render-markdown.nvim',
      repo = 'MeanderingProgrammer/markdown.nvim',
      config = function()
        -- Don't call setup() to avoid overriding user config
        -- Instead, just ensure render-markdown is available
        -- User config and todo-ai highlight overrides are handled separately
      end,
      optional = false,
    },
    -- mini.diff removed - using native Neovim diff functionality instead
  }

  local missing = {}

  for _, dep in ipairs(deps) do
    -- For mini modules, require the specific module
    local module_name = dep.name
    if dep.name:match('^mini%.') then
      module_name = dep.name  -- Use full mini.diff name
    else
      module_name = dep.name:match('([^.]+)')  -- Extract first part for others
    end

    local ok = pcall(require, module_name)
    if not ok and not dep.optional then
      table.insert(missing, dep)
    elseif ok and dep.config then
      -- Run the setup config if the module exists
      dep.config()
    end
  end

  if #missing > 0 then
    M.suggest_installation(missing)
  end

  return #missing == 0
end

function M.suggest_installation(missing)
  local lines = {'Todo-AI: Missing required dependencies:', ''}

  for _, dep in ipairs(missing) do
    table.insert(lines, string.format('  • %s', dep.name))
  end

  table.insert(lines, '')
  table.insert(lines, 'Installation instructions:')
  table.insert(lines, '')

  -- Check package manager
  if vim.fn.exists(':Lazy') > 0 then
    -- Lazy.nvim
    table.insert(lines, 'Add to your lazy.nvim config:')
    table.insert(lines, '')
    for _, dep in ipairs(missing) do
      if dep.name == 'mini.diff' then
        -- Special handling for mini.nvim modules
        table.insert(lines, "  {")
        table.insert(lines, string.format("    '%s',", dep.repo))
        table.insert(lines, "    config = function()")
        table.insert(lines, "      require('mini.diff').setup()")
        table.insert(lines, "    end,")
        table.insert(lines, "  },")
      else
        table.insert(lines, string.format("  { '%s' },", dep.repo))
      end
    end
    table.insert(lines, '')
    table.insert(lines, 'Then run :Lazy install')
  elseif vim.fn.exists(':Packer') > 0 then
    -- Packer
    table.insert(lines, 'Add to your packer config:')
    table.insert(lines, '')
    for _, dep in ipairs(missing) do
      table.insert(lines, string.format("  use '%s'", dep.repo))
    end
  elseif vim.fn.exists(':PlugInstall') > 0 then
    -- vim-plug
    table.insert(lines, 'Add to your vim-plug config:')
    table.insert(lines, '')
    for _, dep in ipairs(missing) do
      table.insert(lines, string.format("  Plug '%s'", dep.repo))
    end
  else
    -- Manual installation
    table.insert(lines, 'Manual installation:')
    table.insert(lines, '')
    for _, dep in ipairs(missing) do
      table.insert(lines, string.format("  git clone https://github.com/%s ~/.config/nvim/pack/todo-ai/start/%s",
        dep.repo, dep.name))
    end
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.WARN)
end

function M.setup_render_markdown()
  -- Just check if render-markdown is available, don't configure it
  local ok = pcall(require, 'render-markdown')
  return ok
end

return M