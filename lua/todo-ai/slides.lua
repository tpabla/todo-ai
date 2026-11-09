-- Slides above the code: a markdown split shows one slide, the window below
-- shows the code it names. The user moves through them; nothing auto-advances.
--
-- Deck: markdown, slides separated by a line of `---` outside code fences.
-- A slide names its code with `<!-- code: path[:a[-b]] -->`.
-- A slide is { lines, code = { path, first, last } | nil }.

local M = {}

-- Pure: deck lines -> slides. Code paths are returned as written; the caller
-- resolves them. Errors on an empty deck.
function M.parse(lines)
    error('not implemented')
end

-- deps: { height = 0.4 } plus the code window to drive (defaults to current).
-- Replaces any deck already shown.
function M.show(slides, deps)
    error('not implemented')
end

function M.next()
    error('not implemented')
end

function M.prev()
    error('not implemented')
end

function M.close()
    error('not implemented')
end

return M
