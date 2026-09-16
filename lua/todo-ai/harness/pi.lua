-- pi harness. See todo-ai.harness.interface for the contract.

return {
    name = 'pi',
    label = 'pi',
    bin = 'pi',
    process_pattern = 'pi',
    deliver = 'prompt_file',
    scan_prompt = '__SCAN__',

    build_cmd = function(opts)
        local config = require('todo-ai.config')
        opts = opts or {}
        local cmd = { 'pi' }
        if opts.extension_path then
            vim.list_extend(cmd, { '-e', opts.extension_path })
        end

        if opts.session_id then
            vim.list_extend(cmd, { '--session', opts.session_id })
        elseif (opts.session_mode or config.get('session_mode') or 'resume') == 'resume' then
            table.insert(cmd, '--resume')
        end

        vim.list_extend(cmd, config.get('pi_extra_args') or {})
        if opts.initial_prompt then
            table.insert(cmd, opts.initial_prompt)
        end
        return cmd
    end,

    -- pi's --resume is an interactive picker that takes no id, so targeting a
    -- specific session needs --session.
    resume_args = function(id) return { '--session', id } end,

    installed = function()
        -- pi install stores a relative path in settings.json, so match on the
        -- unique suffix rather than an absolute path.
        local settings = require('todo-ai.init')._read_file(
            vim.fn.expand('~/.pi/agent/settings.json'))
        if settings and settings:find('todo%-ai/extension/neovim%.ts', 1) then
            return true
        end
        return false, 'pi extension not installed globally. Run :TodoAIInstall.'
    end,

    install = function(notify)
        local init = require('todo-ai.init')
        local spec = require('todo-ai.harness').get('pi')
        if spec.installed() then
            notify('pi extension already installed')
            return true
        end
        if vim.fn.executable('pi') ~= 1 then
            notify('pi not found on PATH', vim.log.levels.ERROR)
            return false
        end
        notify('installing pi extension globally...')
        local out = vim.fn.system({ 'pi', 'install', init._extension_path() })
        if vim.v.shell_error ~= 0 then
            notify('pi install failed:\n' .. out, vim.log.levels.ERROR)
            return false
        end
        notify('pi extension installed — will auto-load for all pi sessions')
        return true
    end,
}
