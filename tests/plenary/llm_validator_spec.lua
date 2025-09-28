-- Tests for LLM validator module using Plenary
local validator = require('todo-ai.llm_validator')

describe("llm_validator", function()
  describe("code changes validation", function()
    it("should validate correct code changes", function()
      local valid_changes = {
        {
          start_line = 1,
          end_line = 5,
          code = "function test()\n  return true\nend",
          description = "Test function"
        }
      }

      local valid, err, fixed = validator.validate_code_changes(valid_changes)
      assert.is_true(valid, "Should validate correct changes")
      assert.is_nil(err, "Should have no errors")
    end)

    it("should fix swapped line numbers", function()
      local invalid_changes = {
        {
          start_line = 10,
          end_line = 5,  -- End before start
          code = "test code"
        }
      }

      local valid, err, fixed = validator.validate_code_changes(invalid_changes)
      assert.is_false(valid, "Should detect invalid changes")
      assert.is_not_nil(fixed, "Should provide fixed changes")
      assert.equals(5, fixed[1].start_line, "Should swap start line")
      assert.equals(10, fixed[1].end_line, "Should swap end line")
    end)

    it("should fix invalid line numbers", function()
      local invalid_changes = {
        {
          start_line = 0,  -- Invalid (< 1)
          end_line = 5,
          code = "test code"
        }
      }

      local valid, err, fixed = validator.validate_code_changes(invalid_changes)
      assert.is_false(valid, "Should detect invalid line number")
      assert.is_not_nil(fixed, "Should provide fixed changes")
      assert.equals(1, fixed[1].start_line, "Should fix to valid line number")
    end)

    it("should reject missing required fields", function()
      local invalid_changes = {
        {
          -- Missing start_line
          end_line = 5,
          code = "test"
        }
      }

      local valid, err = validator.validate_code_changes(invalid_changes)
      assert.is_false(valid, "Should reject missing fields")
      assert.has_match(err, "missing or invalid start_line", "Should report missing field")
    end)

    it("should reject overly large code", function()
      local huge_code = string.rep("x", 100001)
      local changes = {
        {
          start_line = 1,
          end_line = 2,
          code = huge_code
        }
      }

      local valid, err = validator.validate_code_changes(changes)
      assert.is_false(valid, "Should reject huge code")
      assert.has_match(err, "too large", "Should mention size issue")
    end)
  end)

  describe("chat response validation", function()
    it("should validate correct responses", function()
      local valid_response = {
        content = "Here's the solution",
        explanation = "This fixes the issue",
        success = true
      }

      local valid, err, cleaned = validator.validate_chat_response(valid_response)
      assert.is_true(valid, "Should validate correct response")
      assert.is_not_nil(cleaned, "Should return cleaned response")
      assert.equals("Here's the solution", cleaned.content)
    end)

    it("should handle missing content gracefully", function()
      local response = {
        explanation = "Just an explanation"
      }

      local valid, err, cleaned = validator.validate_chat_response(response)
      assert.is_true(valid, "Should accept explanation without content")
      assert.equals("Just an explanation", cleaned.explanation)
    end)

    it("should sanitize injection attempts", function()
      local malicious_response = {
        content = "Good code\n:!rm -rf /\nMore code"
      }

      local valid, err, cleaned = validator.validate_chat_response(malicious_response)
      assert.is_true(valid, "Should process response")
      assert.does_not_match(cleaned.content, ":!", "Should remove vim command injection")
    end)

    it("should handle non-string content", function()
      local response = {
        content = 12345  -- Number instead of string
      }

      local valid, err, cleaned = validator.validate_chat_response(response)
      assert.is_true(valid, "Should handle non-string content")
      assert.equals("12345", cleaned.content, "Should convert to string")
    end)
  end)

  describe("diff validation", function()
    it("should validate correct diff format", function()
      local valid_diff = [[
@@ -1,3 +1,3 @@
-old line
+new line
 context line]]

      local valid, err, fixed = validator.validate_diff(valid_diff)
      assert.is_true(valid, "Should validate correct diff")
    end)

    it("should fix missing context prefixes", function()
      local invalid_diff = [[
@@ -1,3 +1,3 @@
-old line
+new line
context line without prefix]]

      local valid, err, fixed = validator.validate_diff(invalid_diff)
      assert.is_false(valid, "Should detect missing prefix")
      assert.is_not_nil(fixed, "Should provide fixed diff")
      assert.has_match(fixed, " context line", "Should add space prefix")
    end)

    it("should reject diff without header", function()
      local invalid_diff = [[
-old line
+new line]]

      local valid, err = validator.validate_diff(invalid_diff)
      assert.is_false(valid, "Should reject diff without header")
      assert.has_match(err, "Missing diff header")
    end)
  end)

  describe("JSON validation", function()
    it("should parse valid JSON", function()
      local valid_json = '{"key": "value", "number": 42}'

      local valid, data, err = validator.validate_json(valid_json)
      assert.is_true(valid, "Should parse valid JSON")
      assert.equals("value", data.key)
      assert.equals(42, data.number)
    end)

    it("should fix trailing commas", function()
      local json_with_comma = '{"key": "value",}'

      local valid, data, err = validator.validate_json(json_with_comma)
      assert.is_true(valid, "Should fix trailing comma")
      assert.equals("value", data.key)
    end)

    it("should fix single quotes", function()
      local json_with_single = "{'key': 'value'}"

      local valid, data, err = validator.validate_json(json_with_single)
      assert.is_true(valid, "Should fix single quotes")
      assert.equals("value", data.key)
    end)

    it("should strip markdown code blocks", function()
      local json_in_markdown = [[```json
{"key": "value"}
```]]

      local valid, data, err = validator.validate_json(json_in_markdown)
      assert.is_true(valid, "Should strip markdown")
      assert.equals("value", data.key)
    end)
  end)

  describe("file path validation", function()
    it("should validate safe file paths", function()
      local valid, sanitized = validator.validate_file_path("src/module.lua")
      assert.is_true(valid, "Should accept safe path")
      assert.equals("src/module.lua", sanitized)
    end)

    it("should remove directory traversal", function()
      local valid, sanitized = validator.validate_file_path("../../etc/passwd")
      assert.is_true(valid, "Should process path")
      assert.equals("etc/passwd", sanitized, "Should remove traversal")
    end)

    it("should remove absolute paths", function()
      local valid, sanitized = validator.validate_file_path("/etc/passwd")
      assert.is_true(valid, "Should process path")
      assert.equals("etc/passwd", sanitized, "Should remove absolute path")
    end)

    it("should remove invalid characters", function()
      local valid, sanitized = validator.validate_file_path("file<>:\"|?*.txt")
      assert.is_true(valid, "Should process path")
      assert.equals("file.txt", sanitized, "Should remove invalid chars")
    end)

    it("should reject overly long paths", function()
      local long_path = string.rep("a", 256)
      local valid = validator.validate_file_path(long_path)
      assert.is_false(valid, "Should reject long paths")
    end)
  end)

  describe("buffer operations validation", function()
    it("should validate correct buffer operations", function()
      -- Create a real buffer for testing
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
        "line 4",
        "line 5"
      })

      local valid, err = validator.validate_buffer_operation(bufnr, 2, 4)
      assert.is_true(valid, "Should validate valid operation")

      -- Clean up
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)

    it("should reject invalid buffer", function()
      local valid, err = validator.validate_buffer_operation(99999, 1, 5)
      assert.is_false(valid, "Should reject invalid buffer")
      assert.equals("Invalid buffer", err)
    end)

    it("should reject out of range lines", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"line1", "line2"})

      local valid, err = validator.validate_buffer_operation(bufnr, 1, 10)
      assert.is_false(valid, "Should reject out of range")
      assert.has_match(err, "exceeds buffer lines")

      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)

    it("should reject inverted line ranges", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"line1", "line2", "line3"})

      local valid, err = validator.validate_buffer_operation(bufnr, 3, 1)
      assert.is_false(valid, "Should reject inverted range")
      assert.equals("start_line > end_line", err)

      vim.api.nvim_buf_delete(bufnr, {force = true})
    end)
  end)

  describe("retry prompts", function()
    it("should create proper retry prompts", function()
      local prompt = validator.create_retry_prompt(
        "Original request",
        "Line numbers invalid",
        1
      )

      assert.has_match(prompt, "VALIDATION ERRORS", "Should include error section")
      assert.has_match(prompt, "Original request", "Should include original")
      assert.has_match(prompt, "Attempt 1/3", "Should show attempt count")
    end)
  end)

  describe("custom validators", function()
    it("should support custom validators", function()
      -- Register custom validator
      validator.register_validator("test_validator", function(data)
        if data.value > 10 then
          return false, "Value too large"
        end
        return true, nil
      end)

      -- Test passing validation
      local valid, err = validator.run_validator("test_validator", {value = 5})
      assert.is_true(valid, "Should pass custom validation")

      -- Test failing validation
      valid, err = validator.run_validator("test_validator", {value = 15})
      assert.is_false(valid, "Should fail custom validation")
      assert.equals("Value too large", err)
    end)

    it("should handle missing validators gracefully", function()
      local valid, err = validator.run_validator("nonexistent", {})
      assert.is_true(valid, "Should pass when no validator exists")
      assert.is_nil(err)
    end)
  end)
end)