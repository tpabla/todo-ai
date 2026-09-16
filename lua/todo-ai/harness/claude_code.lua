-- Claude Code harness. See todo-ai.harness.interface for the contract.

return {
    name = 'claude_code',
    label = 'claude',
    bin = 'claude',
    process_pattern = 'claude',
    deliver = 'send_keys',
    scan_prompt = '/scan',

    -- --plugin-dir loads the bundled plugin (MCP server, hooks, /scan skill)
    -- in-place, so nothing is copied under ~/.claude/.
    build_cmd = function(opts)
        local config = require('todo-ai.config')
        opts = opts or {}
        local cmd = { 'claude' }
        if opts.plugin_root then
            vim.list_extend(cmd, { '--plugin-dir', opts.plugin_root })
        end

        if opts.session_id then
            vim.list_extend(cmd, { '--resume', opts.session_id })
        elseif (opts.session_mode or config.get('session_mode')) == 'resume' then
            table.insert(cmd, '--continue')
        end

        local model = config.get('claude_model')
        if model then
            vim.list_extend(cmd, { '--model', model })
        end

        vim.list_extend(cmd, config.get('claude_extra_args') or {})
        if opts.initial_prompt then
            table.insert(cmd, opts.initial_prompt)
        end
        return cmd
    end,

    resume_args = function(id) return { '--resume', id } end,

    installed = function()
        local root = require('todo-ai.init')._plugin_root()
        if vim.fn.isdirectory(root .. '/mcp-server/node_modules') == 1 then
            return true
        end
        return false, 'mcp-server deps not installed. Run :TodoAIInstall.'
    end,

    install = function(notify)
        local root = require('todo-ai.init')._plugin_root()
        if vim.fn.isdirectory(root .. '/mcp-server/node_modules') == 1 then
            notify('mcp-server deps already installed')
            return true
        end
        if vim.fn.executable('npm') ~= 1 then
            notify('npm not found on PATH — cannot install mcp-server deps',
                vim.log.levels.ERROR)
            return false
        end
        notify('installing mcp-server deps...')
        local out = vim.fn.system({ 'npm', '--prefix', root .. '/mcp-server',
            'install', '--silent' })
        if vim.v.shell_error ~= 0 then
            notify('npm install failed:\n' .. out, vim.log.levels.ERROR)
            return false
        end
        notify('mcp-server deps installed')
        notify(
            'To skip permission prompts for the Neovim MCP tools, add this to\n' ..
            '~/.claude/settings.json (one-time, optional):\n\n' ..
            '  { "permissions": { "allow": ["mcp__plugin_todo-ai-nvim_neovim__*"] } }'
        )
        return true
    end,
}
