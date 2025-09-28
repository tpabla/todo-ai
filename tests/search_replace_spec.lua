-- Comprehensive test suite for SEARCH/REPLACE functionality
describe("SEARCH/REPLACE functionality", function()
  local diff_native = require('todo-ai.diff_native')
  local search_replace = require('todo-ai.search_replace')
  local parser = require('todo-ai.parser')

  -- Helper to create a test buffer
  local function create_buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  -- Helper to get buffer lines
  local function get_buffer_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  describe("schema.apply_search_replace", function()
    it("should apply simple single-line replacement", function()
      local lines = {"hello", "world", "test"}
      local new_lines, err = schema.apply_search_replace(lines, "world", "universe")

      assert.is_nil(err)
      assert.are.same({"hello", "universe", "test"}, new_lines)
    end)

    it("should apply multi-line replacement", function()
      local lines = {"def foo():", "    pass", "", "def bar():", "    pass"}
      local search = "def foo():\n    pass"
      local replace = "def foo():\n    return 42"

      local new_lines, err = schema.apply_search_replace(lines, search, replace)

      assert.is_nil(err)
      assert.are.same({"def foo():", "    return 42", "", "def bar():", "    pass"}, new_lines)
    end)

    it("should return error when search text not found", function()
      local lines = {"hello", "world"}
      local new_lines, err = schema.apply_search_replace(lines, "notfound", "replace")

      assert.is_nil(new_lines)
      assert.equals("Search text not found", err)
    end)

    it("should handle empty replacement", function()
      local lines = {"hello", "world", "test"}
      local new_lines, err = schema.apply_search_replace(lines, "world\n", "")

      assert.is_nil(err)
      assert.are.same({"hello", "test"}, new_lines)
    end)
  end)

  describe("schema.apply_changes", function()
    it("should apply multiple changes sequentially", function()
      local lines = {"line1", "line2", "line3"}
      local changes = {
        {search = "line1", replace = "first"},
        {search = "line2", replace = "second"},
        {search = "line3", replace = "third"}
      }

      local result, count, err = schema.apply_changes(lines, changes)

      assert.is_nil(err)
      assert.equals(3, count)
      assert.are.same({"first", "second", "third"}, result)
    end)

    it("should continue on failed change and report errors", function()
      local lines = {"hello", "world"}
      local changes = {
        {search = "hello", replace = "hi"},
        {search = "notfound", replace = "test"},
        {search = "world", replace = "universe"}
      }

      local result, count, err = schema.apply_changes(lines, changes)

      assert.equals(2, count)
      assert.is_not_nil(err)
      assert.are.same({"hi", "universe"}, result)
    end)
  end)

  describe("diff_native visual display", function()
    before_each(function()
      -- Clear any existing state
      diff_native.clear_diff()
    end)

    it("should build clean display without SEARCH/REPLACE markers", function()
      local original = {"import sys", "", "# TODO: add function", "", "def main():", "    pass"}
      local changes = {
        {
          search = "# TODO: add function",
          replace = "def hello():\n    print('Hello')",
          description = "Add hello function"
        }
      }

      -- Initialize state
      diff_native.state.response = {changes = changes}
      diff_native.state.rejected_diffs = {}
      diff_native.state.hunks = {{change_index = 1}}

      local display = diff_native.build_search_replace_display(original, changes)

      -- Should show the result with changes applied
      assert.is_not_nil(display)
      assert.is_true(#display > 0)

      -- Should NOT contain SEARCH/REPLACE markers
      local has_markers = false
      for _, line in ipairs(display) do
        if line:match("<<<<<<< SEARCH") or line:match(">>>>>>> REPLACE") then
          has_markers = true
          break
        end
      end
      assert.is_false(has_markers)
    end)

    it("should handle rejected changes", function()
      local original = {"line1", "line2", "line3"}
      local changes = {
        {search = "line1", replace = "new1"},
        {search = "line2", replace = "new2"},
        {search = "line3", replace = "new3"}
      }

      -- Mark second change as rejected
      diff_native.state.response = {changes = changes}
      diff_native.state.rejected_diffs = {[2] = true}
      diff_native.state.hunks = {
        {change_index = 1},
        {change_index = 2},
        {change_index = 3}
      }

      local display = diff_native.build_search_replace_display(original, changes)

      -- Should apply all except rejected
      assert.are.same({"new1", "line2", "new3"}, display)
    end)
  end)

  describe("diff_native navigation", function()
    local buf

    before_each(function()
      buf = create_buffer({"line1", "line2", "line3"})
      diff_native.clear_diff()

      -- Set up some test hunks
      diff_native.state.hunks = {
        {start_line = 2, end_line = 4, change_index = 1},
        {start_line = 6, end_line = 8, change_index = 2},
        {start_line = 10, end_line = 12, change_index = 3}
      }
      diff_native.state.target_buf = buf
    end)

    after_each(function()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, {force = true})
      end
    end)

    it("should navigate to next hunk", function()
      -- Set current buffer
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- Navigate to next hunk
      diff_native.goto_next_hunk()

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.equals(2, pos[1])  -- Should jump to first hunk at line 2
    end)

    it("should wrap to first hunk from end", function()
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, {15, 0})  -- Past last hunk

      diff_native.goto_next_hunk()

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.equals(2, pos[1])  -- Should wrap to first hunk
    end)

    it("should handle no hunks gracefully", function()
      diff_native.state.hunks = {}

      -- Should not error
      assert.has_no.errors(function()
        diff_native.goto_next_hunk()
        diff_native.goto_prev_hunk()
      end)
    end)
  end)

  describe("parser JSON response", function()
    it("should parse valid SEARCH/REPLACE response", function()
      local response = vim.fn.json_encode({
        changes = {
          {
            search = "old code",
            replace = "new code",
            description = "Update code"
          }
        },
        language = "python",
        explanation = "Updated the code"
      })

      local result = parser.parse(response, "test")

      assert.equals("json_response", result.format_detected)
      assert.is_not_nil(result.changes)
      assert.equals(1, #result.changes)
      assert.equals("old code", result.changes[1].search)
      assert.equals("new code", result.changes[1].replace)
    end)

    it("should handle malformed JSON gracefully", function()
      local response = "{ invalid json"

      local result = parser.parse(response, "test")

      -- Should fall back to another format
      assert.not_equals("json_response", result.format_detected)
    end)
  end)

  describe("hanging prevention", function()
    it("should not hang on circular references", function()
      local lines = {"line1", "line2", "line3"}
      local changes = {
        {search = "line1", replace = "line2"},
        {search = "line2", replace = "line1"}
      }

      -- Should complete without hanging
      local success, result = pcall(function()
        return schema.apply_changes(lines, changes)
      end)

      assert.is_true(success)
    end)

    it("should handle very large files without hanging", function()
      -- Create a large file
      local large_lines = {}
      for i = 1, 10000 do
        table.insert(large_lines, "line " .. i)
      end

      local changes = {
        {search = "line 5000", replace = "modified line"}
      }

      -- Should complete in reasonable time
      local start_time = vim.loop.now()
      local result, count = schema.apply_changes(large_lines, changes)
      local elapsed = vim.loop.now() - start_time

      assert.is_true(elapsed < 1000)  -- Should complete in under 1 second
      assert.equals(1, count)
    end)

    it("should handle empty buffer gracefully", function()
      local buf = create_buffer({})
      diff_native.state.target_buf = buf

      local response = {
        changes = {{search = "test", replace = "new"}}
      }

      -- Should not error on empty buffer
      assert.has_no.errors(function()
        diff_native.show_response(buf, response)
      end)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)
  end)

  describe("accept/reject functionality", function()
    it("should track accepted and rejected changes", function()
      diff_native.clear_diff()
      diff_native.state.response = {
        changes = {
          {search = "a", replace = "A"},
          {search = "b", replace = "B"},
          {search = "c", replace = "C"}
        }
      }
      diff_native.state.hunks = {
        {change_index = 1},
        {change_index = 2},
        {change_index = 3}
      }

      -- Accept first, reject second
      diff_native.state.accepted_diffs[1] = true
      diff_native.state.rejected_diffs[2] = true

      -- Third is pending (neither accepted nor rejected)
      assert.is_true(diff_native.state.accepted_diffs[1])
      assert.is_true(diff_native.state.rejected_diffs[2])
      assert.is_nil(diff_native.state.accepted_diffs[3])
      assert.is_nil(diff_native.state.rejected_diffs[3])
    end)
  end)
end)