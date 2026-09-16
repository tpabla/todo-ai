-- Harness registry. A harness is a spec table, not a branch: adding one means
-- dropping a file in this directory that satisfies harness.interface and
-- registering it. Nothing outside this directory compares harness names.
local interface = require('todo-ai.harness.interface')

local M = {}

M.interface = interface
M.specs = {}

-- Shipped harnesses, registered on load. A user harness can be added with
-- require('todo-ai.harness').register(spec).
M.BUILTINS = { 'claude_code', 'pi' }

function M.register(spec)
    local ok, err = interface.validate(spec)
    if not ok then
        error('todo-ai: invalid harness spec: ' .. err)
    end
    M.specs[spec.name] = spec
    return spec
end

function M.names()
    local names = vim.tbl_keys(M.specs)
    table.sort(names)
    return names
end

function M.get(name)
    local spec = M.specs[name]
    if not spec then
        error(string.format('todo-ai: unknown harness %q (known: %s)',
            tostring(name), table.concat(M.names(), ', ')))
    end
    return spec
end

function M.current()
    return M.get(require('todo-ai.config').get('harness'))
end

-- Single prompt-delivery path for every harness. deps supplies the mechanisms
-- so this stays testable without tmux: { send_keys, write_prompt }.
function M.deliver_prompt(spec, pane_id, text, deps)
    if type(spec.deliver) == 'function' then
        return spec.deliver({ pane_id = pane_id, text = text, deps = deps })
    end

    if spec.deliver == 'send_keys' then
        return deps.send_keys(pane_id, text)
    elseif spec.deliver == 'prompt_file' then
        return deps.write_prompt(text)
    end

    error(string.format('todo-ai: harness %q has unsupported delivery mode %q',
        spec.name, tostring(spec.deliver)))
end

for _, name in ipairs(M.BUILTINS) do
    M.register(require('todo-ai.harness.' .. name))
end

return M
