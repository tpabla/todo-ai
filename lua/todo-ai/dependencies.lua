local M = {}

-- Check and setup plugin dependencies
function M.check_dependencies()
  local deps = {
    {
      name = 'render-markdown.nvim',
      repo = 'MeanderingProgrammer/markdown.nvim',
      config = function()
        require('render-markdown').setup({
          -- Enable for todo-ai chat buffers
          file_types = { 'markdown', 'todo-ai-chat' },
          -- Customize rendering for chat
          code = {
            enabled = true,
            sign = false,
            width = 'full',
            position = 'left',
          },
          heading = {
            enabled = true,
            sign = false,
            icons = {},
          },
          bullet = {
            enabled = true,
            icons = { '•', '◦', '▪', '▫' },
          },
          quote = {
            enabled = true,
            icon = '┃',
          },
        })
      end,
      optional = false,
    }
  }

  local missing = {}

  for _, dep in ipairs(deps) do
    local ok = pcall(require, dep.name:match('([^.]+)'))
    if not ok and not dep.optional then
      table.insert(missing, dep)
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
      table.insert(lines, string.format("  { '%s' },", dep.repo))
    end
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
  -- Try to setup render-markdown if available
  local ok, render_md = pcall(require, 'render-markdown')
  if ok then
    -- Additional setup for todo-ai specific rendering
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'todo-ai-chat',
      callback = function(ev)
        -- Enable render-markdown for our chat buffers
        vim.bo[ev.buf].filetype = 'markdown'

        -- Keep some buffer-local settings
        vim.bo[ev.buf].buftype = 'nofile'
        vim.bo[ev.buf].swapfile = false
        vim.bo[ev.buf].modifiable = true

        -- Trigger render-markdown
        vim.cmd('RenderMarkdown enable')
      end
    })

    return true
  end
  return false
end

return M