-- Slides above the code: a markdown split shows one slide, the window below
-- shows the code it names. The user moves through them; nothing auto-advances.
--
-- Deck: markdown, slides separated by a line of `---` outside code fences.
-- A slide names its code with `<!-- code: path[:a[-b]] -->`.
-- parse gives { lines, code = "path[:a[-b]]" | nil }; the CLI resolves code to
-- { path, first, last } with an absolute path before the editor sees it.

local M = {}

M.state = {
    win = nil,
    code_win = nil,
    slides = nil,
    index = 1,
}

local CODE = '^%s*<!%-%-%s*code:%s*(.-)%s*%-%->%s*$'

local function trim(lines)
    while #lines > 0 and vim.trim(lines[1]) == '' do table.remove(lines, 1) end
    while #lines > 0 and vim.trim(lines[#lines]) == '' do table.remove(lines) end
    return lines
end

-- Pure: deck lines -> slides, blank lines trimmed around each. Errors on an
-- empty deck.
function M.parse(lines)
    local slides, current, fenced = {}, { lines = {} }, false

    local function finish()
        trim(current.lines)
        if #current.lines > 0 then table.insert(slides, current) end
        current = { lines = {} }
    end

    for _, line in ipairs(lines) do
        if line:match('^%s*```') or line:match('^%s*~~~') then fenced = not fenced end
        local code = not fenced and line:match(CODE)
        if not fenced and line:match('^%-%-%-+%s*$') then
            finish()
        elseif code then
            current.code = code
        else
            table.insert(current.lines, line)
        end
    end
    finish()

    if #slides == 0 then error('todo-ai: the deck has no slides', 0) end
    return slides
end

local function valid(win)
    return win and vim.api.nvim_win_is_valid(win)
end

local function title(slide)
    for _, line in ipairs(slide.lines) do
        local heading = line:match('^#+%s+(.+)')
        if heading then return heading end
    end
    return ''
end

local function render()
    local slide = M.state.slides[M.state.index]
    local win = M.state.win
    local buf = vim.api.nvim_win_get_buf(win)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, slide.lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.wo[win].winbar = string.format(' %d / %d · %s',
        M.state.index, #M.state.slides, (title(slide):gsub('%%', '%%%%')))

    if slide.code and valid(M.state.code_win) then
        vim.api.nvim_win_call(M.state.code_win, function()
            require('todo-ai').remote_open(slide.code.path, slide.code.first, slide.code.last)
        end)
    end
end

local function open_split(code_win, height)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'markdown'
    for key, fn in pairs({ l = M.next, h = M.prev, q = M.close }) do
        vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, desc = 'todo-ai slides' })
    end

    local win = vim.api.nvim_open_win(buf, true, {
        split = 'above',
        win = code_win,
        height = math.max(3, math.floor(vim.api.nvim_win_get_height(code_win) * height)),
    })
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].wrap = true
    -- markdown fold settings would collapse a slide's code blocks
    vim.wo[win].foldenable = false
    return win
end

-- Opens a markdown split above the code window showing slide 1, with l/h/q
-- to move and close. opts: { height = share of the code window, code_win }.
-- Showing again reuses the split.
function M.show(slides, opts)
    opts = opts or {}
    local current = vim.api.nvim_get_current_win()
    local code_win = opts.code_win
        or (current == M.state.win and M.state.code_win)
        or current

    if not valid(M.state.win) then
        M.state.win = open_split(code_win, opts.height or 0.4)
    end
    vim.api.nvim_set_current_win(M.state.win)

    M.state.code_win = code_win
    M.state.slides = slides
    M.state.index = 1
    render()
end

local function move(by)
    if not (M.state.slides and valid(M.state.win)) then return end
    local index = math.max(1, math.min(#M.state.slides, M.state.index + by))
    if index == M.state.index then return end
    M.state.index = index
    render()
end

function M.next() move(1) end

function M.prev() move(-1) end

function M.close()
    local ns = require('todo-ai')._ns
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
    if valid(M.state.win) then vim.api.nvim_win_close(M.state.win, true) end
    M.state.win, M.state.slides, M.state.index = nil, nil, 1
end

return M
