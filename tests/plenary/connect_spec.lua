describe("connect", function()
  local init

  before_each(function()
    package.loaded['todo-ai.init'] = nil
    package.loaded['todo-ai.config'] = nil
    package.loaded['todo-ai.registry'] = nil
    init = require('todo-ai.init')
    require('todo-ai.config').setup({})
    -- The flows guard on tmux; the deps below stand in for it.
    if not vim.env.TMUX then vim.env.TMUX = 'test' end
  end)

  it("spawns immediately when no agent panes exist", function()
    local spawned, prompted = false, false
    init.open_agent_interactive(nil, {
      candidates = function() return {} end,
      spawn = function() spawned = true end,
      select = function() prompted = true end,
    })
    assert.is_true(spawned)
    assert.is_false(prompted)
  end)

  it("prompts even when exactly one agent pane exists", function()
    -- Regression: the old code auto-joined silently on a single match, so
    -- there was no way to confirm which session you were attaching to.
    local prompted, joined = false, nil
    init.open_agent_interactive(nil, {
      candidates = function() return { { id = '%1', agent = 'claude', dir = '/proj' } } end,
      spawn = function() error('should not spawn when a candidate exists') end,
      select = function(items, _, cb) prompted = true; cb(items[1]) end,
      join = function(pane_id) joined = pane_id end,
    })
    assert.is_true(prompted)
    assert.equals('%1', joined)
  end)

  it("rejects a relative path instead of resolving it against the cwd", function()
    -- The agent may sit above nvim in the tree, so a relative path is
    -- ambiguous and must never be resolved against vim.fn.getcwd().
    local ok, err = pcall(init.remote_open, 'src/foo.lua', 10)
    assert.is_false(ok)
    assert.is_true(tostring(err):lower():find('absolute', 1, true) ~= nil)
  end)

  it("refuses to send to an attached pane that is no longer an agent", function()
    -- The pane may have dropped back to a shell since it was chosen; sending
    -- keys then types the prompt into the user's shell.
    init.state.attached = '%1'
    init.state.tmux_pane = '%1'
    local sent, prompted = false, false
    init.send_prompt('hello', {
      candidates = function() return {} end,
      spawn = function() prompted = true end,
      select = function() prompted = true end,
      send_keys = function() sent = true end,
    })
    assert.is_false(sent)
    assert.is_true(prompted)
    assert.is_nil(init.state.attached)
  end)

  it("delivers to an attached pane that is still an agent", function()
    init.state.attached = '%1'
    init.state.tmux_pane = '%1'
    local sent
    init.send_prompt('hello', {
      candidates = function() return { { id = '%1', agent = 'claude', dir = '/proj' } } end,
      send_keys = function(pane, text) sent = { pane = pane, text = text } end,
    })
    assert.equals('%1', sent.pane)
    assert.equals('hello', sent.text)
  end)

  it("prunes dead editor entries on setup", function()
    local registry = require('todo-ai.registry')
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, 'p')
    registry.REGISTRY_DIR = tmp
    registry.publish({ socket = '/tmp/dead.sock', cwd = '/proj', pid = 4194304 })
    assert.equals(1, #vim.fn.readdir(tmp))

    init.setup({})
    assert.is_false(vim.tbl_contains(vim.fn.readdir(tmp), '4194304'))
    vim.fn.delete(tmp, 'rf')
  end)

  describe("picker line", function()
    it("shows the session title with the agent's marker stripped", function()
      local line = init._describe_pane({
        id = '%74', agent = 'claude', dir = vim.fn.expand('~') .. '/Projects/todo-ai',
        title = '✳ todoai-integration', rank = 'exact',
      })
      assert.is_true(line:find('%%74') ~= nil)
      assert.is_true(line:find('todoai-integration', 1, true) ~= nil)
      assert.is_nil(line:find('✳', 1, true))
      -- Home-relative so the line stays readable
      assert.is_true(line:find('~/Projects/todo-ai', 1, true) ~= nil)
    end)

    it("omits a title that carries no information", function()
      -- tmux defaults pane_title to the hostname, and it can also just echo
      -- the running command.
      local host = vim.fn.hostname()
      local default_title = init._describe_pane({
        id = '%1', agent = 'claude', dir = '/proj', title = host, rank = 'exact',
      })
      assert.is_nil(default_title:find(host, 1, true))

      local echoes_command = init._describe_pane({
        id = '%2', agent = 'claude', dir = '/proj', title = 'claude',
        command = 'claude', rank = 'exact',
      })
      local _, count = echoes_command:gsub('claude', '')
      assert.equals(1, count)
    end)

    it("still renders a pane with no title at all", function()
      local line = init._describe_pane({ id = '%9', agent = 'claude', dir = '/proj' })
      assert.is_true(line:find('%%9') ~= nil)
      assert.is_true(line:find('/proj', 1, true) ~= nil)
    end)
  end)

  it("keeps harness branching out of init.lua", function()
    -- Mechanically enforces the adapter boundary: a new harness must not
    -- require edits to init.lua.
    local src = table.concat(vim.fn.readfile(init._plugin_root() .. '/lua/todo-ai/init.lua'), '\n')
    assert.is_nil(src:find('HARNESS_PI', 1, true))
    assert.is_nil(src:find('HARNESS_CLAUDE_CODE', 1, true))
    assert.is_nil(src:find("== 'pi'", 1, true))
    assert.is_nil(src:find("== 'claude_code'", 1, true))
  end)
end)
