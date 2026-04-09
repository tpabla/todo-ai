local M = {}
local config = require('todo-ai.config')


M.state = {
    tmux_pane = nil,
}

local severity_map = {
    [1] = 'ERROR', [2] = 'WARN', [3] = 'INFO', [4] = 'HINT',
}

function M._state_dir()
    local cwd = vim.fn.getcwd()
    return '/tmp/todo-ai-' .. vim.fn.sha256(cwd):sub(1, 16)
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

    -- Write socket so extension can connect/reconnect
    local dir = M._state_dir()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ vim.v.servername }, dir .. '/nvim-socket')

    -- Remove socket on exit → extension detects disconnect (🔴)
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            os.remove(M._state_dir() .. '/nvim-socket')
        end,
    })

    -- Deferred install check so startup is never blocked.
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

function M._clear_pane()
    M.state.tmux_pane = nil
    local dir = M._state_dir()
    os.remove(dir .. '/pane-id')
    os.remove(dir .. '/prompt.md')
    os.remove(dir .. '/prompt.md.tmp')
end

function M._is_pane_alive()
    local pane_id = M.state.tmux_pane or M._read_file(M._state_dir() .. '/pane-id')
    if not pane_id then return false end

    -- list-panes is the only reliable check — display-message returns
    -- exit 0 even for non-existent panes on some tmux versions
    local panes = vim.fn.system("tmux list-panes -a -F '#{pane_id}'")
    if not panes:find(pane_id, 1, true) then
        M._clear_pane()
        return false
    end

    M.state.tmux_pane = pane_id
    return true
end

function M._plugin_root()
    local source = debug.getinfo(1, 'S').source:sub(2)
    return vim.fn.fnamemodify(source, ':h:h:h')
end

function M._extension_path()
    return M._plugin_root() .. '/extension/neovim.ts'
end

-- Install state ---------------------------------------------------------------

function M._mcp_deps_installed()
    return vim.fn.isdirectory(M._plugin_root() .. '/mcp-server/node_modules') == 1
end

function M.install()
    local root = M._plugin_root()
    local notify = function(msg, level)
        vim.notify('[todo-ai] ' .. msg, level or vim.log.levels.INFO)
    end

    -- The only install step is `npm install` for the MCP server. The Claude
    -- Code plugin itself is loaded in-place via `claude --plugin-dir <root>`
    -- (baked into the launch command), so nothing is copied to ~/.claude/.
    if M._mcp_deps_installed() then
        notify('mcp-server deps already installed')
        return true
    end
    if vim.fn.executable('npm') ~= 1 then
        notify('npm not found on PATH — cannot install mcp-server deps', vim.log.levels.ERROR)
        return false
    end
    notify('installing mcp-server deps (npm install)...')
    local out = vim.fn.system({ 'npm', '--prefix', root .. '/mcp-server', 'install', '--silent' })
    if vim.v.shell_error ~= 0 then
        notify('npm install failed:\n' .. out, vim.log.levels.ERROR)
        return false
    end
    notify('mcp-server deps installed')
    M._print_permissions_hint()
    return true
end

function M._print_permissions_hint()
    vim.notify(
        '[todo-ai] To skip permission prompts for the Neovim MCP tools, add this\n' ..
        'to ~/.claude/settings.json (one-time, optional):\n\n' ..
        '  {\n' ..
        '    "permissions": {\n' ..
        '      "allow": ["mcp__plugin_todo-ai-nvim_neovim__*"]\n' ..
        '    }\n' ..
        '  }',
        vim.log.levels.INFO
    )
end

function M._check_install()
    -- Only relevant for the claude_code harness.
    if config.get('harness') ~= config.HARNESS_CLAUDE_CODE then return end
    if not M._mcp_deps_installed() then
        vim.notify(
            '[todo-ai] mcp-server deps not installed. Run :TodoAIInstall.',
            vim.log.levels.WARN
        )
    end
end

function M._build_cmd(initial_prompt)
    local harness = config.get('harness')

    if harness == config.HARNESS_PI then
        local cmd = { 'pi', '-e', M._extension_path(), '--resume' }
        for _, arg in ipairs(config.get('pi_extra_args') or {}) do
            table.insert(cmd, arg)
        end
        if initial_prompt then
            table.insert(cmd, initial_prompt)
        end
        return cmd
    elseif harness == config.HARNESS_CLAUDE_CODE then
        -- --plugin-dir loads the bundled Claude Code plugin (MCP server,
        -- hooks, /scan skill, workflow rules) in-place from the lazy.nvim
        -- clone, so no copy lands under ~/.claude/.
        local cmd = { 'claude', '--plugin-dir', M._plugin_root() }
        local model = config.get('claude_model')
        if model then
            table.insert(cmd, '--model')
            table.insert(cmd, model)
        end
        for _, arg in ipairs(config.get('claude_extra_args') or {}) do
            table.insert(cmd, arg)
        end
        if initial_prompt then
            table.insert(cmd, initial_prompt)
        end
        return cmd
    end

    error('todo-ai: unknown harness: ' .. tostring(harness))
end

function M._write_prompt(text)
    local dir = M._state_dir()
    local tmpfile = dir .. '/prompt.md'
    local staging = tmpfile .. '.tmp'
    local f = io.open(staging, 'w')
    if not f then error('Failed to write ' .. staging) end
    f:write(text)
    f:close()
    os.rename(staging, tmpfile)
end

function M.open_agent(initial_prompt)
    if not M._in_tmux() then
        error('todo-ai requires tmux. Start Neovim inside a tmux session.')
    end

    local dir = M._state_dir()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ vim.v.servername }, dir .. '/nvim-socket')

    local harness = config.get('harness')

    -- Reconnect if agent is already running for this CWD
    if M._is_pane_alive() then
        if initial_prompt then
            if harness == config.HARNESS_PI then
                M._write_prompt(initial_prompt)
            elseif harness == config.HARNESS_CLAUDE_CODE then
                M._send_keys(initial_prompt)
            end
        end
        vim.fn.system({ 'tmux', 'select-pane', '-t', M.state.tmux_pane })
        return
    end

    -- Spawn new agent
    local cmd = M._build_cmd(initial_prompt)
    local socket = vim.v.servername
    local width = config.get('pane_width')
    local tag = config.get('tag')

    local parts = {
        'env',
        'NVIM=' .. socket,
        'TODO_AI_STATE_DIR=' .. dir,
        'TODO_AI_TAG=' .. tag,
    }
    for _, arg in ipairs(cmd) do
        table.insert(parts, arg)
    end
    local shell_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, parts), ' ')

    local result = vim.trim(vim.fn.system({
        'tmux', 'split-window', '-h', '-l', tostring(width),
        '-P', '-F', '#{pane_id}',
        shell_cmd,
    }))
    if vim.v.shell_error ~= 0 or not result:match('^%%') then
        error('todo-ai: failed to create tmux pane: ' .. result)
    end
    M.state.tmux_pane = result
    vim.fn.writefile({ result }, dir .. '/pane-id')
end

-- Backward-compatible alias
M.open_pi = M.open_agent

function M._send_keys(text)
    -- Send literal text + Enter to the agent's tmux pane.
    -- Uses tmux's '-l' (literal) flag so special chars don't get interpreted.
    if not M.state.tmux_pane then return end
    vim.fn.system({ 'tmux', 'send-keys', '-t', M.state.tmux_pane, '-l', text })
    vim.fn.system({ 'tmux', 'send-keys', '-t', M.state.tmux_pane, 'Enter' })
end

function M.send_prompt(text)
    if not M._is_pane_alive() then
        M.open_agent(text)
        return
    end
    local harness = config.get('harness')
    if harness == config.HARNESS_PI then
        M._write_prompt(text)
    elseif harness == config.HARNESS_CLAUDE_CODE then
        M._send_keys(text)
    end
end

function M.scan()
    if not M._is_pane_alive() then
        M.open_agent()
    end
    local harness = config.get('harness')
    if harness == config.HARNESS_PI then
        M._write_prompt('__SCAN__')
    elseif harness == config.HARNESS_CLAUDE_CODE then
        M._send_keys('/scan')
    end
end

function M.focus_agent()
    if M._is_pane_alive() then
        vim.fn.system({ 'tmux', 'select-pane', '-t', M.state.tmux_pane })
    else
        M.open_agent()
    end
end

-- Backward-compatible alias
M.focus_pi = M.focus_agent

-- Remote functions (called by pi extension via nvim --server) -----------------

function M.remote_open(path, line)
    vim.schedule(function()
        vim.cmd('edit +' .. (line or 1) .. ' ' .. vim.fn.fnameescape(path))
    end)
end

function M.remote_diff_review()
    vim.schedule(function()
        vim.cmd('DiffviewOpen')
    end)
end

function M.remote_get_context()
    local ctx = { open_files = {} }

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

return M
