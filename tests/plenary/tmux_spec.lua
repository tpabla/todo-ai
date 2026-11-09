local tmux = require('todo-ai.tmux')
local config = require('todo-ai.config')

local function runner(stdout)
  local calls = {}
  return function(argv)
    table.insert(calls, argv)
    return stdout or ''
  end, calls
end

describe("tmux", function()
  local saved

  before_each(function()
    config.setup({})
    saved = vim.env.TMUX_PANE
    vim.env.TMUX_PANE = '%2'
  end)

  after_each(function()
    vim.env.TMUX_PANE = saved
  end)

  it("lists agent panes in the editor's session only", function()
    local lines = table.concat({
      '%1\tclaude\t/w/app\t✳ Fix login bug',
      '%2\tnvim\t/w/app\tnvim',
      '%3\tfish\t/w/app\tfish',
      '%4\tgrep\t/w/app\tgrep claude',
      '%5\tpi\t/w/app/api\tπ - api',
    }, '\n')
    local run, calls = runner(lines)
    assert.same({
      { id = '%1', kind = 'claude', cwd = '/w/app', title = '✳ Fix login bug' },
      { id = '%5', kind = 'pi', cwd = '/w/app/api', title = 'π - api' },
    }, tmux.list(run))
    assert.same({ 'tmux', 'list-panes', '-s', '-t', '%2' }, vim.list_slice(calls[1], 1, 5))
  end)

  it("sends the prompt literally, then Enter", function()
    local run, calls = runner()
    tmux.prompt('%1', 'what does -l do?', run)
    assert.same({
      { 'tmux', 'send-keys', '-t', '%1', '-l', 'what does -l do?' },
      { 'tmux', 'send-keys', '-t', '%1', 'Enter' },
    }, calls)
  end)

  it("focuses the pane's window, then the pane", function()
    local run, calls = runner()
    tmux.focus('%1', run)
    assert.same({
      { 'tmux', 'select-window', '-t', '%1' },
      { 'tmux', 'select-pane', '-t', '%1' },
    }, calls)
  end)

  it("reads a pane's window and session", function()
    local run = runner('$1\t@3\n')
    assert.same({ tab = '@3', workspace = '$1' }, tmux.location('%1', run))
  end)

  it("returns nil for a pane that is gone", function()
    local run = function() error("can't find pane: %99") end
    assert.is_nil(tmux.location('%99', run))
  end)

  it("spawns the agent in a split beside the editor", function()
    local run, calls = runner('%9\n')
    local agent = tmux.spawn({ kind = 'claude', cwd = '/w/app', direction = 'right' }, run)
    assert.same({ 'tmux', 'split-window', '-h', '-t', '%2', '-c', '/w/app',
      '-P', '-F', '#{pane_id}', 'claude' }, calls[1])
    assert.same({ id = '%9', kind = 'claude', cwd = '/w/app' }, agent)

    run, calls = runner('%9\n')
    tmux.spawn({ kind = 'pi', cwd = '/w/app', direction = 'down' }, run)
    assert.equals('-v', calls[1][3])
  end)
end)
