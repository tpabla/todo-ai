local M = {}

local config = require('todo-ai.config')
local harness = require('todo-ai.harness')
local paths = require('todo-ai.paths')
local registry = require('todo-ai.registry')

M.state = {
    tmux_pane = nil,
    attached = nil, -- pane the user explicitly connected to
}

local severity_map = {
    [1] = 'ERROR', [2] = 'WARN', [3] = 'INFO', [4] = 'HINT',
}

local function notify(msg, level)
    vim.notify('[todo-ai] ' .. msg, level or vim.log.levels.INFO)
end

-- Directory this nvim publishes itself into. Replaces the old
-- sha256(cwd) state dir, which could not pair an agent above nvim in the tree.
function M._session_dir()
    return registry.session_dir()
end

function M._publish()
    return registry.publish({
        socket = vim.v.servername,
        cwd = paths.normalize(vim.fn.getcwd()),
        pid = vim.fn.getpid(),
        name = config.get('session_name'),
    })
end

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

    -- Publish so an agent anywhere in the tree can find this editor, and drop
    -- entries left behind by editors that died without running VimLeavePre.
    pcall(registry.list_editors)
    M._publish()

    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function() registry.unpublish() end,
    })

    vim.defer_fn(function() M._check_install() end, 100)
end

-- Tmux pane management --------------------------------------------------------

function M._in_tmux()
    return os.getenv('TMUX') ~= nil
end

function M._read_file(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    local trimmed = content and vim.trim(content) or nil
    return (trimmed and trimmed ~= '') and trimmed or nil
end

function M._require_tmux()
    if not M._in_tmux() then
        error('todo-ai requires tmux. Start Neovim inside a tmux session.')
    end
end

function M._clear_pane()
    M.state.tmux_pane = nil
    M.state.attached = nil
    os.remove(M._session_dir() .. '/prompt.md')
    os.remove(M._session_dir() .. '/prompt.md.tmp')
end

-- The attached pane id, but only while it is still a live agent pane. A pane
-- can close, or its agent can exit leaving a shell behind, between choosing it
-- and using it -- and send_keys into a shell would type the prompt at a prompt.
-- Derived from current state on every call rather than remembered.
function M.attached_pane(overrides)
    local pane_id = M.state.attached
    if not pane_id then return nil end

    for _, pane in ipairs(M._deps(overrides).candidates()) do
        if pane.id == pane_id then
            M.state.tmux_pane = pane_id
            return pane_id
        end
    end

    M._clear_pane()
    return nil
end

function M._is_pane_alive()
    return M.attached_pane() ~= nil
end

function M._plugin_root()
    local source = debug.getinfo(1, 'S').source:sub(2)
    return vim.fn.fnamemodify(source, ':h:h:h')
end

function M._extension_path()
    return M._plugin_root() .. '/extension/neovim.ts'
end

-- Install state ---------------------------------------------------------------

function M.install()
    return harness.current().install(notify)
end

function M._check_install()
    local ok, hint = harness.current().installed()
    if not ok and hint then
        notify(hint, vim.log.levels.WARN)
    end
end

-- Command construction --------------------------------------------------------

function M._build_cmd(initial_prompt, session_mode, session_id)
    return harness.current().build_cmd({
        plugin_root = M._plugin_root(),
        extension_path = M._extension_path(),
        initial_prompt = initial_prompt,
        session_mode = session_mode,
        session_id = session_id,
    })
end

-- Prompt delivery -------------------------------------------------------------

function M._write_prompt(text)
    local dir = M._session_dir()
    vim.fn.mkdir(dir, 'p')
    local target = dir .. '/prompt.md'
    local staging = target .. '.tmp'
    local f = io.open(staging, 'w')
    if not f then error('Failed to write ' .. staging) end
    f:write(text)
    f:close()
    os.rename(staging, target)
end

function M._send_keys(pane_id, text)
    pane_id = pane_id or M.state.tmux_pane
    if not pane_id then return end
    -- '-l' sends the text literally so special chars are not interpreted
    vim.fn.system({ 'tmux', 'send-keys', '-t', pane_id, '-l', text })
    vim.fn.system({ 'tmux', 'send-keys', '-t', pane_id, 'Enter' })
end

-- Single delivery path for every harness; the mechanism comes from the spec.
function M._deliver(text, pane_id, overrides)
    if not text then return end
    local deps = M._deps(overrides)
    return harness.deliver_prompt(harness.current(), pane_id or M.state.tmux_pane, text, {
        send_keys = deps.send_keys,
        write_prompt = deps.write_prompt,
    })
end

-- Attach / spawn --------------------------------------------------------------

function M._join_pane(pane_id, initial_prompt)
    M.state.tmux_pane = pane_id
    M.state.attached = pane_id
    M._publish()
    M._deliver(initial_prompt, pane_id)
    vim.fn.system({ 'tmux', 'select-pane', '-t', pane_id })
    return pane_id
end

function M._spawn_agent(initial_prompt, session_mode, session_id)
    local dir = M._publish()
    local spec = harness.current()

    if vim.fn.executable(spec.bin) ~= 1 then
        error(string.format('todo-ai: %s not found on PATH', spec.bin))
    end

    local parts = {
        'env',
        'NVIM=' .. vim.v.servername,
        'TODO_AI_SESSION_DIR=' .. dir,
        'TODO_AI_SOCKET=' .. vim.v.servername,
        'TODO_AI_TAG=' .. config.get('tag'),
    }
    local name = config.get('session_name')
    if name then table.insert(parts, 'TODO_AI_NAME=' .. name) end

    vim.list_extend(parts, M._build_cmd(initial_prompt, session_mode, session_id))
    local shell_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, parts), ' ')

    local result = vim.trim(vim.fn.system({
        'tmux', 'split-window', '-h', '-l', tostring(config.get('pane_width')),
        '-P', '-F', '#{pane_id}',
        shell_cmd,
    }))
    if vim.v.shell_error ~= 0 or not result:match('^%%') then
        error('todo-ai: failed to create tmux pane: ' .. result)
    end

    M.state.tmux_pane = result
    M.state.attached = result
    return result
end

-- Picker ----------------------------------------------------------------------

-- A pane title only helps when the agent set it. tmux defaults it to the
-- hostname, and it sometimes just echoes the running command.
function M._session_title(pane)
    local title = pane.title
    if not title or title == '' then return nil end
    if title == vim.fn.hostname() then return nil end
    if pane.command and title == pane.command then return nil end
    -- Strip the agent's own marker; the agent column already says who it is.
    title = title:gsub('^%s*✳%s*', '')
    title = vim.trim(title)
    return (title ~= '') and title or nil
end

function M._describe_pane(pane)
    local bits = { pane.agent or 'agent' }

    local title = M._session_title(pane)
    if title then table.insert(bits, title) end

    table.insert(bits, pane.dir and vim.fn.fnamemodify(pane.dir, ':~') or '?')

    if pane.name then table.insert(bits, '[' .. pane.name .. ']') end
    if pane.rank and pane.rank ~= 'exact' then
        table.insert(bits, '(' .. pane.rank .. ')')
    end
    if not pane.tagged then table.insert(bits, '(untagged)') end

    return string.format('%s  %s', pane.id, table.concat(bits, '  '))
end

M.NEW_SESSION = 'New session'

-- deps is injectable so the flow is testable without tmux.
function M._deps(overrides)
    return vim.tbl_extend('force', {
        candidates = function() return registry.candidates(paths.normalize(vim.fn.getcwd())) end,
        spawn = function(prompt) return M._spawn_agent(prompt, nil) end,
        join = function(pane_id, prompt) return M._join_pane(pane_id, prompt) end,
        select = function(items, opts, cb) vim.ui.select(items, opts, cb) end,
        send_keys = function(pane, text) M._send_keys(pane, text) end,
        write_prompt = function(text) M._write_prompt(text) end,
    }, overrides or {})
end

-- :TodoAI — spawn when there is nothing to attach to, otherwise always ask.
-- It never silently picks a pane for you.
function M.open_agent_interactive(initial_prompt, overrides)
    M._require_tmux()
    local deps = M._deps(overrides)

    local panes = deps.candidates()
    if #panes == 0 then
        return deps.spawn(initial_prompt)
    end

    local items = vim.list_extend(vim.deepcopy(panes), { M.NEW_SESSION })
    deps.select(items, {
        prompt = 'todo-ai: connect to',
        format_item = function(item)
            if item == M.NEW_SESSION then return M.NEW_SESSION end
            return M._describe_pane(item)
        end,
    }, function(choice)
        if not choice then return end
        if choice == M.NEW_SESSION then
            deps.spawn(initial_prompt)
        else
            deps.join(choice.id, initial_prompt)
        end
    end)
end

-- Attach to an already-chosen pane, or ask. Used by everything that needs a
-- live agent (prompts, scan, focus).
function M.open_agent(initial_prompt, overrides)
    M._require_tmux()

    local pane_id = M.attached_pane(overrides)
    if pane_id then
        M._deliver(initial_prompt, pane_id, overrides)
        vim.fn.system({ 'tmux', 'select-pane', '-t', pane_id })
        return pane_id
    end

    return M.open_agent_interactive(initial_prompt, overrides)
end

-- :TodoAIConnect [name|%pane|session-id] — explicit attach. With no argument
-- it shows the picker; with one it matches a pane by name, id, or session.
function M.connect(target, overrides)
    M._require_tmux()
    local deps = M._deps(overrides)

    if not target or target == '' then
        return M.open_agent_interactive(nil, overrides)
    end

    for _, pane in ipairs(deps.candidates()) do
        if pane.id == target or pane.name == target or pane.session == target
                or (pane.session and vim.startswith(pane.session, target)) then
            notify('connected to ' .. M._describe_pane(pane))
            return deps.join(pane.id, nil)
        end
    end

    notify(string.format('no agent pane matching %q', target), vim.log.levels.WARN)
end

function M.disconnect()
    local was = M.state.attached
    M.state.tmux_pane = nil
    M.state.attached = nil
    notify(was and ('detached from ' .. was) or 'not attached')
end

function M.open_agent_new(initial_prompt)
    M._require_tmux()
    return M._spawn_agent(initial_prompt, 'new')
end

-- Resume a specific past session in a new pane.
function M.resume_session(session_id, initial_prompt)
    M._require_tmux()
    if not session_id or session_id == '' then
        error('todo-ai: a session id is required')
    end
    return M._spawn_agent(initial_prompt, nil, session_id)
end

function M.send_prompt(text, overrides)
    local pane_id = M.attached_pane(overrides)
    if pane_id then
        return M._deliver(text, pane_id, overrides)
    end
    return M.open_agent(text, overrides)
end

function M.scan(overrides)
    return M.send_prompt(harness.current().scan_prompt, overrides)
end

function M.focus_agent(overrides)
    local pane_id = M.attached_pane(overrides)
    if pane_id then
        return vim.fn.system({ 'tmux', 'select-pane', '-t', pane_id })
    end
    return M.open_agent(nil, overrides)
end

-- Remote functions (called by the agent via nvim --server) --------------------

-- Paths arrive absolute: the agent may sit above this nvim in the tree, so
-- resolving a relative path against our cwd would silently open the wrong file.
function M.remote_open(path, line)
    local p = paths.normalize(path)
    if not p or p:sub(1, 1) ~= '/' then
        error(string.format(
            'todo-ai: path must be absolute, got %q — the agent must resolve it ' ..
            'against its own cwd before sending', tostring(path)))
    end

    vim.schedule(function()
        vim.cmd('edit +' .. (line or 1) .. ' ' .. vim.fn.fnameescape(p))
    end)
end

function M.remote_diff_review()
    vim.schedule(function()
        vim.cmd('DiffviewOpen')
    end)
end

function M.remote_get_context()
    local ctx = { open_files = {}, cwd = paths.normalize(vim.fn.getcwd()) }

    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= '' and vim.bo[buf].buftype == '' then
        ctx.current_file = name
        ctx.cursor_line = vim.api.nvim_win_get_cursor(win)[1]
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

    return vim.fn.json_encode(ctx)
end

-- Backward-compatible aliases
M.open_pi = M.open_agent
M.focus_pi = M.focus_agent

return M
