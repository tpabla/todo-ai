-- tmux backend. Deliberately minimal: an agent is a pane whose foreground
-- command is in config.agent_commands, nothing more.
--
-- An agent is { id, kind, cwd, title }; id is a tmux pane id (%12).

local M = {}

local function default_run(argv)
    local r = vim.system(argv, { text = true }):wait()
    if r.code ~= 0 then
        error(string.format('todo-ai: %s failed: %s', table.concat(argv, ' ', 1, 2),
            vim.trim(r.stderr)), 0)
    end
    return r.stdout
end

function M.available()
    return os.getenv('TMUX') ~= nil
end

function M.self_pane()
    return os.getenv('TMUX_PANE')
end

-- run(argv) -> stdout string, errors on non-zero exit.
-- Agents in the editor's current session.
function M.list(run)
    local out = (run or default_run)({ 'tmux', 'list-panes', '-s', '-t', M.self_pane(),
        '-F', '#{pane_id}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_title}' })
    local commands = require('todo-ai.config').get('agent_commands')

    local agents = {}
    for line in out:gmatch('[^\n]+') do
        local id, cmd, cwd, title = unpack(vim.split(line, '\t', { plain = true }))
        if vim.tbl_contains(commands, cmd) then
            table.insert(agents, { id = id, kind = cmd, cwd = cwd, title = title })
        end
    end
    return agents
end

-- Splits the editor's window and runs `kind` in the new pane.
-- opts: { kind, cwd, direction }. Returns the new agent.
function M.spawn(opts, run)
    local id = vim.trim((run or default_run)({ 'tmux', 'split-window',
        opts.direction == 'down' and '-v' or '-h', '-t', M.self_pane(), '-c', opts.cwd,
        '-P', '-F', '#{pane_id}', opts.kind }))
    return { id = id, kind = opts.kind, cwd = opts.cwd }
end

function M.prompt(id, text, run)
    run = run or default_run
    -- -l sends the text literally so special chars are not interpreted
    run({ 'tmux', 'send-keys', '-t', id, '-l', text })
    run({ 'tmux', 'send-keys', '-t', id, 'Enter' })
end

function M.focus(id, run)
    run = run or default_run
    run({ 'tmux', 'select-window', '-t', id })
    run({ 'tmux', 'select-pane', '-t', id })
end

-- { tab = window, workspace = session } of a pane. nil if gone.
function M.location(pane_id, run)
    local ok, out = pcall(run or default_run,
        { 'tmux', 'display-message', '-p', '-t', pane_id, '#{session_id}\t#{window_id}' })
    -- display-message exits 0 for a dead pane, printing empty fields
    if not ok then return nil end
    local session, window = unpack(vim.split(vim.trim(out), '\t', { plain = true }))
    if not session or session == '' then return nil end
    return { tab = window, workspace = session }
end

return M
