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

  describe("editor registry entry", function()
    local registry, tmp

    before_each(function()
      registry = require('todo-ai.registry')
      tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, 'p')
      registry.REGISTRY_DIR = tmp
    end)

    after_each(function()
      vim.fn.delete(tmp, 'rf')
      init.state.attached = nil
      init.state.tmux_pane = nil
    end)

    local function published()
      local dir = tmp .. '/' .. vim.fn.getpid()
      return vim.fn.json_decode(table.concat(vim.fn.readfile(dir .. '/editor.json'), '\n'))
    end

    it("records the attached pane so the agent resolves this editor", function()
      -- Without this the link is one-way: the agent falls back to cwd
      -- ancestry and may target a different nvim entirely.
      init._join_pane('%7', nil)
      assert.equals('%7', published().pane)
    end)

    it("clears the pane on disconnect", function()
      init._join_pane('%7', nil)
      init.disconnect()
      assert.is_nil(published().pane)
    end)

    it("clears the pane when the attached pane is no longer an agent", function()
      init._join_pane('%7', nil)
      assert.is_nil(init.attached_pane({ candidates = function() return {} end }))
      assert.is_nil(published().pane)
    end)
  end)

  describe(":TodoAIConnect with no argument", function()
    after_each(function()
      init.state.attached = nil
      init.state.tmux_pane = nil
    end)

    it("does not re-prompt while already connected", function()
      init.state.attached = '%1'
      init.state.tmux_pane = '%1'
      local prompted = false
      local result = init.connect(nil, {
        candidates = function() return { { id = '%1', agent = 'claude', dir = '/proj' } } end,
        select = function() prompted = true end,
        spawn = function() prompted = true end,
      })
      assert.is_false(prompted)
      assert.equals('%1', result)
    end)

    it("prompts when nothing is attached", function()
      local prompted = false
      init.connect(nil, {
        candidates = function() return { { id = '%1', agent = 'claude', dir = '/proj' } } end,
        select = function() prompted = true end,
      })
      assert.is_true(prompted)
    end)

    it("still always prompts via :TodoAI, even while attached", function()
      init.state.attached = '%1'
      init.state.tmux_pane = '%1'
      local prompted = false
      init.open_agent_interactive(nil, {
        candidates = function() return { { id = '%1', agent = 'claude', dir = '/proj' } } end,
        select = function() prompted = true end,
      })
      assert.is_true(prompted)
    end)
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

    it("flags a pane with no todo-ai integration loaded", function()
      -- The tag comes from the plugin's own hook, so an untagged pane cannot
      -- talk back to nvim however the user connects to it.
      local line = init._describe_pane({ id = '%59', agent = 'claude', dir = '/proj' })
      assert.is_true(line:find('no editor bridge', 1, true) ~= nil)

      local bridged = init._describe_pane({
        id = '%12', agent = 'claude', dir = '/proj', tagged = true,
      })
      assert.is_nil(bridged:find('no editor bridge', 1, true))
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
