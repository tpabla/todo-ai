describe("schema", function()
  local schema = require("todo-ai.schema")

  describe("apply_changes", function()
    it("should apply single line replacement", function()
      local lines = {"line 1", "line 2", "line 3"}
      local changes = {
        {start_line = 2, end_line = 2, lines = {"new line 2"}}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "new line 2", "line 3"}, result)
    end)

    it("should handle multi-line replacement", function()
      local lines = {"line 1", "line 2", "line 3", "line 4"}
      local changes = {
        {start_line = 2, end_line = 3, lines = {"new line 2", "new line 3"}}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "new line 2", "new line 3", "line 4"}, result)
    end)

    it("should handle deletion when lines is empty", function()
      local lines = {"line 1", "TODO: remove this", "line 3"}
      local changes = {
        {start_line = 2, end_line = 2, lines = {}}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "line 3"}, result)
    end)

    it("should handle deletion when lines is nil", function()
      local lines = {"line 1", "TODO: remove this", "line 3"}
      local changes = {
        {start_line = 2, end_line = 2}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "line 3"}, result)
    end)

    it("should handle code field instead of lines", function()
      local lines = {"line 1", "line 2", "line 3"}
      local changes = {
        {start_line = 2, end_line = 2, code = "new line 2\nand another"}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "new line 2", "and another", "line 3"}, result)
    end)

    it("should apply multiple changes", function()
      local lines = {"line 1", "line 2", "line 3", "line 4", "line 5"}
      local changes = {
        {start_line = 2, end_line = 2, lines = {"changed 2"}},
        {start_line = 4, end_line = 5, lines = {"changed 4-5"}}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "changed 2", "line 3", "changed 4-5"}, result)
    end)

    it("should handle overlapping ranges correctly", function()
      local lines = {"line 1", "line 2", "line 3", "line 4"}
      local changes = {
        {start_line = 2, end_line = 3, lines = {"replacement"}}
      }

      local result = schema.apply_changes(lines, changes)

      assert.are.same({"line 1", "replacement", "line 4"}, result)
    end)
  end)

  describe("apply_edits", function()
    it("should apply single line edit", function()
      local lines = {"line 1", "line 2", "line 3"}
      local edits = {
        ["2"] = "edited line 2"
      }

      local result = schema.apply_edits(lines, edits)

      assert.are.same({"line 1", "edited line 2", "line 3"}, result)
    end)

    it("should delete line when edit is empty string", function()
      local lines = {"line 1", "line 2", "line 3"}
      local edits = {
        ["2"] = ""
      }

      local result = schema.apply_edits(lines, edits)

      assert.are.same({"line 1", "line 3"}, result)
    end)

    it("should apply multiple sparse edits", function()
      local lines = {"line 1", "line 2", "line 3", "line 4", "line 5"}
      local edits = {
        ["2"] = "edited 2",
        ["4"] = "",
        ["5"] = "edited 5"
      }

      local result = schema.apply_edits(lines, edits)

      assert.are.same({"line 1", "edited 2", "line 3", "edited 5"}, result)
    end)

    it("should add lines beyond buffer end", function()
      local lines = {"line 1", "line 2"}
      local edits = {
        ["5"] = "new line 5"
      }

      local result = schema.apply_edits(lines, edits)

      assert.are.same({"line 1", "line 2", "", "", "new line 5"}, result)
    end)

    it("should handle nil edits gracefully", function()
      local lines = {"line 1", "line 2"}

      local result = schema.apply_edits(lines, nil)

      assert.are.same({"line 1", "line 2"}, result)
    end)
  end)

  describe("create_minimal_change", function()
    it("should use lines array for single line", function()
      local change = schema.create_minimal_change(5, 5, "new content", "Fix bug")

      assert.are.equal(5, change.start_line)
      assert.are.equal(5, change.end_line)
      assert.are.same({"new content"}, change.lines)
      assert.are.equal("Fix bug", change.description)
    end)

    it("should use code field for multi-line", function()
      local code = "line 1\nline 2\nline 3"
      local change = schema.create_minimal_change(10, 12, code, "Add function")

      assert.are.equal(10, change.start_line)
      assert.are.equal(12, change.end_line)
      assert.are.equal(code, change.code)
      assert.are.equal("Add function", change.description)
    end)
  end)

  describe("schema examples", function()
    it("should have valid JSON in examples", function()
      for name, example in pairs(schema.examples) do
        local ok, decoded = pcall(vim.fn.json_decode, example)
        assert.is_true(ok, "Failed to decode example: " .. name)

        -- Check that examples follow the schema structure
        if decoded.changes then
          assert.is_table(decoded.changes)
          for _, change in ipairs(decoded.changes) do
            assert.is_number(change.start_line)
            assert.is_number(change.end_line)
            -- Should have either lines or code
            assert.is_true(change.lines ~= nil or change.code ~= nil or
                          (not change.lines and not change.code), -- deletion case
                          "Change must have lines, code, or neither (for deletion)")
          end
        end

        if decoded.edits then
          assert.is_table(decoded.edits)
        end
      end
    end)
  end)
end)