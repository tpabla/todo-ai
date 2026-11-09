-- The `todo-ai` command agents run to drive the editor. Runs under `nvim -l`,
-- so it talks to the target editor over msgpack-rpc with no shell quoting.
--
-- Editor resolution, first step yielding exactly one live editor wins:
--   1. attached  /tmp/todo-ai/agents/<agent pane> names a socket
--   2. same tab  an editor whose pane shares the agent's tab/window
--   3. cwd       nearest by ancestry: exact > parent > child
--   4. otherwise error listing the candidates
-- An agent inside herdr/tmux only ever sees editors in its own
-- workspace/session; one outside sees every editor.

local M = {}

M.ATTACH_DIR = '/tmp/todo-ai/agents'
M.PROBE_TIMEOUT_MS = 1000

M.USAGE = [=[
usage: todo-ai <command>
  context                 current file, cursor, last selection, buffers, diagnostics
  open <path>[:a[-b]]     show a file, optionally highlighting lines a..b
  diff                    open the diff review
  reload                  re-read changed buffers from disk
  slides <deck.md>        show a deck above the code, each slide with its code
  which                   print the chosen editor and why
options:
  --editor <socket>       skip resolution and use this editor]=]

-- Symlinks resolved so tmux's /var/... matches nvim's /private/var/... on darwin.
local function normalize(path)
    return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function depth(path)
    return select(2, path:gsub('/[^/]', ''))
end

local function is_ancestor(dir, path)
    return dir == '/' or vim.startswith(path, dir .. '/')
end

-- Lower is nearer; nil when unrelated.
local function distance(editor_cwd, cwd)
    if editor_cwd == cwd then return 0 end
    local gap = math.abs(depth(cwd) - depth(editor_cwd))
    if is_ancestor(editor_cwd, cwd) then return 1000 + gap end
    if is_ancestor(cwd, editor_cwd) then return 2000 + gap end
end

local function by_cwd(editors, cwd)
    cwd = normalize(cwd)
    local best, ties = nil, {}
    for _, e in ipairs(editors) do
        local d = distance(normalize(e.cwd), cwd)
        if d and (not best or d < best) then
            best, ties = d, { e }
        elseif d and d == best then
            table.insert(ties, e)
        end
    end

    if #ties == 1 then return { socket = ties[1].socket, how = 'cwd' } end
    if #ties == 0 then return nil, 'todo-ai: no editor related to ' .. cwd end

    local lines = { string.format('todo-ai: %d editors match %s:', #ties, cwd) }
    for _, e in ipairs(ties) do
        table.insert(lines, string.format('  %s  %s', e.socket, e.cwd))
    end
    table.insert(lines, 'run :TodoAI in the editor you want, or pass --editor <socket>')
    return nil, table.concat(lines, '\n')
end

-- deps: everything with a side effect, injectable for tests.
--   self_pane()          -> agent pane id or nil
--   cwd()                -> agent cwd
--   read_attachment(id)  -> socket or nil
--   sockets()            -> list of running nvim socket paths
--   identity(sock)       -> { cwd, pane } or nil when the socket is dead
--   location(pane)       -> { tab, workspace } or nil
--   call(sock, fn, args) -> result of require('todo-ai')[fn](unpack(args))
--   print(s), eprint(s)
-- Returns { socket, how } or nil, err.
function M.resolve(deps)
    local me = deps.self_pane()
    if me then
        local sock = deps.read_attachment(me)
        if sock and deps.identity(sock) then
            return { socket = sock, how = 'attached' }
        end
    end

    local editors = {}
    for _, sock in ipairs(deps.sockets()) do
        local id = deps.identity(sock)
        if id then
            table.insert(editors, { socket = sock, cwd = id.cwd, pane = id.pane })
        end
    end
    if #editors == 0 then return nil, 'todo-ai: no editor running' end

    local here = me and deps.location(me)
    if here then
        local in_workspace, in_tab = {}, {}
        for _, e in ipairs(editors) do
            local at = e.pane and deps.location(e.pane)
            if at and at.workspace == here.workspace then
                table.insert(in_workspace, e)
                if at.tab == here.tab then table.insert(in_tab, e) end
            end
        end
        if #in_tab == 1 then
            return { socket = in_tab[1].socket, how = 'same tab' }
        end
        editors = #in_tab > 1 and in_tab or in_workspace
    end

    return by_cwd(editors, deps.cwd())
end

-- Absolute path and line range from "path[:a[-b]]", resolved against cwd: the
-- editor may sit in another directory, so it refuses relative paths.
-- Returns { path, first, last } or nil, err.
function M.parse_location(arg, cwd)
    local path, first, last = arg:match('^(.-):(%d+)%-(%d+)$')
    if not path then
        path, first = arg:match('^(.-):(%d+)$')
        last = first
    end
    path = path or arg
    first, last = tonumber(first), tonumber(last)
    if first and last < first then
        return nil, 'todo-ai: invalid range in ' .. arg
    end

    if path:sub(1, 1) ~= '/' then
        path = vim.fs.joinpath(cwd, path)
    end
    return { path = vim.fs.normalize(path), first = first, last = last }
end

local commands = {
    context = function(deps, sock)
        deps.print(vim.json.encode(deps.call(sock, 'remote_get_context', {})))
    end,
    open = function(deps, sock, arg)
        local loc, err = M.parse_location(arg, deps.cwd())
        if not loc then error(err, 0) end
        deps.call(sock, 'remote_open', { loc.path, loc.first, loc.last })
        deps.print('opened ' .. loc.path)
    end,
    -- Code paths resolved here, against the agent's cwd, like open's.
    slides = function(deps, sock, arg)
        error('not implemented')
    end,
    diff = function(deps, sock)
        deps.call(sock, 'remote_diff_review', {})
    end,
    reload = function(deps, sock)
        deps.call(sock, 'remote_reload', {})
    end,
}

-- Returns an exit code: 0 ok, 1 failed, 2 usage.
function M.run(argv, deps)
    local args, socket = {}, nil
    local i = 1
    while i <= #argv do
        if argv[i] == '--editor' then
            socket = argv[i + 1]
            i = i + 2
        else
            table.insert(args, argv[i])
            i = i + 1
        end
    end

    local command = args[1]
    if not (commands[command] or command == 'which') or ((command == 'open' or command == 'slides') and not args[2]) then
        deps.eprint(M.USAGE)
        return 2
    end

    local editor, err
    if socket then
        editor = { socket = socket, how = '--editor' }
    else
        editor, err = M.resolve(deps)
    end
    if not editor then
        deps.eprint(err)
        return 1
    end

    if command == 'which' then
        deps.print(string.format('%s  (%s)', editor.socket, editor.how))
        return 0
    end

    local ok, failure = pcall(commands[command], deps, editor.socket, args[2])
    if not ok then
        deps.eprint(tostring(failure))
        return 1
    end
    return 0
end

local function rpc(sock, fn, args)
    local ch = vim.fn.sockconnect('pipe', sock, { rpc = true })
    local ok, result = pcall(vim.rpcrequest, ch, 'nvim_exec_lua',
        'local fn = ...; return require("todo-ai")[fn](select(2, ...))',
        { fn, unpack(args) })
    vim.fn.chanclose(ch)
    if not ok then error(result, 0) end
    return result
end

-- Default per-instance sockets: <run>/nvim.<pid>.0 on linux and
-- <tmp>/nvim.<user>/<random>/nvim.<pid>.0 on darwin.
local function list_sockets()
    local run = vim.fn.stdpath('run')
    local found = vim.fn.glob(run .. '/nvim.*.0', false, true)
    vim.list_extend(found, vim.fn.glob(vim.fs.dirname(run) .. '/*/nvim.*.0', false, true))
    return vim.tbl_filter(function(s) return s ~= vim.v.servername end, found)
end

function M.default_deps()
    local ok, backend = pcall(require('todo-ai')._backend)
    if not ok then backend = nil end

    return {
        self_pane = function() return backend and backend.self_pane() end,
        cwd = function() return vim.uv.cwd() end,
        read_attachment = function(id)
            local f = io.open(M.ATTACH_DIR .. '/' .. id, 'r')
            if not f then return nil end
            local sock = vim.trim(f:read('*a'))
            f:close()
            return sock ~= '' and sock or nil
        end,
        sockets = list_sockets,
        -- Probed from a child process with a deadline: rpcrequest cannot be
        -- interrupted, and one editor stuck at a prompt would hang every call.
        identity = function(sock)
            local r = vim.system({ 'nvim', '--server', sock, '--remote-expr',
                [[luaeval("vim.json.encode(require('todo-ai').remote_identity())")]] },
                { text = true }):wait(M.PROBE_TIMEOUT_MS)
            if r.code ~= 0 then return nil end
            local ok, id = pcall(vim.json.decode, r.stdout)
            return ok and id or nil
        end,
        location = function(pane) return backend and backend.location(pane) end,
        call = rpc,
        print = function(s) io.stdout:write(s, '\n') end,
        eprint = function(s) io.stderr:write(s, '\n') end,
    }
end

return M
