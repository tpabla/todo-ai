-- Agent discovery. tmux and the process table are the registry: candidates are
-- derived from current state on every call and nothing is cached, so a pane
-- that closes or whose agent exits simply stops being a candidate.
--
-- Liveness comes from the process tree, never from the @todo-ai-* pane options:
-- a tag outlives the agent that wrote it. Tags carry metadata only (name,
-- session id) and act as a hint solely for an agent behind a wrapper process.
local paths = require('todo-ai.paths')

local M = {}

M.REGISTRY_DIR = '/tmp/todo-ai/sessions'

-- Written by shared/tag-pane.sh; read back for metadata.
M.PANE_OPTIONS = { '@todo-ai-agent', '@todo-ai-dir', '@todo-ai-name', '@todo-ai-session' }

M.PANE_FORMAT = table.concat({
    '#{pane_id}', '#{pane_pid}', '#{pane_current_command}', '#{pane_current_path}',
    '#{@todo-ai-agent}', '#{@todo-ai-name}', '#{@todo-ai-session}',
    -- Agents write a human-readable session name here (Claude Code sets
    -- '✳ <summary>'), which is the most useful label in the picker.
    '#{pane_title}',
}, '\t')

-- A pane that has fallen back to one of these is definitively not an agent.
M.SHELLS = {
    sh = true, bash = true, zsh = true, fish = true, dash = true,
    ksh = true, tcsh = true, csh = true, nu = true, xonsh = true,
}

-- Pure helpers ---------------------------------------------------------------

local function basename(cmd)
    if not cmd or cmd == '' then return nil end
    -- Login shells arrive as '-fish'; comm may be a full path.
    return (cmd:gsub('^%-', ''):match('([^/]+)$'))
end

local function empty_to_nil(s)
    return (s and s ~= '') and s or nil
end

function M.parse_panes(raw)
    local panes = {}
    for line in (raw or ''):gmatch('[^\n]+') do
        local f = vim.split(line, '\t', { plain = true })
        if f[1] then
            table.insert(panes, {
                id = f[1],
                pid = tonumber(f[2]),
                command = empty_to_nil(f[3]),
                dir = empty_to_nil(f[4]),
                tag = {
                    agent = empty_to_nil(f[5]),
                    name = empty_to_nil(f[6]),
                    session = empty_to_nil(f[7]),
                },
                title = empty_to_nil(f[8]),
            })
        end
    end
    return panes
end

-- `ps -eo pid,ppid,comm` -> { [pid] = { ppid, comm, name } }
function M.parse_processes(raw)
    local procs = {}
    for line in (raw or ''):gmatch('[^\n]+') do
        local pid, ppid, comm = line:match('^%s*(%d+)%s+(%d+)%s+(.+)$')
        if pid then
            procs[tonumber(pid)] = {
                ppid = tonumber(ppid),
                comm = comm,
                name = basename(comm),
            }
        end
    end
    return procs
end

local function agent_names(specs)
    local names = {}
    for _, spec in ipairs(specs or {}) do
        names[spec.bin] = spec.label or spec.name
        names[spec.process_pattern] = spec.label or spec.name
    end
    return names
end

-- Exact basename match, so `grep claude` in a pane is not mistaken for an agent.
local function descendant_agent(pid, procs, names)
    if not pid then return nil end

    local children = {}
    for child, info in pairs(procs) do
        children[info.ppid] = children[info.ppid] or {}
        table.insert(children[info.ppid], child)
    end

    local queue, seen, depth = { pid }, { [pid] = true }, 0
    while #queue > 0 and depth < 32 do
        local next_queue = {}
        for _, current in ipairs(queue) do
            local info = procs[current]
            if info and names[info.name] then return names[info.name] end
            for _, child in ipairs(children[current] or {}) do
                if not seen[child] then
                    seen[child] = true
                    table.insert(next_queue, child)
                end
            end
        end
        queue = next_queue
        depth = depth + 1
    end
    return nil
end

-- 'agent' | 'stale' | 'none', plus the agent label when active.
function M.pane_state(pane, procs, specs)
    local names = agent_names(specs)

    local foreground = basename(pane.command)
    if foreground and names[foreground] then
        return 'agent', names[foreground]
    end

    local found = descendant_agent(pane.pid, procs, names)
    if found then return 'agent', found end

    if pane.tag and pane.tag.agent then
        -- Tagged but the pane is back at a shell prompt: the agent is gone and
        -- the tag is a leftover. Anything else may be a wrapped agent.
        if foreground and M.SHELLS[foreground] then
            return 'stale', pane.tag.agent
        end
        return 'agent', pane.tag.agent
    end

    return 'none'
end

-- Splits panes into live agents (with tag metadata folded in) and stale ones.
function M.agent_panes(panes, procs, specs)
    local active, stale = {}, {}
    for _, pane in ipairs(panes) do
        local state, label = M.pane_state(pane, procs, specs)
        if state == 'agent' then
            table.insert(active, {
                id = pane.id,
                agent = label,
                dir = pane.dir,
                name = pane.tag and pane.tag.name or nil,
                session = pane.tag and pane.tag.session or nil,
                tagged = pane.tag and pane.tag.agent ~= nil or false,
                command = pane.command,
                title = pane.title,
            })
        elseif state == 'stale' then
            table.insert(stale, pane)
        end
    end
    return active, stale
end

-- Ranking --------------------------------------------------------------------

local EXACT, ANCESTOR, DESCENDANT, UNRELATED = 0, 1, 2, 3

local function rank(dir, pane_dir)
    if not dir or not pane_dir then return UNRELATED, 0 end
    local above = paths.distance(pane_dir, dir)
    if above == 0 then return EXACT, 0 end
    if above then return ANCESTOR, above end
    local below = paths.distance(dir, pane_dir)
    if below then return DESCENDANT, below end
    return UNRELATED, 0
end

-- Edges ----------------------------------------------------------------------

local function system_lines(args)
    local out = vim.fn.system(args)
    if vim.v.shell_error ~= 0 then return '' end
    return out
end

function M.untag(pane_id)
    for _, option in ipairs(M.PANE_OPTIONS) do
        vim.fn.system({ 'tmux', 'set-option', '-pu', '-t', pane_id, option })
    end
end

function M.specs()
    local harness = require('todo-ai.harness')
    return vim.tbl_map(function(name) return harness.get(name) end, harness.names())
end

-- All live agent panes, ranked nearest-first. Reads tmux and the process table
-- on every call; `opts` injects them for testing. Stale panes are untagged as a
-- side effect so every other editor stops seeing them too.
function M.candidates(dir, opts)
    opts = opts or {}

    local found = opts.panes
    if not found then
        local panes = M.parse_panes(
            opts.panes_raw or system_lines({ 'tmux', 'list-panes', '-a', '-F', M.PANE_FORMAT }))
        local procs = M.parse_processes(
            opts.ps_raw or system_lines({ 'ps', '-eo', 'pid,ppid,comm' }))

        local stale
        found, stale = M.agent_panes(panes, procs, opts.specs or M.specs())

        local untag = opts.untag or M.untag
        for _, pane in ipairs(stale) do untag(pane.id) end
    end

    local seen, ranked = {}, {}
    for i, pane in ipairs(found) do
        if not seen[pane.id] then
            seen[pane.id] = true
            local bucket, dist = rank(dir, pane.dir)
            table.insert(ranked, { pane = pane, bucket = bucket, dist = dist, order = i })
        end
    end

    table.sort(ranked, function(a, b)
        if a.bucket ~= b.bucket then return a.bucket < b.bucket end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.order < b.order
    end)

    return vim.tbl_map(function(r)
        r.pane.rank = ({ 'exact', 'parent', 'child', 'unrelated' })[r.bucket + 1]
        r.pane.distance = r.dist
        return r.pane
    end, ranked)
end

-- Editor registry ------------------------------------------------------------

local function alive(pid)
    if not pid then return false end
    local ok, res = pcall(vim.uv.kill, pid, 0)
    return ok and res == 0
end

function M.session_dir(pid)
    return M.REGISTRY_DIR .. '/' .. (pid or vim.fn.getpid())
end

function M.publish(entry)
    local dir = M.session_dir(entry.pid)
    vim.fn.mkdir(dir, 'p')
    entry.dir = dir
    vim.fn.writefile({ vim.fn.json_encode(entry) }, dir .. '/editor.json')
    return dir
end

function M.unpublish(pid)
    vim.fn.delete(M.session_dir(pid), 'rf')
end

-- Live editors, with dead ones pruned from disk.
function M.list_editors()
    local entries = {}
    for name, kind in vim.fs.dir(M.REGISTRY_DIR) do
        if kind == 'directory' then
            local dir = M.REGISTRY_DIR .. '/' .. name
            local ok, decoded = pcall(function()
                return vim.fn.json_decode(table.concat(vim.fn.readfile(dir .. '/editor.json'), '\n'))
            end)
            if ok and type(decoded) == 'table' and alive(decoded.pid) then
                table.insert(entries, decoded)
            else
                vim.fn.delete(dir, 'rf')
            end
        end
    end
    return entries
end

return M
