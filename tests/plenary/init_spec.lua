describe("init", function()
  local init

  before_each(function()
    package.loaded['todo-ai.init'] = nil
    package.loaded['todo-ai.config'] = nil
    init = require('todo-ai.init')
  end)

  it("builds command with no config", function()
    require('todo-ai.config').setup({})
    local cmd = init._build_cmd(nil)
    assert.equals('pi', cmd[1])
    assert.is_true(vim.tbl_contains(cmd, '-e'))
    -- Extension path should be last before any prompt
    local ext_idx = nil
    for i, v in ipairs(cmd) do
      if v == '-e' then ext_idx = i end
    end
    assert.is_not_nil(ext_idx)
    assert.is_true(cmd[ext_idx + 1]:match('neovim%.ts$') ~= nil)
  end)

  it("builds command with provider and model", function()
    require('todo-ai.config').setup({ pi_provider = 'anthropic', pi_model = 'sonnet' })
    local cmd = init._build_cmd(nil)
    assert.is_true(vim.tbl_contains(cmd, '--provider'))
    assert.is_true(vim.tbl_contains(cmd, 'anthropic'))
    assert.is_true(vim.tbl_contains(cmd, '--model'))
    assert.is_true(vim.tbl_contains(cmd, 'sonnet'))
  end)

  it("builds command with thinking level", function()
    require('todo-ai.config').setup({ pi_thinking = 'high' })
    local cmd = init._build_cmd(nil)
    assert.is_true(vim.tbl_contains(cmd, '--thinking'))
    assert.is_true(vim.tbl_contains(cmd, 'high'))
  end)

  it("appends initial prompt as last arg", function()
    require('todo-ai.config').setup({})
    local cmd = init._build_cmd('fix the bug')
    assert.equals('fix the bug', cmd[#cmd])
  end)

  it("includes extra args", function()
    require('todo-ai.config').setup({ pi_extra_args = { '--continue', '--no-session' } })
    local cmd = init._build_cmd(nil)
    assert.is_true(vim.tbl_contains(cmd, '--continue'))
    assert.is_true(vim.tbl_contains(cmd, '--no-session'))
  end)

  it("returns valid context JSON", function()
    local json = init.remote_get_context()
    local ctx = vim.fn.json_decode(json)
    assert.is_table(ctx)
    assert.is_table(ctx.open_files)
  end)

  it("reports no pane alive when no tmux pane", function()
    assert.is_false(init._is_pane_alive())
  end)

  it("includes --resume in command", function()
    require('todo-ai.config').setup({})
    local cmd = init._build_cmd(nil)
    assert.is_true(vim.tbl_contains(cmd, '--resume'))
  end)
end)
