-- Comprehensive test suite for SEARCH/REPLACE functionality
describe("search_replace module", function()
  local search_replace = require('todo-ai.search_replace')

  describe("apply_single", function()
    it("should apply simple replacement", function()
      local content = "hello world"
      local result, err = search_replace.apply_single(content, "world", "universe")

      assert.is_nil(err)
      assert.equals("hello universe", result)
    end)

    it("should apply multi-line replacement", function()
      local content = "line1\nline2\nline3"
      local result, err = search_replace.apply_single(content, "line2", "modified")

      assert.is_nil(err)
      assert.equals("line1\nmodified\nline3", result)
    end)

    it("should return error when search text not found", function()
      local content = "hello world"
      local result, err = search_replace.apply_single(content, "notfound", "replace")

      assert.is_nil(result)
      assert.equals("Search text not found", err)
    end)

    it("should handle empty replacement", function()
      local content = "hello world"
      local result, err = search_replace.apply_single(content, "world", "")

      assert.is_nil(err)
      assert.equals("hello ", result)
    end)

    it("should handle special characters", function()
      local content = "function test() { return true; }"
      local result, err = search_replace.apply_single(content, "return true;", "return false;")

      assert.is_nil(err)
      assert.equals("function test() { return false; }", result)
    end)
  end)

  describe("apply_changes", function()
    it("should apply multiple changes sequentially", function()
      local lines = {"line1", "line2", "line3"}
      local changes = {
        {search = "line1", replace = "first"},
        {search = "line2", replace = "second"},
        {search = "line3", replace = "third"}
      }

      local result, count, err = search_replace.apply_changes(lines, changes)

      assert.is_nil(err)
      assert.equals(3, count)
      assert.are.same({"first", "second", "third"}, result)
    end)

    it("should handle overlapping changes", function()
      local lines = {"def foo():", "    pass", "def bar():", "    pass"}
      local changes = {
        {search = "def foo():\n    pass", replace = "def foo():\n    return 1"},
        {search = "def bar():\n    pass", replace = "def bar():\n    return 2"}
      }

      local result, count, err = search_replace.apply_changes(lines, changes)

      assert.is_nil(err)
      assert.equals(2, count)
      assert.are.same({"def foo():", "    return 1", "def bar():", "    return 2"}, result)
    end)

    it("should continue on errors and report them", function()
      local lines = {"hello", "world"}
      local changes = {
        {search = "hello", replace = "hi"},
        {search = "notfound", replace = "test"},
        {search = "world", replace = "universe"}
      }

      local result, count, err = search_replace.apply_changes(lines, changes)

      assert.equals(2, count)
      assert.is_not_nil(err)
      assert.is_true(err:find("Change 2") ~= nil)
    end)

    it("should handle empty changes array", function()
      local lines = {"line1", "line2"}
      local changes = {}

      local result, count, err = search_replace.apply_changes(lines, changes)

      assert.is_nil(err)
      assert.equals(0, count)
      assert.are.same({"line1", "line2"}, result)
    end)
  end)

  describe("calculate_position", function()
    it("should calculate correct line positions", function()
      local content = "line1\nline2\nline3\nline4"
      local pos = search_replace.calculate_position(content, "line2")

      assert.is_not_nil(pos)
      assert.equals(2, pos.start_line)
      assert.equals(2, pos.end_line)
      assert.equals(1, pos.line_count)
    end)

    it("should handle multi-line search", function()
      local content = "line1\nline2\nline3\nline4"
      local pos = search_replace.calculate_position(content, "line2\nline3")

      assert.is_not_nil(pos)
      assert.equals(2, pos.start_line)
      assert.equals(3, pos.end_line)
      assert.equals(2, pos.line_count)
    end)

    it("should return nil for not found", function()
      local content = "line1\nline2"
      local pos = search_replace.calculate_position(content, "notfound")

      assert.is_nil(pos)
    end)
  end)

  describe("build_display", function()
    it("should apply only non-rejected changes", function()
      local lines = {"a", "b", "c"}
      local changes = {
        {search = "a", replace = "A"},
        {search = "b", replace = "B"},
        {search = "c", replace = "C"}
      }
      local rejected = {[2] = true}

      local result = search_replace.build_display(lines, changes, rejected)

      assert.are.same({"A", "b", "C"}, result)
    end)

    it("should return original when all rejected", function()
      local lines = {"a", "b", "c"}
      local changes = {
        {search = "a", replace = "A"},
        {search = "b", replace = "B"}
      }
      local rejected = {[1] = true, [2] = true}

      local result = search_replace.build_display(lines, changes, rejected)

      assert.are.same({"a", "b", "c"}, result)
    end)
  end)

  describe("validate_change", function()
    it("should validate correct change", function()
      local change = {search = "old", replace = "new"}
      local valid, err = search_replace.validate_change(change)

      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("should reject nil change", function()
      local valid, err = search_replace.validate_change(nil)

      assert.is_false(valid)
      assert.equals("Change is nil", err)
    end)

    it("should reject missing search", function()
      local change = {replace = "new"}
      local valid, err = search_replace.validate_change(change)

      assert.is_false(valid)
      assert.is_true(err:find("search") ~= nil)
    end)

    it("should reject missing replace", function()
      local change = {search = "old"}
      local valid, err = search_replace.validate_change(change)

      assert.is_false(valid)
      assert.is_true(err:find("replace") ~= nil)
    end)
  end)
end)

describe("diff_formatter module", function()
  local formatter = require('todo-ai.diff_formatter')

  describe("create_header", function()
    it("should create pending header", function()
      local header = formatter.create_header("pending", "Test change")

      assert.is_table(header)
      assert.is_true(#header > 0)

      -- Check for status indicator
      local found_pending = false
      for _, part in ipairs(header) do
        if part[1]:find("PENDING") then
          found_pending = true
          break
        end
      end
      assert.is_true(found_pending)
    end)

    it("should create accepted header", function()
      local header = formatter.create_header("accepted", "Test change")

      assert.is_table(header)

      local found_accepted = false
      for _, part in ipairs(header) do
        if part[1]:find("ACCEPTED") then
          found_accepted = true
          break
        end
      end
      assert.is_true(found_accepted)
    end)

    it("should handle nil description", function()
      local header = formatter.create_header("pending", nil)

      assert.is_table(header)
      assert.is_true(#header > 0)
    end)
  end)

  describe("format_removed_lines", function()
    it("should format single line", function()
      local lines = {"removed line"}
      local formatted = formatter.format_removed_lines(lines)

      assert.equals(1, #formatted)
      assert.equals("- ", formatted[1][1][1])
      assert.equals("removed line", formatted[1][2][1])
    end)

    it("should format multiple lines", function()
      local lines = {"line1", "line2", "line3"}
      local formatted = formatter.format_removed_lines(lines)

      assert.equals(3, #formatted)
      for i, line in ipairs(formatted) do
        assert.equals("- ", line[1][1])
        assert.equals("line" .. i, line[2][1])
      end
    end)

    it("should handle empty lines array", function()
      local lines = {}
      local formatted = formatter.format_removed_lines(lines)

      assert.equals(0, #formatted)
    end)
  end)

  describe("create_line_highlight", function()
    it("should create add highlight", function()
      local extmark_opts, sign_opts = formatter.create_line_highlight("test line", "add")

      assert.is_not_nil(extmark_opts)
      assert.is_not_nil(sign_opts)
      assert.equals("DiffAdd", extmark_opts.hl_group)
      assert.equals("+", sign_opts.sign_text)
    end)

    it("should create delete highlight", function()
      local extmark_opts, sign_opts = formatter.create_line_highlight("test line", "delete")

      assert.is_not_nil(extmark_opts)
      assert.is_not_nil(sign_opts)
      assert.equals("DiffDelete", extmark_opts.hl_group)
      assert.equals("-", sign_opts.sign_text)
    end)
  end)
end)

describe("Integration tests", function()
  local search_replace = require('todo-ai.search_replace')
  local formatter = require('todo-ai.diff_formatter')

  it("should handle complete margarita to negroni transformation", function()
    local original = {
      "def get_margarita_ingredients():",
      '    return {"tequila": "2 oz", "lime": "1 oz"}',
      "",
      "def make_margarita():",
      "    return 'Shake with ice'"
    }

    local changes = {
      {
        search = table.concat({
          "def get_margarita_ingredients():",
          '    return {"tequila": "2 oz", "lime": "1 oz"}',
          "",
          "def make_margarita():",
          "    return 'Shake with ice'"
        }, "\n"),
        replace = table.concat({
          "def get_negroni_ingredients():",
          '    return {"gin": "1 oz", "campari": "1 oz"}',
          "",
          "def make_negroni():",
          "    return 'Stir with ice'"
        }, "\n"),
        description = "Transform to negroni"
      }
    }

    local result, count, err = search_replace.apply_changes(original, changes)

    assert.is_nil(err)
    assert.equals(1, count)
    assert.equals("def get_negroni_ingredients():", result[1])
    assert.equals("def make_negroni():", result[4])
  end)

  it("should handle large file efficiently", function()
    local lines = {}
    for i = 1, 1000 do
      table.insert(lines, "line " .. i)
    end

    local changes = {
      {search = "line 500", replace = "MODIFIED"},
      {search = "line 750", replace = "CHANGED"}
    }

    local start_time = vim.loop and vim.loop.now() or os.clock() * 1000
    local result, count, err = search_replace.apply_changes(lines, changes)
    local elapsed = (vim.loop and vim.loop.now() or os.clock() * 1000) - start_time

    assert.is_nil(err)
    assert.equals(2, count)
    assert.is_true(elapsed < 100) -- Should complete in under 100ms
  end)
end)