-- Path normalization. Every path crossing the nvim <-> agent boundary is
-- absolute; the sender absolutizes against its own cwd because the two sides
-- may sit at different depths of the same tree (agent above, nvim below).
local M = {}

-- Expand ~ and collapse redundant/trailing slashes. Symlinks are deliberately
-- left alone: resolving them would rewrite paths the user typed (/etc ->
-- /private/etc on darwin) and break comparisons against agent-reported paths.
function M.normalize(path)
    if not path or path == '' then return nil end
    local p = vim.fn.expand(path)
    p = p:gsub('//+', '/'):gsub('(.)/+$', '%1')
    return p
end

-- Canonical form for comparison only: resolves symlinks when the path exists,
-- so a tmux-reported /var/... and an nvim-reported /private/var/... compare
-- equal on darwin. Display paths keep whatever the source reported.
function M.real(path)
    local p = M.normalize(path)
    if not p then return nil end
    local ok, resolved = pcall(vim.uv.fs_realpath, p)
    if ok and resolved then return M.normalize(resolved) end
    return p
end

-- Resolve a relative path against base. Never falls back to vim.fn.getcwd():
-- the agent may sit anywhere in the tree, so an unbased relative path is
-- ambiguous rather than merely inconvenient.
function M.abs(path, base)
    local p = M.normalize(path)
    if not p then return nil end
    if p:sub(1, 1) == '/' then return p end
    local b = M.normalize(base)
    if not b then
        error('todo-ai.paths.abs: base required to resolve relative path: ' .. path)
    end
    return M.normalize(b .. '/' .. p)
end

-- True when ancestor contains descendant at a component boundary, so /a/b
-- contains /a/b/c but not /a/bc. Equal paths count as ancestors.
function M.is_ancestor(ancestor, descendant)
    local a, d = M.real(ancestor), M.real(descendant)
    if not a or not d then return false end
    if a == d then return true end
    if a == '/' then return d:sub(1, 1) == '/' end
    return d:sub(1, #a + 1) == a .. '/'
end

-- Components between ancestor and descendant; nil when unrelated. Ranks
-- candidate pairings nearest-first.
function M.distance(ancestor, descendant)
    if not M.is_ancestor(ancestor, descendant) then return nil end
    local a, d = M.real(ancestor), M.real(descendant)
    if a == d then return 0 end
    local rest = d:sub(#a + 2)
    local n = 0
    for _ in rest:gmatch('[^/]+') do n = n + 1 end
    return n
end

return M
