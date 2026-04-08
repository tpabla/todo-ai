describe("init", function()
  local init

  before_each(function()
    package.loaded['todo-ai.init'] = nil
    package.loaded['todo-ai.config'] = nil
    init = require('todo-ai.init')
  end)

  describe("_build_cmd (pi harness)", function()
    it("builds pi command", function()
      require('todo-ai.config').setup({ harness = 'pi' })
      local cmd = init._build_cmd(nil)
      assert.equals('pi', cmd[1])
      assert.equals('-e', cmd[2])
      assert.is_true(cmd[3]:match('neovim%.ts$') ~= nil)
      assert.equals('--resume', cmd[4])
    end)

    it("appends initial prompt as last arg", function()
      require('todo-ai.config').setup({ harness = 'pi' })
      local cmd = init._build_cmd('fix the bug')
      assert.equals('fix the bug', cmd[#cmd])
    end)

    it("includes pi_extra_args", function()
      require('todo-ai.config').setup({
        harness = 'pi',
        pi_extra_args = { '--continue', '--no-session' },
      })
      local cmd = init._build_cmd(nil)
      assert.is_true(vim.tbl_contains(cmd, '--continue'))
      assert.is_true(vim.tbl_contains(cmd, '--no-session'))
    end)

    it("always includes --resume", function()
      require('todo-ai.config').setup({ harness = 'pi' })
      local cmd = init._build_cmd(nil)
      assert.is_true(vim.tbl_contains(cmd, '--resume'))
    end)
  end)

  describe("_build_cmd (claude_code harness)", function()
    it("builds claude command (default harness)", function()
      require('todo-ai.config').setup({})
      local cmd = init._build_cmd(nil)
      assert.equals('claude', cmd[1])
    end)

    it("includes --model when claude_model set", function()
      require('todo-ai.config').setup({ claude_model = 'sonnet' })
      local cmd = init._build_cmd(nil)
      assert.is_true(vim.tbl_contains(cmd, '--model'))
      assert.is_true(vim.tbl_contains(cmd, 'sonnet'))
    end)

    it("omits --model when not set", function()
      require('todo-ai.config').setup({})
      local cmd = init._build_cmd(nil)
      assert.is_false(vim.tbl_contains(cmd, '--model'))
    end)

    it("includes claude_extra_args", function()
      require('todo-ai.config').setup({ claude_extra_args = { '--verbose' } })
      local cmd = init._build_cmd(nil)
      assert.is_true(vim.tbl_contains(cmd, '--verbose'))
    end)

    it("appends initial prompt as last arg", function()
      require('todo-ai.config').setup({})
      local cmd = init._build_cmd('hello world')
      assert.equals('hello world', cmd[#cmd])
    end)
  end)

  it("errors on unknown harness", function()
    require('todo-ai.config').setup({ harness = 'bogus' })
    assert.has_error(function() init._build_cmd(nil) end)
  end)

  it("exposes backward-compatible aliases", function()
    assert.equals(init.open_agent, init.open_pi)
    assert.equals(init.focus_agent, init.focus_pi)
  end)

  it("returns valid context JSON", function()
    local json = init.remote_get_context()
    local ctx = vim.fn.json_decode(json)
    assert.is_table(ctx)
    assert.is_table(ctx.open_files)
  end)

  it("reports no pane alive when no state", function()
    init.state.tmux_pane = nil
    local pane_file = init._state_dir() .. '/pane-id'
    os.remove(pane_file)
    assert.is_false(init._is_pane_alive())
  end)

  it("generates CWD-based state dir", function()
    local dir = init._state_dir()
    assert.is_true(dir:match('^/tmp/todo%-ai%-') ~= nil)
    assert.equals(dir, init._state_dir())
  end)

  it("reads files correctly", function()
    local path = '/tmp/todo-ai-test-read-' .. vim.fn.getpid()
    vim.fn.writefile({ 'hello' }, path)
    assert.equals('hello', init._read_file(path))
    os.remove(path)
  end)

  it("returns nil for missing files", function()
    assert.is_nil(init._read_file('/tmp/nonexistent-todo-ai-test'))
  end)
end)
