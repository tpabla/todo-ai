describe("harness registry", function()
  local harness, interface

  -- nil cannot be stored in a Lua table, so removal needs a sentinel
  local REMOVE = {}

  local function valid_spec(overrides)
    local spec = {
      name = 'testh',
      label = 'testh',
      bin = 'true',
      process_pattern = 'testh',
      deliver = 'send_keys',
      scan_prompt = '/scan',
      build_cmd = function() return { 'true' } end,
      resume_args = function(id) return { '--resume', id } end,
      installed = function() return true end,
      install = function() return true end,
    }
    for k, v in pairs(overrides or {}) do
      spec[k] = (v ~= REMOVE) and v or nil
    end
    return spec
  end

  before_each(function()
    package.loaded['todo-ai.harness'] = nil
    package.loaded['todo-ai.harness.interface'] = nil
    package.loaded['todo-ai.config'] = nil
    harness = require('todo-ai.harness')
    interface = require('todo-ai.harness.interface')
  end)

  it("rejects a spec missing a required field", function()
    for field, _ in pairs(interface.FIELDS) do
      local spec = valid_spec({ [field] = REMOVE })
      local ok = interface.validate(spec)
      assert.is_false(ok, 'expected validate() to reject missing field: ' .. field)
    end
  end)

  it("rejects a field of the wrong type", function()
    assert.is_false(interface.validate(valid_spec({ build_cmd = 'not a function' })))
    assert.is_false(interface.validate(valid_spec({ label = 42 })))
  end)

  it("rejects an unknown delivery mode", function()
    assert.is_false(interface.validate(valid_spec({ deliver = 'carrier_pigeon' })))
  end)

  it("accepts a complete spec", function()
    assert.is_true(interface.validate(valid_spec()))
  end)

  it("ships specs that satisfy the contract", function()
    for _, name in ipairs({ 'claude_code', 'pi' }) do
      local spec = harness.get(name)
      local ok, err = interface.validate(spec)
      assert.is_true(ok, name .. ' violates the harness contract: ' .. tostring(err))
    end
  end)

  it("errors listing known names for an unknown harness", function()
    require('todo-ai.config').setup({ harness = 'bogus' })
    local ok, err = pcall(harness.current)
    assert.is_false(ok)
    assert.is_true(tostring(err):find('claude_code', 1, true) ~= nil)
    assert.is_true(tostring(err):find('pi', 1, true) ~= nil)
  end)

  describe("built-in specs", function()
    it("claude_code builds a command with plugin-dir and model", function()
      require('todo-ai.config').setup({ harness = 'claude_code', claude_model = 'sonnet' })
      local cmd = harness.get('claude_code').build_cmd({ plugin_root = '/plug' })
      assert.equals('claude', cmd[1])
      assert.is_true(vim.tbl_contains(cmd, '--plugin-dir'))
      assert.is_true(vim.tbl_contains(cmd, '/plug'))
      assert.is_true(vim.tbl_contains(cmd, '--model'))
      assert.is_true(vim.tbl_contains(cmd, 'sonnet'))
    end)

    it("pi builds a command loading the extension", function()
      require('todo-ai.config').setup({ harness = 'pi' })
      local cmd = harness.get('pi').build_cmd({ extension_path = '/plug/extension/neovim.ts' })
      assert.equals('pi', cmd[1])
      assert.is_true(vim.tbl_contains(cmd, '-e'))
      assert.is_true(vim.tbl_contains(cmd, '/plug/extension/neovim.ts'))
    end)

    it("targets a specific session with harness-appropriate args", function()
      -- claude resumes by id; pi's --resume is an interactive picker with no
      -- id argument, so it must use --session.
      assert.same({ '--resume', 'abc123' }, harness.get('claude_code').resume_args('abc123'))
      assert.same({ '--session', 'abc123' }, harness.get('pi').resume_args('abc123'))
    end)
  end)

  describe("deliver_prompt", function()
    it("routes send_keys harnesses through tmux", function()
      local sent = {}
      local spec = valid_spec({ deliver = 'send_keys' })
      harness.deliver_prompt(spec, '%9', 'hello', {
        send_keys = function(pane, text) sent = { pane = pane, text = text } end,
      })
      assert.equals('%9', sent.pane)
      assert.equals('hello', sent.text)
    end)

    it("routes prompt_file harnesses through a file", function()
      local wrote = {}
      local spec = valid_spec({ deliver = 'prompt_file' })
      harness.deliver_prompt(spec, '%9', 'hello', {
        write_prompt = function(text) wrote.text = text end,
      })
      assert.equals('hello', wrote.text)
    end)
  end)
end)
