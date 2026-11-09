local herdr = require('todo-ai.herdr')

local function fixture(name)
  local f = assert(io.open('tests/fixtures/' .. name, 'r'))
  local s = f:read('*a')
  f:close()
  return s
end

-- Fake runner keyed by the herdr subcommand ("agent list", "pane split", ...).
local function runner(responses)
  local calls = {}
  local run = function(argv)
    table.insert(calls, argv)
    local r = responses[argv[2] .. ' ' .. argv[3]]
    if type(r) == 'function' then return r(argv) end
    if r == nil then error('unexpected: ' .. table.concat(argv, ' ')) end
    return r
  end
  return run, calls
end

local function find(calls, sub)
  for _, argv in ipairs(calls) do
    if argv[2] .. ' ' .. argv[3] == sub then return argv end
  end
end

describe("herdr.list", function()
  it("returns the agents in the editor's current workspace", function()
    local run = runner({
      ['pane current'] = fixture('herdr_pane_current.json'),
      ['agent list'] = fixture('herdr_agent_list.json'),
    })
    assert.same({
      { id = 'w1:p1', kind = 'claude', cwd = '/work/app', title = 'Fix login bug' },
      { id = 'w1:p4', kind = 'pi', cwd = '/work/app/api', title = 'π - api', name = 'reviewer' },
    }, herdr.list(run))
  end)
end)

describe("herdr commands", function()
  it("prompts an agent", function()
    local run, calls = runner({ ['agent prompt'] = '{}' })
    herdr.prompt('w1:p1', 'what does this do?', run)
    assert.same({ 'herdr', 'agent', 'prompt', 'w1:p1', 'what does this do?' }, calls[1])
  end)

  it("focuses an agent", function()
    local run, calls = runner({ ['agent focus'] = '{}' })
    herdr.focus('w1:p1', run)
    assert.same({ 'herdr', 'agent', 'focus', 'w1:p1' }, calls[1])
  end)

  it("reads a pane's tab and workspace", function()
    local run, calls = runner({ ['pane get'] = fixture('herdr_pane_get.json') })
    assert.same({ tab = 'w1:t1', workspace = 'w1' }, herdr.location('w1:p2', run))
    assert.same({ 'herdr', 'pane', 'get', 'w1:p2' }, calls[1])
  end)

  it("returns nil for a pane that is gone", function()
    local run = runner({ ['pane get'] = function() error('pane_not_found') end })
    assert.is_nil(herdr.location('w1:p99', run))
  end)
end)

describe("herdr.spawn", function()
  local function spawn_with(cwd, list)
    local run, calls = runner({
      ['agent list'] = list or fixture('herdr_agent_list.json'),
      ['pane split'] = fixture('herdr_pane_split.json'),
      ['agent start'] = '{}',
    })
    local agent = herdr.spawn({ kind = 'claude', cwd = cwd, direction = 'right' }, run)
    return agent, calls
  end

  it("splits the editor's pane and starts the agent in it", function()
    local agent, calls = spawn_with('/work/app')
    assert.same({ 'herdr', 'pane', 'split', '--current', '--direction', 'right',
      '--cwd', '/work/app', '--no-focus' }, find(calls, 'pane split'))
    local start = find(calls, 'agent start')
    assert.same({ '--kind', 'claude', '--pane', 'w1:p9' }, vim.list_slice(start, 5, 8))
    assert.same({ id = 'w1:p9', kind = 'claude', cwd = '/work/app', name = start[4] }, agent)
  end)

  it("names the agent after the cwd within herdr's name rules", function()
    local _, calls = spawn_with('/x/ACE-Step-1.5')
    assert.equals('ace-step-1-5', find(calls, 'agent start')[4])

    _, calls = spawn_with('/x/2048')
    local name = find(calls, 'agent start')[4]
    assert.matches('^[a-z][a-z0-9_-]*$', name)
    assert.is_true(#name <= 32)
  end)

  it("suffixes the name when a live agent already has it", function()
    local list = vim.json.encode({ result = { agents = {
      { agent = 'claude', pane_id = 'w1:p1', workspace_id = 'w1', name = 'app' },
      { agent = 'claude', pane_id = 'w3:p1', workspace_id = 'w3', name = 'app-2' },
    } } })
    local _, calls = spawn_with('/work/app', list)
    assert.equals('app-3', find(calls, 'agent start')[4])
  end)

  it("raises herdr's error when the agent fails to start", function()
    local run = runner({
      ['agent list'] = fixture('herdr_agent_list.json'),
      ['pane split'] = fixture('herdr_pane_split.json'),
      ['agent start'] = function() error('agent_not_ready') end,
    })
    assert.has_error(function()
      herdr.spawn({ kind = 'claude', cwd = '/work/app', direction = 'right' }, run)
    end)
  end)
end)
