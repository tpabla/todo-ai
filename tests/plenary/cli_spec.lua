local cli = require('todo-ai.cli')

-- A world of editors: socket -> { cwd, pane }; pane -> { tab, workspace }.
-- Sockets missing from `editors` are dead.
local function world(opts)
  local calls, out, err = {}, {}, {}
  local deps = {
    self_pane = function() return opts.self_pane end,
    cwd = function() return opts.cwd or '/w/app' end,
    read_attachment = function(id) return (opts.attachments or {})[id] end,
    sockets = function() return opts.sockets or vim.tbl_keys(opts.editors or {}) end,
    identity = function(sock) return (opts.editors or {})[sock] end,
    location = function(pane) return (opts.locations or {})[pane] end,
    call = function(sock, fn, args)
      table.insert(calls, { sock = sock, fn = fn, args = args })
      return (opts.returns or {})[fn]
    end,
    print = function(s) table.insert(out, s) end,
    eprint = function(s) table.insert(err, s) end,
  }
  return deps, { calls = calls, out = out, err = err }
end

-- Agent in w1:t1 of workspace w1, which has a second tab w1:t2.
local LOCATIONS = {
  ['w1:p1'] = { tab = 'w1:t1', workspace = 'w1' },
  ['w1:p2'] = { tab = 'w1:t1', workspace = 'w1' },
  ['w1:p3'] = { tab = 'w1:t1', workspace = 'w1' },
  ['w1:p5'] = { tab = 'w1:t2', workspace = 'w1' },
  ['w1:p6'] = { tab = 'w1:t2', workspace = 'w1' },
  ['w1:p7'] = { tab = 'w1:t2', workspace = 'w1' },
  ['w2:p1'] = { tab = 'w2:t1', workspace = 'w2' },
}

local function resolve(opts)
  opts.locations = opts.locations or LOCATIONS
  return cli.resolve((world(opts)))
end

describe("cli.resolve", function()
  it("uses the attached editor when its socket is alive", function()
    local ed = resolve({
      self_pane = 'w1:p1',
      attachments = { ['w1:p1'] = '/s/a' },
      editors = {
        ['/s/a'] = { cwd = '/elsewhere', pane = 'w1:p5' },
        ['/s/b'] = { cwd = '/w/app', pane = 'w1:p2' },
      },
    })
    assert.same({ socket = '/s/a', how = 'attached' }, ed)
  end)

  it("falls through to the same tab when the attached socket is dead", function()
    local ed = resolve({
      self_pane = 'w1:p1',
      attachments = { ['w1:p1'] = '/s/dead' },
      editors = { ['/s/b'] = { cwd = '/elsewhere', pane = 'w1:p2' } },
    })
    assert.same({ socket = '/s/b', how = 'same tab' }, ed)
  end)

  it("uses cwd only when the agent is outside a multiplexer", function()
    local ed = resolve({
      cwd = '/w/app',
      editors = {
        ['/s/a'] = { cwd = '/w/app' },
        ['/s/b'] = { cwd = '/w/other', pane = 'w2:p1' },
      },
    })
    assert.same({ socket = '/s/a', how = 'cwd' }, ed)
  end)

  it("picks the only editor in the agent's tab", function()
    local ed = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/app',
      editors = {
        ['/s/tab'] = { cwd = '/unrelated', pane = 'w1:p2' },
        ['/s/far'] = { cwd = '/w/app', pane = 'w1:p5' },
      },
    })
    assert.same({ socket = '/s/tab', how = 'same tab' }, ed)
  end)

  it("ranks by cwd when several editors share the agent's tab", function()
    local ed = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/a',
      editors = {
        ['/s/a'] = { cwd = '/w/a', pane = 'w1:p2' },
        ['/s/b'] = { cwd = '/w/b', pane = 'w1:p3' },
      },
    })
    assert.same({ socket = '/s/a', how = 'cwd' }, ed)
  end)

  it("never considers editors outside the agent's workspace", function()
    local ed, err = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/app',
      editors = {
        ['/s/other'] = { cwd = '/w/app', pane = 'w2:p1' },
        ['/s/bare'] = { cwd = '/w/app' },
      },
    })
    assert.is_nil(ed)
    assert.matches('no editor', err)
  end)

  it("prefers exact over parent over child", function()
    local editors = {
      ['/s/parent'] = { cwd = '/w/a', pane = 'w1:p5' },
      ['/s/exact'] = { cwd = '/w/a/b', pane = 'w1:p6' },
      ['/s/child'] = { cwd = '/w/a/b/c', pane = 'w1:p7' },
    }
    local opts = { self_pane = 'w1:p1', cwd = '/w/a/b', editors = editors }
    assert.equals('/s/exact', resolve(opts).socket)

    editors['/s/exact'] = nil
    assert.equals('/s/parent', resolve(opts).socket)
  end)

  it("picks the deepest parent", function()
    local ed = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/a/b',
      editors = {
        ['/s/top'] = { cwd = '/w', pane = 'w1:p5' },
        ['/s/near'] = { cwd = '/w/a', pane = 'w1:p6' },
      },
    })
    assert.equals('/s/near', ed.socket)
  end)

  it("picks the shallowest child", function()
    local ed = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/a',
      editors = {
        ['/s/near'] = { cwd = '/w/a/b', pane = 'w1:p5' },
        ['/s/deep'] = { cwd = '/w/a/b/c', pane = 'w1:p6' },
      },
    })
    assert.equals('/s/near', ed.socket)
  end)

  it("errors when no editor is related by path", function()
    local ed, err = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/a',
      editors = { ['/s/x'] = { cwd = '/elsewhere', pane = 'w1:p5' } },
    })
    assert.is_nil(ed)
    assert.matches('no editor', err)
  end)

  it("errors on a tie and lists the candidates", function()
    local ed, err = resolve({
      self_pane = 'w1:p1',
      cwd = '/w/a',
      editors = {
        ['/s/x'] = { cwd = '/w/a', pane = 'w1:p5' },
        ['/s/y'] = { cwd = '/w/a', pane = 'w1:p6' },
      },
    })
    assert.is_nil(ed)
    assert.matches('/s/x', err, 1, true)
    assert.matches('/s/y', err, 1, true)
    assert.matches(':TodoAI', err, 1, true)
  end)

  it("errors when no editor is running", function()
    local ed, err = resolve({ self_pane = 'w1:p1', editors = {} })
    assert.is_nil(ed)
    assert.matches('no editor running', err)
  end)

  it("ignores dead sockets", function()
    local ed = resolve({
      cwd = '/w/a',
      sockets = { '/s/dead', '/s/live' },
      editors = { ['/s/live'] = { cwd = '/w/a' } },
    })
    assert.equals('/s/live', ed.socket)
  end)

  it("treats a symlinked cwd as the same directory", function()
    local real = vim.fn.tempname()
    vim.fn.mkdir(real, 'p')
    local link = vim.fn.tempname()
    vim.uv.fs_symlink(real, link)

    local ed = resolve({
      cwd = link,
      editors = {
        ['/s/real'] = { cwd = vim.uv.fs_realpath(real) },
        ['/s/parent'] = { cwd = vim.fs.dirname(vim.uv.fs_realpath(real)) },
      },
    })
    assert.equals('/s/real', ed.socket)
  end)

  it("does not treat a sibling with a shared prefix as an ancestor", function()
    local ed, err = resolve({
      cwd = '/w/foobar',
      editors = { ['/s/foo'] = { cwd = '/w/foo' } },
    })
    assert.is_nil(ed)
    assert.matches('no editor', err)
  end)
end)

describe("cli.parse_location", function()
  it("parses a bare path", function()
    assert.same({ path = '/w/a.lua' }, cli.parse_location('/w/a.lua', '/w'))
  end)

  it("parses a single line", function()
    assert.same({ path = '/w/a.lua', first = 12, last = 12 },
      cli.parse_location('/w/a.lua:12', '/w'))
  end)

  it("parses a range", function()
    assert.same({ path = '/w/a.lua', first = 12, last = 30 },
      cli.parse_location('/w/a.lua:12-30', '/w'))
  end)

  it("resolves a relative path against the agent's cwd", function()
    assert.same({ path = '/w/src/a.lua', first = 3, last = 3 },
      cli.parse_location('src/a.lua:3', '/w'))
  end)

  it("rejects a reversed range", function()
    local loc, err = cli.parse_location('/w/a.lua:30-12', '/w')
    assert.is_nil(loc)
    assert.matches('range', err)
  end)
end)

describe("cli.run", function()
  local editors = { ['/s/a'] = { cwd = '/w/app' } }

  it("prints usage and exits 2 without a command", function()
    local deps, io = world({ editors = editors })
    assert.equals(2, cli.run({}, deps))
    assert.matches('usage', io.err[1])
  end)

  it("prints usage and exits 2 on an unknown command", function()
    local deps, io = world({ editors = editors })
    assert.equals(2, cli.run({ 'frobnicate' }, deps))
    assert.matches('usage', io.err[1])
  end)

  it("skips resolution with --editor", function()
    local deps, io = world({ editors = {} })
    assert.equals(0, cli.run({ '--editor', '/s/given', 'reload' }, deps))
    assert.same({ sock = '/s/given', fn = 'remote_reload', args = {} }, io.calls[1])
  end)

  it("opens an absolute path and range", function()
    local deps, io = world({ cwd = '/w/app', editors = editors })
    assert.equals(0, cli.run({ 'open', 'src/a.lua:4-9' }, deps))
    assert.same({ sock = '/s/a', fn = 'remote_open', args = { '/w/app/src/a.lua', 4, 9 } },
      io.calls[1])
  end)

  it("prints context as JSON", function()
    local ctx = { cwd = '/w/app', current_file = '/w/app/a.lua', cursor_line = 3 }
    local deps, io = world({ editors = editors, returns = { remote_get_context = ctx } })
    assert.equals(0, cli.run({ 'context' }, deps))
    assert.same(ctx, vim.json.decode(io.out[1]))
  end)

  it("prints the chosen editor and why with which", function()
    local deps, io = world({ editors = editors })
    assert.equals(0, cli.run({ 'which' }, deps))
    assert.matches('/s/a', io.out[1], 1, true)
    assert.matches('cwd', io.out[1], 1, true)
  end)

  it("exits 1 with the reason when no editor resolves", function()
    local deps, io = world({ editors = {} })
    assert.equals(1, cli.run({ 'diff' }, deps))
    assert.matches('no editor running', io.err[1])
    assert.equals(0, #io.calls)
  end)
end)
