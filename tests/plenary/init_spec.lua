local function fake_backend(agents)
  local b = { calls = {}, agents = agents or {} }
  b.list = function() return b.agents end
  b.spawn = function(opts)
    table.insert(b.calls, { 'spawn', opts })
    local a = { id = 'w1:p9', kind = opts.kind, cwd = opts.cwd }
    table.insert(b.agents, a)
    return a
  end
  b.prompt = function(id, text) table.insert(b.calls, { 'prompt', id, text }) end
  b.focus = function(id) table.insert(b.calls, { 'focus', id }) end
  return b
end

local function read(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end

describe("init", function()
  local init, dir

  before_each(function()
    package.loaded['todo-ai.init'] = nil
    package.loaded['todo-ai.config'] = nil
    init = require('todo-ai.init')
    require('todo-ai.config').setup({})
    dir = vim.fn.tempname()
  end)

  -- select picks the item at `choice` (an index, or nil to cancel).
  local function deps(backend, choice)
    local shown
    return {
      backend = backend,
      attach_dir = dir,
      socket = function() return '/s/me' end,
      cwd = function() return '/w/app' end,
      select = function(items, _, cb)
        shown = items
        cb(choice and items[choice] or nil)
      end,
    }, function() return shown end
  end

  describe("_backend", function()
    local function env(t) return function(k) return t[k] end end

    it("prefers herdr, even inside tmux", function()
      assert.equals(require('todo-ai.herdr'),
        init._backend(env({ HERDR_ENV = '1', TMUX = '/tmp/tmux' })))
    end)

    it("uses tmux outside herdr", function()
      assert.equals(require('todo-ai.tmux'), init._backend(env({ TMUX = '/tmp/tmux' })))
    end)

    it("errors outside both", function()
      assert.has_error(function() init._backend(env({})) end)
    end)
  end)

  describe("pick", function()
    it("spawns and attaches when the workspace has no agents", function()
      local b = fake_backend()
      local d, shown = deps(b, 1)
      local attached
      init.pick(d, function(a) attached = a end)
      assert.same({ 'spawn', { kind = 'claude', cwd = '/w/app', direction = 'right' } }, b.calls[1])
      assert.is_nil(shown())
      assert.equals('w1:p9', attached.id)
      assert.equals('/s/me', read(dir .. '/w1:p9'))
    end)

    it("attaches the chosen agent", function()
      local b = fake_backend({ { id = 'w1:p1', kind = 'claude', cwd = '/w/app' } })
      local d, shown = deps(b, 1)
      local attached
      init.pick(d, function(a) attached = a end)
      assert.equals(init.NEW_AGENT, shown()[#shown()])
      assert.equals('w1:p1', attached.id)
      assert.equals(0, #b.calls)
    end)

    it("spawns when New agent is chosen", function()
      local b = fake_backend({ { id = 'w1:p1', kind = 'claude', cwd = '/w/app' } })
      local d = deps(b, 2)
      local attached
      init.pick(d, function(a) attached = a end)
      assert.equals('spawn', b.calls[1][1])
      assert.equals('w1:p9', attached.id)
    end)

    it("does nothing when cancelled", function()
      local b = fake_backend({ { id = 'w1:p1', kind = 'claude', cwd = '/w/app' } })
      local called = false
      init.pick((deps(b, nil)), function() called = true end)
      assert.is_false(called)
      assert.is_nil(init.state.agent)
    end)
  end)

  describe("attachment", function()
    it("writes this editor's socket under the agent's pane", function()
      local d = deps(fake_backend())
      init._attach({ id = 'w1:p1' }, d)
      assert.equals('/s/me', read(dir .. '/w1:p1'))
    end)

    it("removes the previous attachment when switching agents", function()
      local d = deps(fake_backend())
      init._attach({ id = 'w1:p1' }, d)
      init._attach({ id = 'w1:p4' }, d)
      assert.is_nil(read(dir .. '/w1:p1'))
      assert.equals('/s/me', read(dir .. '/w1:p4'))
    end)

    it("removes the attachment on detach", function()
      local d = deps(fake_backend())
      init._attach({ id = 'w1:p1' }, d)
      init._detach(d)
      assert.is_nil(read(dir .. '/w1:p1'))
      assert.is_nil(init.state.agent)
    end)

    it("forgets an attached agent that has gone", function()
      local b = fake_backend({ { id = 'w1:p1' } })
      local d = deps(b)
      init._attach({ id = 'w1:p1' }, d)
      assert.equals('w1:p1', init.attached(d).id)

      b.agents = {}
      assert.is_nil(init.attached(d))
      assert.is_nil(read(dir .. '/w1:p1'))
    end)
  end)

  describe("send", function()
    it("prompts the attached agent", function()
      local b = fake_backend({ { id = 'w1:p1' } })
      local d = deps(b)
      init._attach({ id = 'w1:p1' }, d)
      init.send('explain this', d)
      assert.same({ 'prompt', 'w1:p1', 'explain this' }, b.calls[1])
    end)

    it("picks first when nothing is attached", function()
      local b = fake_backend({ { id = 'w1:p1' } })
      init.send('explain this', (deps(b, 1)))
      assert.same({ 'prompt', 'w1:p1', 'explain this' }, b.calls[1])
    end)

    it("ignores empty text", function()
      local b = fake_backend({ { id = 'w1:p1' } })
      init.send('', (deps(b, 1)))
      init.send(nil, (deps(b, 1)))
      assert.equals(0, #b.calls)
    end)

    it("asks the agent to resolve tagged comments on scan", function()
      local b = fake_backend({ { id = 'w1:p1' } })
      init.scan((deps(b, 1)))
      assert.matches('AGENT:', b.calls[1][3], 1, true)
    end)

    it("focuses the attached agent", function()
      local b = fake_backend({ { id = 'w1:p1' } })
      local d = deps(b)
      init._attach({ id = 'w1:p1' }, d)
      init.focus(d)
      assert.same({ 'focus', 'w1:p1' }, b.calls[1])
    end)
  end)

  describe("_selection_prompt", function()
    it("includes the file, range, fenced code, and question", function()
      local p = init._selection_prompt({
        file = '/w/app/retry.ts', start_line = 12, end_line = 14,
        filetype = 'typescript', text = 'a\nb\nc',
      }, 'what does this do?')
      assert.equals(
        'In /w/app/retry.ts (lines 12-14):\n```typescript\na\nb\nc\n```\n\nwhat does this do?', p)
    end)
  end)

  describe("remote functions", function()
    local file

    before_each(function()
      vim.cmd('silent! %bwipeout!')
      file = vim.fn.tempname() .. '.lua'
      local lines = {}
      for i = 1, 20 do lines[i] = 'line ' .. i end
      vim.fn.writefile(lines, file)
    end)

    it("refuses a relative path", function()
      assert.has_error(function() init.remote_open('src/a.lua', 1) end)
    end)

    it("opens the file at the first line and highlights the range", function()
      init.remote_open(file, 5, 8)
      assert.equals(vim.uv.fs_realpath(file), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
      assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])
      local marks = vim.api.nvim_buf_get_extmarks(0, init._ns, 0, -1, { details = true })
      assert.equals(1, #marks)
      assert.equals(4, marks[1][2])
      assert.equals(8, marks[1][4].end_row)
    end)

    it("reports the last selection with its range", function()
      vim.cmd('edit ' .. vim.fn.fnameescape(file))
      vim.api.nvim_buf_set_mark(0, '<', 3, 0, {})
      vim.api.nvim_buf_set_mark(0, '>', 4, 0, {})
      local ctx = init.remote_get_context()
      assert.same({ start_line = 3, end_line = 4, text = 'line 3\nline 4' }, ctx.selection)
      assert.equals(vim.api.nvim_buf_get_name(0), ctx.current_file)
    end)

    it("has no selection when nothing was selected", function()
      vim.cmd('edit ' .. vim.fn.fnameescape(file))
      assert.is_nil(init.remote_get_context().selection)
    end)

    it("lists only file buffers", function()
      vim.cmd('edit ' .. vim.fn.fnameescape(file))
      local scratch = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(scratch, 'scratch')
      local ctx = init.remote_get_context()
      assert.same({ vim.api.nvim_buf_get_name(0) }, ctx.open_files)
    end)

    it("reports its cwd and pane", function()
      local saved = vim.env.HERDR_PANE_ID
      vim.env.HERDR_PANE_ID = 'w1:p2'
      local id = init.remote_identity()
      vim.env.HERDR_PANE_ID = saved
      assert.same({ cwd = vim.fn.getcwd(), pane = 'w1:p2' }, id)
    end)
  end)
end)
