describe("slides.parse", function()
  local slides = require('todo-ai.slides')

  it("splits on --- lines", function()
    local deck = slides.parse({ '# One', 'a', '---', '# Two', 'b' })
    assert.equals(2, #deck)
    assert.same({ '# One', 'a' }, deck[1].lines)
    assert.same({ '# Two', 'b' }, deck[2].lines)
  end)

  it("ignores --- inside code fences", function()
    local deck = slides.parse({
      '# One', '```mermaid', 'flowchart LR', '---', 'A --> B', '```', '---', '# Two',
    })
    assert.equals(2, #deck)
    assert.same({ '# One', '```mermaid', 'flowchart LR', '---', 'A --> B', '```' }, deck[1].lines)
  end)

  it("takes the code reference out of the slide", function()
    local deck = slides.parse({ '# One', '<!-- code: src/a.lua:3-9 -->', 'text' })
    assert.equals('src/a.lua:3-9', deck[1].code)
    assert.same({ '# One', 'text' }, deck[1].lines)
  end)

  it("has no code when the slide names none", function()
    assert.is_nil(slides.parse({ '# One', 'text' })[1].code)
  end)

  it("trims blank lines around each slide", function()
    local deck = slides.parse({ '', '# One', '', 'a', '', '---', '', '# Two', '' })
    assert.same({ '# One', '', 'a' }, deck[1].lines)
    assert.same({ '# Two' }, deck[2].lines)
  end)

  it("errors on an empty deck", function()
    assert.has_error(function() slides.parse({}) end)
    assert.has_error(function() slides.parse({ '', '---', '' }) end)
  end)
end)

describe("slides viewer", function()
  local slides, init, files

  local function file(n)
    local path = vim.fn.tempname() .. '.lua'
    local lines = {}
    for i = 1, n do lines[i] = 'line ' .. i end
    vim.fn.writefile(lines, path)
    return vim.uv.fs_realpath(path)
  end

  local function deck()
    return {
      { lines = { '# First', 'about a' }, code = { path = files[1], first = 3, last = 5 } },
      { lines = { '# Second', 'no code here' } },
      { lines = { '# Third', 'about b' }, code = { path = files[2], first = 7, last = 7 } },
    }
  end

  local function buf_path(win)
    return vim.uv.fs_realpath(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))
  end

  local function slide_text()
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(slides.state.win), 0, -1, false)
  end

  before_each(function()
    vim.cmd('silent! only | silent! %bwipeout!')
    package.loaded['todo-ai.slides'] = nil
    slides = require('todo-ai.slides')
    init = require('todo-ai.init')
    files = { file(20), file(20) }
  end)

  it("opens a markdown split above the code window showing slide 1", function()
    local code_win = vim.api.nvim_get_current_win()
    local total = vim.api.nvim_win_get_height(code_win)
    slides.show(deck(), { height = 0.4 })

    local win = slides.state.win
    assert.is_true(vim.api.nvim_win_get_position(win)[1] < vim.api.nvim_win_get_position(code_win)[1])
    assert.near(total * 0.4, vim.api.nvim_win_get_height(win), 2)
    assert.equals('markdown', vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
    assert.is_false(vim.wo[win].foldenable)
    assert.same({ '# First', 'about a' }, slide_text())
    for _, key in ipairs({ 'l', 'h', 'q' }) do
      assert.is_true(vim.fn.maparg(key, 'n', false, true).buffer == 1)
    end
  end)

  it("shows the slide's code below with its range highlighted, focus in the slides", function()
    local code_win = vim.api.nvim_get_current_win()
    slides.show(deck(), { height = 0.4 })

    assert.equals(files[1], buf_path(code_win))
    assert.equals(3, vim.api.nvim_win_get_cursor(code_win)[1])
    local marks = vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(code_win), init._ns, 0, -1, { details = true })
    assert.equals(1, #marks)
    assert.equals(2, marks[1][2])
    assert.equals(5, marks[1][4].end_row)
    assert.equals(slides.state.win, vim.api.nvim_get_current_win())
  end)

  it("moves between slides and stops at the ends", function()
    local code_win = vim.api.nvim_get_current_win()
    slides.show(deck(), { height = 0.4 })

    slides.prev()
    assert.same({ '# First', 'about a' }, slide_text())
    slides.next()
    slides.next()
    assert.same({ '# Third', 'about b' }, slide_text())
    assert.equals(files[2], buf_path(code_win))
    assert.equals(7, vim.api.nvim_win_get_cursor(code_win)[1])
    slides.next()
    assert.same({ '# Third', 'about b' }, slide_text())
    slides.prev()
    assert.same({ '# Second', 'no code here' }, slide_text())
  end)

  it("leaves the code window alone for a slide without code", function()
    local code_win = vim.api.nvim_get_current_win()
    slides.show(deck(), { height = 0.4 })
    slides.next()
    assert.equals(files[1], buf_path(code_win))
    assert.equals(3, vim.api.nvim_win_get_cursor(code_win)[1])
  end)

  it("reuses the split when shown again", function()
    slides.show(deck(), { height = 0.4 })
    local win = slides.state.win
    local count = #vim.api.nvim_tabpage_list_wins(0)
    slides.show({ { lines = { '# Other' } } }, { height = 0.4 })
    assert.equals(win, slides.state.win)
    assert.equals(count, #vim.api.nvim_tabpage_list_wins(0))
    assert.same({ '# Other' }, slide_text())
  end)

  it("closes the split and its highlight, keeping the code window", function()
    local code_win = vim.api.nvim_get_current_win()
    slides.show(deck(), { height = 0.4 })
    local win = slides.state.win
    slides.close()

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_true(vim.api.nvim_win_is_valid(code_win))
    local buf = vim.api.nvim_win_get_buf(code_win)
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(buf, init._ns, 0, -1, {}))
  end)

  it("titles the split with the position and slide heading", function()
    slides.show(deck(), { height = 0.4 })
    assert.matches('1 / 3', vim.wo[slides.state.win].winbar, 1, true)
    assert.matches('First', vim.wo[slides.state.win].winbar, 1, true)
    slides.next()
    assert.matches('2 / 3', vim.wo[slides.state.win].winbar, 1, true)
    assert.matches('Second', vim.wo[slides.state.win].winbar, 1, true)
  end)
end)
