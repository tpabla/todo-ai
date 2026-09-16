describe("registry", function()
  local registry, tmpdir

  -- tmux: id, pane_pid, foreground command, path, @agent, @name, @session, title
  local PANES = table.concat({
    "%1\t100\tclaude\t/proj/thing\tclaude\tapi\tsess-1\t✳ fix the parser",
    "%2\t200\tfish\t/proj/thing/repo-b\t\t\t\t~/proj",
    "%3\t300\tfish\t/proj/thing/repo-a\tclaude\t\t\t~/proj",
    "%4\t400\tfish\t/proj/deep\t\t\t\t",
    "%5\t500\tnode\t/proj/wrapped\tpi\twrapped\t\t✳ wrapped run",
    "%6\t600\tfish\t/proj/grep\t\t\t\t",
  }, '\n')

  -- ps -eo pid,ppid,comm
  local PROCS = table.concat({
    "  PID  PPID COMM",
    "  100     1 claude",
    "  200     1 -fish",
    "  300     1 -fish",
    "  400     1 -fish",
    "  450   400 /opt/homebrew/bin/claude",
    "  500     1 node",
    "  600     1 -fish",
    "  650   600 grep",
  }, '\n')

  local function specs()
    local harness = require('todo-ai.harness')
    return vim.tbl_map(function(n) return harness.get(n) end, harness.names())
  end

  local function state_of(id)
    local panes = registry.parse_panes(PANES)
    local procs = registry.parse_processes(PROCS)
    for _, p in ipairs(panes) do
      if p.id == id then return registry.pane_state(p, procs, specs()) end
    end
    error('no such pane in fixture: ' .. id)
  end

  before_each(function()
    for _, m in ipairs({ 'todo-ai.registry', 'todo-ai.paths', 'todo-ai.harness', 'todo-ai.config' }) do
      package.loaded[m] = nil
    end
    registry = require('todo-ai.registry')
    require('todo-ai.config').setup({})
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    registry.REGISTRY_DIR = tmpdir
  end)

  after_each(function()
    vim.fn.delete(tmpdir, 'rf')
  end)

  describe("parsing", function()
    it("parses every pane field, including empty tags", function()
      local panes = registry.parse_panes(PANES)
      assert.equals(6, #panes)
      assert.equals('%1', panes[1].id)
      assert.equals(100, panes[1].pid)
      assert.equals('claude', panes[1].command)
      assert.equals('/proj/thing', panes[1].dir)
      assert.equals('claude', panes[1].tag.agent)
      assert.equals('api', panes[1].tag.name)
      assert.equals('sess-1', panes[1].tag.session)
      assert.is_nil(panes[2].tag.agent)
    end)

    it("captures the pane title, mapping an empty one to nil", function()
      local panes = registry.parse_panes(PANES)
      assert.equals('✳ fix the parser', panes[1].title)
      assert.is_nil(panes[4].title)
    end)

    it("builds a pid map from ps output", function()
      local procs = registry.parse_processes(PROCS)
      assert.equals(1, procs[100].ppid)
      assert.equals('claude', procs[100].name)
      assert.equals(400, procs[450].ppid)
      -- basename of the full path, so matching is exact rather than substring
      assert.equals('claude', procs[450].name)
      -- login shells arrive with a leading dash
      assert.equals('fish', procs[200].name)
      assert.is_nil(procs[1])
    end)
  end)

  describe("pane_state", function()
    it("is active when the foreground command is an agent", function()
      assert.equals('agent', state_of('%1'))
    end)

    it("is active when an agent is a descendant of a shell pane", function()
      -- tmux reports the pane's foreground process; an agent launched under a
      -- wrapper or subshell is only visible in the process tree.
      assert.equals('agent', state_of('%4'))
    end)

    it("is stale when tagged but the pane fell back to a shell", function()
      -- The defect this replaces: quitting the agent left the tag behind and
      -- the pane still received keystrokes.
      assert.equals('stale', state_of('%3'))
    end)

    it("trusts the tag when a non-shell process is running", function()
      -- A node-wrapped agent reports 'node' in both signals.
      assert.equals('agent', state_of('%5'))
    end)

    it("is not an agent for an untagged shell", function()
      assert.equals('none', state_of('%2'))
    end)

    it("ignores an incidental descendant that merely mentions an agent", function()
      -- `grep claude` in a pane must not register as an agent.
      assert.equals('none', state_of('%6'))
    end)
  end)

  describe("agent_panes", function()
    it("keeps active panes with their tag metadata and reports stale ones", function()
      local active, stale = registry.agent_panes(
        registry.parse_panes(PANES), registry.parse_processes(PROCS), specs())

      local ids = vim.tbl_map(function(p) return p.id end, active)
      assert.same({ '%1', '%4', '%5' }, ids)
      assert.equals('api', active[1].name)
      assert.equals('sess-1', active[1].session)
      assert.equals('wrapped', active[3].name)
      -- The title is where Claude Code writes a human-readable session name.
      assert.equals('✳ fix the parser', active[1].title)
      assert.equals('✳ wrapped run', active[3].title)

      assert.same({ '%3' }, vim.tbl_map(function(p) return p.id end, stale))
    end)
  end)

  describe("candidates", function()
    it("reads current state on every call and caches nothing", function()
      local first = registry.candidates('/proj/thing',
        { panes_raw = PANES, ps_raw = PROCS, untag = function() end })
      assert.equals(3, #first)

      -- Same call, different world: the agent panes are gone.
      local second = registry.candidates('/proj/thing', {
        panes_raw = "%9\t900\tfish\t/proj/thing\t\t\t",
        ps_raw = "  PID  PPID COMM\n  900     1 -fish",
        untag = function() end,
      })
      assert.equals(0, #second)
    end)

    it("clears the tags on a stale pane so it self-heals", function()
      local untagged = {}
      registry.candidates('/proj/thing', {
        panes_raw = PANES, ps_raw = PROCS,
        untag = function(id) table.insert(untagged, id) end,
      })
      assert.same({ '%3' }, untagged)
    end)

    it("ranks exact, then nearest parent, then child, then unrelated", function()
      local found = {
        { id = '%1', agent = 'claude', dir = '/proj/thing' },
        { id = '%2', agent = 'claude', dir = '/elsewhere' },
        { id = '%3', agent = 'claude', dir = '/proj/thing/repo-b' },
        { id = '%4', agent = 'claude', dir = '/proj/thing/repo-b/sub/x' },
      }
      local ranked = registry.candidates('/proj/thing/repo-b', { panes = found })
      assert.same({ '%3', '%1', '%4', '%2' },
        vim.tbl_map(function(p) return p.id end, ranked))
    end)

    it("dedupes by pane id", function()
      local found = {
        { id = '%1', agent = 'claude', dir = '/proj/thing', name = 'api' },
        { id = '%1', agent = 'claude', dir = '/proj/thing' },
      }
      local ranked = registry.candidates('/proj/thing', { panes = found })
      assert.equals(1, #ranked)
      assert.equals('api', ranked[1].name)
    end)
  end)

  describe("editor registry", function()
    it("round-trips a published editor entry", function()
      registry.publish({ socket = '/tmp/nvim.sock', cwd = '/proj/repo', pid = vim.fn.getpid() })
      local editors = registry.list_editors()
      assert.equals(1, #editors)
      assert.equals('/tmp/nvim.sock', editors[1].socket)

      registry.unpublish()
      assert.equals(0, #registry.list_editors())
    end)

    it("prunes entries whose process is gone", function()
      registry.publish({ socket = '/tmp/dead.sock', cwd = '/proj', pid = 4194304 })
      assert.equals(0, #registry.list_editors())
      assert.equals(0, #vim.fn.readdir(tmpdir))
    end)
  end)
end)
