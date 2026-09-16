-- The harness contract. To integrate a new agent, create
-- lua/todo-ai/harness/<name>.lua returning a table with these fields and
-- register it -- no other file in the plugin needs to change.
--
-- FIELDS is the single source of truth: validate() checks against it and
-- describe() renders it for docs and error messages.
local M = {}

M.DELIVERY_MODES = { 'send_keys', 'prompt_file' }

M.FIELDS = {
    name = {
        type = 'string', required = true,
        doc = 'Identifier used as the `harness` config value.',
    },
    label = {
        type = 'string', required = true,
        doc = 'Human label shown in the pane picker.',
    },
    bin = {
        type = 'string', required = true,
        doc = 'Executable name, checked with vim.fn.executable() before spawning.',
    },
    process_pattern = {
        type = 'string', required = true,
        doc = 'Lua pattern matched against a pane process, to discover agent ' ..
              'panes that have not tagged themselves yet.',
    },
    deliver = {
        type = { 'string', 'function' }, required = true,
        one_of = M.DELIVERY_MODES,
        doc = "How a prompt reaches the agent: 'send_keys' types into the tmux " ..
              "pane, 'prompt_file' writes prompt.md for the agent to poll. A " ..
              'function (ctx) -> nil may be supplied for anything else.',
    },
    scan_prompt = {
        type = 'string', required = true,
        doc = 'Text delivered by :TodoAIScan (e.g. a slash command).',
    },
    build_cmd = {
        type = 'function', required = true,
        doc = 'build_cmd(opts) -> argv. opts: { plugin_root, extension_path, ' ..
              'initial_prompt, session_id, session_mode }. Read harness-specific ' ..
              'options from todo-ai.config directly.',
    },
    resume_args = {
        type = 'function', required = true,
        doc = 'resume_args(session_id) -> argv fragment targeting one session.',
    },
    installed = {
        type = 'function', required = true,
        doc = 'installed() -> boolean, hint. hint is shown when false.',
    },
    install = {
        type = 'function', required = true,
        doc = 'install(notify) -> boolean. notify(msg, level) reports progress.',
    },
}

local function type_ok(value, expected)
    local accepted = type(expected) == 'table' and expected or { expected }
    for _, t in ipairs(accepted) do
        if type(value) == t then return true end
    end
    return false
end

local function type_names(expected)
    return type(expected) == 'table' and table.concat(expected, '|') or expected
end

-- validate(spec) -> ok, err. err names the offending field and the contract it
-- broke, so a partial harness fails at register() rather than at a missed
-- call site.
function M.validate(spec)
    if type(spec) ~= 'table' then
        return false, 'harness spec must be a table, got ' .. type(spec)
    end

    for field, rule in pairs(M.FIELDS) do
        local value = spec[field]

        if value == nil then
            if rule.required then
                return false, string.format('missing required field `%s` (%s)',
                    field, rule.doc)
            end
        elseif not type_ok(value, rule.type) then
            return false, string.format('field `%s` must be %s, got %s',
                field, type_names(rule.type), type(value))
        elseif rule.one_of and type(value) == 'string'
                and not vim.tbl_contains(rule.one_of, value) then
            return false, string.format('field `%s` must be one of %s, got %q',
                field, table.concat(rule.one_of, ', '), value)
        end
    end

    return true
end

-- Renders FIELDS as readable contract text, for docs and error messages.
function M.describe()
    local names = vim.tbl_keys(M.FIELDS)
    table.sort(names)
    local lines = {}
    for _, field in ipairs(names) do
        local rule = M.FIELDS[field]
        table.insert(lines, string.format('%-16s %-8s %s',
            field, type_names(rule.type), rule.doc))
    end
    return table.concat(lines, '\n')
end

return M
