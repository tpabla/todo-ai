-- herdr backend. Every call goes through the herdr CLI, which talks to the
-- session the calling pane belongs to.
--
-- An agent is { id, kind, cwd, title, name }; id is a herdr pane id (w1:p2).

local M = {}

local function default_run(argv)
    local r = vim.system(argv, { text = true }):wait()
    if r.code ~= 0 then
        error(string.format('todo-ai: %s failed: %s', table.concat(argv, ' ', 1, 3),
            vim.trim(r.stderr ~= '' and r.stderr or r.stdout)), 0)
    end
    return r.stdout
end

local function call(run, ...)
    return vim.json.decode((run or default_run)({ 'herdr', ... })).result
end

local function to_agent(a)
    return {
        id = a.pane_id,
        kind = a.agent,
        cwd = a.cwd,
        title = a.terminal_title_stripped,
        name = a.name,
    }
end

function M.available()
    return os.getenv('HERDR_ENV') == '1'
end

function M.self_pane()
    return os.getenv('HERDR_PANE_ID')
end

-- run is injectable so parsing is testable without a herdr session.
-- run(argv) -> stdout string, errors on non-zero exit.
-- Agents in the editor's current workspace, read live: env ids go stale
-- when a pane moves.
function M.list(run)
    local workspace = call(run, 'pane', 'current', '--current').pane.workspace_id
    local agents = {}
    for _, a in ipairs(call(run, 'agent', 'list').agents) do
        if a.workspace_id == workspace then
            table.insert(agents, to_agent(a))
        end
    end
    return agents
end

-- Names must match [a-z][a-z0-9_-]{0,31} and be unique among live agents.
local function agent_name(cwd, taken)
    local base = vim.fs.basename(cwd):lower():gsub('[^a-z0-9_-]', '-')
    if not base:match('^[a-z]') then base = 'agent-' .. base end
    base = base:sub(1, 28)

    local name, n = base, 1
    while taken[name] do
        n = n + 1
        name = base .. '-' .. n
    end
    return name
end

-- Splits the editor's pane and starts an agent of `kind` in it, named so it
-- is unique among live agents (herdr requires that).
-- opts: { kind, cwd, direction }. Returns the new agent.
function M.spawn(opts, run)
    local taken = {}
    for _, a in ipairs(call(run, 'agent', 'list').agents) do
        if a.name then taken[a.name] = true end
    end
    local name = agent_name(opts.cwd, taken)

    local pane = call(run, 'pane', 'split', '--current', '--direction', opts.direction,
        '--cwd', opts.cwd, '--no-focus').pane.pane_id
    call(run, 'agent', 'start', name, '--kind', opts.kind, '--pane', pane)

    return { id = pane, kind = opts.kind, cwd = opts.cwd, name = name }
end

function M.prompt(id, text, run)
    call(run, 'agent', 'prompt', id, text)
end

function M.focus(id, run)
    call(run, 'agent', 'focus', id)
end

-- { tab, workspace } of a pane, read live: panes can move. nil if gone.
function M.location(pane_id, run)
    local ok, result = pcall(call, run, 'pane', 'get', pane_id)
    if not ok then return nil end
    return { tab = result.pane.tab_id, workspace = result.pane.workspace_id }
end

return M
