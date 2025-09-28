describe("diff_mini", function()
  local diff_mini
  local schema
  local mock_mini_diff

  before_each(function()
    -- Create mock before requiring modules
    mock_mini_diff = {
    ref_text = nil,
    enabled = {},
    overlay_shown = false,

    set_ref_text = function(buf, text)
      mock_mini_diff.ref_text = text
    end,

    enable = function(buf)
      mock_mini_diff.enabled[buf] = true
    end,

    toggle_overlay = function(buf)
      mock_mini_diff.overlay_shown = not mock_mini_diff.overlay_shown
      vim.b[buf] = vim.b[buf] or {}
      vim.b[buf].minidiff_overlay_shown = mock_mini_diff.overlay_shown
    end
  }

    -- Replace mini.diff with mock before loading diff_mini
    package.loaded['mini.diff'] = mock_mini_diff

    -- Now load the modules
    diff_mini = require("todo-ai.diff_mini")
    schema = require("todo-ai.schema")
  end)

  describe("show_response", function()
    local test_buf

    before_each(function()
      test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "line 1",
        "TODO: implement this",
        "line 3",
        "line 4"
      })
      mock_mini_diff.ref_text = nil
      mock_mini_diff.overlay_shown = false
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, {force = true})
      end
      diff_mini.state = {
        target_buf = nil,
        response = nil,
        hunks = {}
      }
    end)

    it("should handle changes format with lines array", function()
      local response = {
        changes = {
          {
            start_line = 2,
            end_line = 2,
            lines = {"function doSomething() {", "  return true", "}"},
            description = "Implement function"
          }
        },
        explanation = "Added implementation"
      }

      diff_mini.show_response(test_buf, response)

      assert.is_not_nil(mock_mini_diff.ref_text)
      assert.are.equal(1, #diff_mini.state.hunks)
      assert.are.equal(2, diff_mini.state.hunks[1].start_line)
      assert.are.equal('change', diff_mini.state.hunks[1].type)
    end)

    it("should handle changes format with code string", function()
      local response = {
        changes = {
          {
            start_line = 2,
            end_line = 2,
            code = "const result = 42;",
            description = "Simple replacement"
          }
        }
      }

      diff_mini.show_response(test_buf, response)

      assert.is_not_nil(mock_mini_diff.ref_text)
      assert.are.equal(1, #diff_mini.state.hunks)
    end)

    it("should handle deletion (empty lines array)", function()
      local response = {
        changes = {
          {
            start_line = 2,
            end_line = 2,
            lines = {},
            description = "Remove TODO"
          }
        }
      }

      diff_mini.show_response(test_buf, response)

      assert.is_not_nil(mock_mini_diff.ref_text)
      -- Reference should be the ORIGINAL content
      assert.is_true(mock_mini_diff.ref_text:match("line 1\nTODO: implement this\nline 3\nline 4") ~= nil)
    end)

    it("should handle edits format", function()
      local response = {
        edits = {
          ["2"] = "edited line 2",
          ["4"] = ""  -- Delete line 4
        }
      }

      diff_mini.show_response(test_buf, response)

      assert.is_not_nil(mock_mini_diff.ref_text)
      assert.are.equal(2, #diff_mini.state.hunks)
      -- Hunks should be sorted by line number
      assert.are.equal(2, diff_mini.state.hunks[1].start_line)
      assert.are.equal(4, diff_mini.state.hunks[2].start_line)
    end)

    it("should handle multiple changes", function()
      local response = {
        changes = {
          {
            start_line = 1,
            end_line = 1,
            lines = {"// Header comment"},
            description = "Add header"
          },
          {
            start_line = 2,
            end_line = 2,
            lines = {"implemented()"},
            description = "Implement TODO"
          }
        }
      }

      diff_mini.show_response(test_buf, response)

      assert.are.equal(2, #diff_mini.state.hunks)
      assert.are.equal(1, diff_mini.state.hunks[1].start_line)
      assert.are.equal(2, diff_mini.state.hunks[2].start_line)
    end)
  end)

  describe("hunk navigation", function()
    local test_buf
    local test_win

    before_each(function()
      test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "line 1", "line 2", "line 3", "line 4", "line 5",
        "line 6", "line 7", "line 8", "line 9", "line 10"
      })

      -- Create a window for the buffer
      test_win = vim.api.nvim_open_win(test_buf, true, {
        relative = 'editor',
        row = 0, col = 0,
        width = 50, height = 10,
        style = 'minimal'
      })

      -- Setup test hunks
      diff_mini.state.hunks = {
        {start_line = 2, end_line = 2, type = 'change'},
        {start_line = 5, end_line = 6, type = 'change'},
        {start_line = 9, end_line = 9, type = 'change'}
      }
    end)

    after_each(function()
      if vim.api.nvim_win_is_valid(test_win) then
        vim.api.nvim_win_close(test_win, true)
      end
      if vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, {force = true})
      end
    end)

    it("should navigate to next hunk", function()
      vim.api.nvim_win_set_cursor(0, {1, 0})

      diff_mini.goto_next_hunk()
      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(2, pos[1])

      diff_mini.goto_next_hunk()
      pos = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(5, pos[1])
    end)

    it("should wrap to first hunk from last", function()
      vim.api.nvim_win_set_cursor(0, {10, 0})

      diff_mini.goto_next_hunk()
      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(2, pos[1])  -- Wrapped to first
    end)

    it("should navigate to previous hunk", function()
      vim.api.nvim_win_set_cursor(0, {10, 0})

      diff_mini.goto_prev_hunk()
      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(9, pos[1])

      diff_mini.goto_prev_hunk()
      pos = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(5, pos[1])
    end)

    it("should find hunk at cursor position", function()
      vim.api.nvim_win_set_cursor(0, {5, 0})

      local idx, hunk = diff_mini.get_hunk_at_cursor()
      assert.are.equal(2, idx)
      assert.are.equal(5, hunk.start_line)
    end)
  end)

  describe("accept/reject operations", function()
    it("should accept all changes", function()
      local test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "line 1",
        "TODO: fix this",
        "line 3"
      })

      local response = {
        changes = {
          {
            start_line = 2,
            end_line = 2,
            lines = {"fixed!"},
            description = "Fix TODO"
          }
        }
      }

      -- Call show_response which applies changes immediately
      diff_mini.show_response(test_buf, response)

      -- Now accept the changes (which just clears the diff)
      diff_mini.accept()

      local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
      assert.are.same({"line 1", "fixed!", "line 3"}, lines)
      assert.is_nil(diff_mini.state.response)

      vim.api.nvim_buf_delete(test_buf, {force = true})
    end)

    it("should reject all changes", function()
      local test_buf = vim.api.nvim_create_buf(false, true)
      local original_lines = {"line 1", "TODO: fix this", "line 3"}
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, original_lines)

      local response = {
        changes = {{start_line = 2, end_line = 2, lines = {"fixed!"}}}
      }

      -- Call show_response which applies changes and stores original
      diff_mini.show_response(test_buf, response)

      -- Now reject the changes (which should restore original)
      diff_mini.reject()

      local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
      assert.are.same(original_lines, lines)  -- Should be restored to original
      assert.is_nil(diff_mini.state.response)

      vim.api.nvim_buf_delete(test_buf, {force = true})
    end)
  end)

  describe("legacy compatibility", function()
    it("should handle old show_changes format", function()
      local test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {"line 1", "line 2", "line 3"})

      diff_mini.show_changes(test_buf, 2, 2, "new line 2", "Test change")

      assert.is_not_nil(diff_mini.state.response)
      assert.are.equal(1, #diff_mini.state.response.changes)
      assert.are.equal("new line 2", diff_mini.state.response.changes[1].code)

      vim.api.nvim_buf_delete(test_buf, {force = true})
    end)
  end)
end)