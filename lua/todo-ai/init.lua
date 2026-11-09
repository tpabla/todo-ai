local M = {}

local config = require('todo-ai.config')
local cli = require('todo-ai.cli')

M.state = {
    agent = nil, -- { id, kind, cwd, title } of the agent this editor talks to
    reload_timer = nil,
}

M._ns = vim.api.nvim_create_namespace('todo-ai')

local severity_map = {
    [1] = 'ERROR', [2] = 'WARN', [3] = 'INFO', [4] = 'HINT',
}

function M.setup(opts)
    config.setup(opts or {})

    vim.o.autoread = true
    local group = vim.api.nvim_create_augroup('TodoAI', { clear = true })
    vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
        group = group,
        callback = function() vim.cmd('silent! checktime') end,
    })

    -- Highlight AGENT: (or custom tag) comments
    local tag = config.get('tag')
    vim.api.nvim_set_hl(0, 'TodoAI', { fg = '#ff79c6', bold = true })
    local hl_pattern = [[\C\<]] .. tag .. [[:.\+]]
    vim.api.nvim_create_autocmd({ 'BufWinEnter', 'FileType' }, {
        group = group,
        callback = function()
            if vim.bo.buftype ~= '' then return end
            for _, m in ipairs(vim.fn.getmatches()) do
                if m.group == 'TodoAI' then return end
            end
            vim.fn.matchadd('TodoAI', hl_pattern, 10)
        end,
    })

    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function() M._detach() end,
    })
end

-- Backend + side effects ------------------------------------------------------

-- herdr wins when both are present: herdr panes can run inside tmux.
function M._backend(getenv)
    getenv = getenv or os.getenv
    if getenv('HERDR_ENV') == '1' then return require('todo-ai.herdr') end
    if getenv('TMUX') then return require('todo-ai.tmux') end
    error('todo-ai: run Neovim inside herdr or tmux', 0)
end

-- deps is injectable so the flows are testable without herdr or tmux.
function M._deps(overrides)
    local deps = vim.tbl_extend('force', {
        attach_dir = cli.ATTACH_DIR,
        socket = function() return vim.v.servername end,
        cwd = vim.fn.getcwd,
        select = vim.ui.select,
    }, overrides or {})
    deps.backend = deps.backend or M._backend()
    return deps
end

-- Attachment ------------------------------------------------------------------

local function start_reload()
    if M.state.reload_timer then return end
    M.state.reload_timer = vim.uv.new_timer()
    local every = config.get('reload_interval_ms')
    M.state.reload_timer:start(every, every, vim.schedule_wrap(function()
        vim.cmd('silent! checktime')
    end))
end

local function stop_reload()
    if not M.state.reload_timer then return end
    M.state.reload_timer:close()
    M.state.reload_timer = nil
end

-- Records this editor's socket under the agent's pane id so the agent's
-- `todo-ai` resolves to exactly this editor.
function M._attach(agent, deps)
    deps = M._deps(deps)
    if M.state.agent and M.state.agent.id ~= agent.id then M._detach(deps) end

    vim.fn.mkdir(deps.attach_dir, 'p')
    local f = assert(io.open(deps.attach_dir .. '/' .. agent.id, 'w'))
    f:write(deps.socket())
    f:close()

    M.state.agent = agent
    start_reload()
    return agent
end

-- Needs no backend: it runs on exit, wherever nvim is.
function M._detach(deps)
    local agent = M.state.agent
    M.state.agent = nil
    stop_reload()
    if not agent then return end

    local dir = deps and deps.attach_dir or cli.ATTACH_DIR
    local socket = deps and deps.socket and deps.socket() or vim.v.servername
    local path = dir .. '/' .. agent.id
    local f = io.open(path, 'r')
    if not f then return end
    local owner = f:read('*a')
    f:close()
    -- Another editor may have attached to this agent since
    if owner == socket then os.remove(path) end
end

-- The attached agent, only while it is still alive.
function M.attached(deps)
    deps = M._deps(deps)
    local agent = M.state.agent
    if not agent then return nil end

    for _, a in ipairs(deps.backend.list()) do
        if a.id == agent.id then return a end
    end
    M._detach(deps)
    return nil
end

function M._describe(agent)
    local bits = { agent.id, agent.kind or 'agent' }
    if agent.title and agent.title ~= '' then table.insert(bits, agent.title) end
    if agent.cwd then table.insert(bits, vim.fn.fnamemodify(agent.cwd, ':~')) end
    if agent.name then table.insert(bits, '[' .. agent.name .. ']') end
    return table.concat(bits, '  ')
end

-- Commands --------------------------------------------------------------------

M.NEW_AGENT = 'New agent'

-- :TodoAI — spawns when the workspace has no agents, otherwise always asks
-- (offering a new one too), never silently picks. on_attached(agent) runs
-- once an agent is attached.
function M.pick(overrides, on_attached)
    local deps = M._deps(overrides)
    on_attached = on_attached or function(a)
        vim.notify('[todo-ai] attached to ' .. M._describe(a))
    end
    local function attach(a) on_attached(M._attach(a, deps)) end

    local agents = deps.backend.list()
    if #agents == 0 then
        return attach(M._spawn(deps))
    end

    local items = vim.list_extend(vim.deepcopy(agents), { M.NEW_AGENT })
    deps.select(items, {
        prompt = 'todo-ai: connect to',
        format_item = function(item)
            if item == M.NEW_AGENT then return M.NEW_AGENT end
            return M._describe(item)
        end,
    }, function(choice)
        if not choice then return end
        attach(choice == M.NEW_AGENT and M._spawn(deps) or choice)
    end)
end

-- :TodoAISend [text] — picks first when nothing is attached.
function M.send(text, overrides)
    if not text or text == '' then return end
    local deps = M._deps(overrides)
    local function deliver(a) deps.backend.prompt(a.id, text) end

    local agent = M.attached(deps)
    if agent then return deliver(agent) end
    M.pick(deps, deliver)
end

function M._spawn(deps)
    return deps.backend.spawn({
        kind = config.get('agent'),
        cwd = deps.cwd(),
        direction = config.get('split'),
    })
end

function M.scan(overrides)
    local tag = config.get('tag')
    return M.send(string.format(
        'Find every %s: comment in this project and resolve it, removing each comment once done.',
        tag), overrides)
end

function M.focus(overrides)
    local deps = M._deps(overrides)
    local function focus(a) deps.backend.focus(a.id) end

    local agent = M.attached(deps)
    if agent then return focus(agent) end
    M.pick(deps, focus)
end

-- Prompt text for a selection plus the user's question.
function M._selection_prompt(sel, question)
    return string.format('In %s (lines %d-%d):\n```%s\n%s\n```\n\n%s',
        sel.file, sel.start_line, sel.end_line, sel.filetype or '', sel.text, question)
end

-- Remote functions (called by `todo-ai` over rpc) -----------------------------

-- { cwd, pane }: lets `todo-ai` place this editor in a tab and workspace.
function M.remote_identity()
    return {
        cwd = vim.fn.getcwd(),
        pane = os.getenv('HERDR_PANE_ID') or os.getenv('TMUX_PANE'),
    }
end

-- Paths arrive absolute: the agent may sit in another directory, so resolving
-- a relative path against our cwd would silently open the wrong file.
function M.remote_open(path, first, last)
    if type(path) ~= 'string' or path:sub(1, 1) ~= '/' then
        error(string.format(
            'todo-ai: path must be absolute, got %q — resolve it against the ' ..
            "agent's cwd before sending", tostring(path)))
    end

    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_clear_namespace(buf, M._ns, 0, -1)
    end
    if not first then return end

    local count = vim.api.nvim_buf_line_count(0)
    first = math.min(first, count)
    last = math.min(last or first, count)
    vim.api.nvim_win_set_cursor(0, { first, 0 })
    vim.api.nvim_buf_set_extmark(0, M._ns, first - 1, 0, {
        end_row = last,
        hl_group = 'Visual',
        hl_eol = true,
    })
    vim.cmd('normal! zz')
end

function M.remote_slides(slides)
    error('not implemented')
end

function M.remote_diff_review()
    vim.schedule(function()
        vim.cmd('DiffviewOpen')
    end)
end

function M.remote_reload()
    vim.cmd('silent! checktime')
end

-- Includes the last visual selection of the current buffer, with its range so
-- the agent can judge whether it is still what the user means.
function M.remote_get_context()
    local ctx = { cwd = vim.fn.getcwd(), open_files = {} }

    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= '' and vim.bo[buf].buftype == '' then
        ctx.current_file = name
        ctx.cursor_line = vim.api.nvim_win_get_cursor(win)[1]

        local first = vim.api.nvim_buf_get_mark(buf, '<')[1]
        local last = vim.api.nvim_buf_get_mark(buf, '>')[1]
        if first > 0 and last >= first then
            ctx.selection = {
                start_line = first,
                end_line = last,
                text = table.concat(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), '\n'),
            }
        end

        local diags = vim.diagnostic.get(buf)
        if #diags > 0 then
            ctx.diagnostics = {}
            for i, d in ipairs(diags) do
                if i > 20 then break end
                table.insert(ctx.diagnostics, {
                    line = d.lnum + 1,
                    severity = severity_map[d.severity] or 'UNKNOWN',
                    message = d.message,
                })
            end
        end
    end

    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '' then
            local n = vim.api.nvim_buf_get_name(b)
            if n ~= '' then
                table.insert(ctx.open_files, n)
            end
        end
    end

    return ctx
end

return M
