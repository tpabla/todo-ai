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
    assert.equals('-e', cmd[2])
    assert.is_true(cmd[3]:match('neovim%.ts$') ~= nil)
    assert.equals('--resume', cmd[4])
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

  it("always includes --resume", function()
    require('todo-ai.config').setup({})
    local cmd = init._build_cmd(nil)
    assert.is_true(vim.tbl_contains(cmd, '--resume'))
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

  it("generates instance-specific prompt file", function()
    local path = init._prompt_file()
    assert.is_true(path:match('/tmp/todo%-ai%-prompt%-%d+%.md') ~= nil)
  end)
end)
