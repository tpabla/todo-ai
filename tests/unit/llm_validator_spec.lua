local runner = require('tests.test_runner')
local assert = runner.assert

-- Test suite for LLM validator
local suite = runner.describe("llm_validator")
local validator = require('todo-ai.llm_validator')

-- Test: validate_code_changes
runner.it(suite, "should validate code changes", function()
  -- Valid changes
  local valid_changes = {
    {
      start_line = 1,
      end_line = 5,
      code = "function test()\n  return true\nend",
      description = "Test function"
    }
  }

  local valid, err, fixed = validator.validate_code_changes(valid_changes)
  assert.truthy(valid, "Should validate correct changes")
  assert.is_nil(err, "Should have no errors")
end)

runner.it(suite, "should fix swapped line numbers", function()
  local invalid_changes = {
    {
      start_line = 10,
      end_line = 5,  -- End before start
      code = "test code"
    }
  }

  local valid, err, fixed = validator.validate_code_changes(invalid_changes)
  assert.falsy(valid, "Should detect invalid changes")
  assert.not_nil(fixed, "Should provide fixed changes")
  assert.equals(fixed[1].start_line, 5, "Should swap start line")
  assert.equals(fixed[1].end_line, 10, "Should swap end line")
end)

runner.it(suite, "should fix invalid line numbers", function()
  local invalid_changes = {
    {
      start_line = 0,  -- Invalid (< 1)
      end_line = 5,
      code = "test code"
    }
  }

  local valid, err, fixed = validator.validate_code_changes(invalid_changes)
  assert.falsy(valid, "Should detect invalid line number")
  assert.not_nil(fixed, "Should provide fixed changes")
  assert.equals(fixed[1].start_line, 1, "Should fix to valid line number")
end)

runner.it(suite, "should reject missing required fields", function()
  local invalid_changes = {
    {
      -- Missing start_line
      end_line = 5,
      code = "test"
    }
  }

  local valid, err = validator.validate_code_changes(invalid_changes)
  assert.falsy(valid, "Should reject missing fields")
  assert.truthy(err:match("missing or invalid start_line"), "Should report missing field")
end)

-- Test: validate_chat_response
runner.it(suite, "should validate chat responses", function()
  local valid_response = {
    content = "Here's the solution",
    explanation = "This fixes the issue",
    success = true
  }

  local valid, err, cleaned = validator.validate_chat_response(valid_response)
  assert.truthy(valid, "Should validate correct response")
  assert.not_nil(cleaned, "Should return cleaned response")
  assert.equals(cleaned.content, "Here's the solution")
end)

runner.it(suite, "should handle missing content gracefully", function()
  local response = {
    explanation = "Just an explanation"
  }

  local valid, err, cleaned = validator.validate_chat_response(response)
  assert.truthy(valid, "Should accept explanation without content")
  assert.equals(cleaned.explanation, "Just an explanation")
end)

runner.it(suite, "should sanitize injection attempts", function()
  local malicious_response = {
    content = "Good code\n:!rm -rf /\nMore code"
  }

  local valid, err, cleaned = validator.validate_chat_response(malicious_response)
  assert.truthy(valid, "Should process response")
  assert.falsy(cleaned.content:match(":!"), "Should remove vim command injection")
end)

-- Test: validate_diff
runner.it(suite, "should validate diff format", function()
  local valid_diff = [[
@@ -1,3 +1,3 @@
-old line
+new line
 context line]]

  local valid, err, fixed = validator.validate_diff(valid_diff)
  assert.truthy(valid, "Should validate correct diff")
end)

runner.it(suite, "should fix missing context prefixes", function()
  local invalid_diff = [[
@@ -1,3 +1,3 @@
-old line
+new line
context line without prefix]]

  local valid, err, fixed = validator.validate_diff(invalid_diff)
  assert.falsy(valid, "Should detect missing prefix")
  assert.not_nil(fixed, "Should provide fixed diff")
  assert.truthy(fixed:match(" context line"), "Should add space prefix")
end)

runner.it(suite, "should reject diff without header", function()
  local invalid_diff = [[
-old line
+new line]]

  local valid, err = validator.validate_diff(invalid_diff)
  assert.falsy(valid, "Should reject diff without header")
  assert.truthy(err:match("Missing diff header"))
end)

-- Test: validate_json
runner.it(suite, "should parse valid JSON", function()
  local valid_json = '{"key": "value", "number": 42}'

  local valid, data, err = validator.validate_json(valid_json)
  assert.truthy(valid, "Should parse valid JSON")
  assert.equals(data.key, "value")
  assert.equals(data.number, 42)
end)

runner.it(suite, "should fix common JSON issues", function()
  -- Trailing comma
  local json_with_comma = '{"key": "value",}'

  local valid, data, err = validator.validate_json(json_with_comma)
  assert.truthy(valid, "Should fix trailing comma")
  assert.equals(data.key, "value")

  -- Single quotes
  local json_with_single = "{'key': 'value'}"

  valid, data, err = validator.validate_json(json_with_single)
  assert.truthy(valid, "Should fix single quotes")
  assert.equals(data.key, "value")
end)

runner.it(suite, "should strip markdown code blocks", function()
  local json_in_markdown = [[```json
{"key": "value"}
```]]

  local valid, data, err = validator.validate_json(json_in_markdown)
  assert.truthy(valid, "Should strip markdown")
  assert.equals(data.key, "value")
end)

-- Test: validate_file_path
runner.it(suite, "should validate safe file paths", function()
  local valid, sanitized = validator.validate_file_path("src/module.lua")
  assert.truthy(valid, "Should accept safe path")
  assert.equals(sanitized, "src/module.lua")
end)

runner.it(suite, "should reject directory traversal", function()
  local valid, sanitized = validator.validate_file_path("../../etc/passwd")
  assert.truthy(valid, "Should process path")
  assert.equals(sanitized, "etc/passwd", "Should remove traversal")
end)

runner.it(suite, "should reject absolute paths", function()
  local valid, sanitized = validator.validate_file_path("/etc/passwd")
  assert.truthy(valid, "Should process path")
  assert.equals(sanitized, "etc/passwd", "Should remove absolute path")
end)

runner.it(suite, "should remove invalid characters", function()
  local valid, sanitized = validator.validate_file_path("file<>:\"|?*.txt")
  assert.truthy(valid, "Should process path")
  assert.equals(sanitized, "file.txt", "Should remove invalid chars")
end)

-- Test: validate_buffer_operation
runner.it(suite, "should validate buffer operations", function()
  -- Mock buffer
  local bufnr = 1
  local old_valid = vim.api.nvim_buf_is_valid
  local old_count = vim.api.nvim_buf_line_count

  vim.api.nvim_buf_is_valid = function(b) return b == bufnr end
  vim.api.nvim_buf_line_count = function(b) return 100 end

  -- Valid operation
  local valid, err = validator.validate_buffer_operation(bufnr, 10, 20)
  assert.truthy(valid, "Should validate valid operation")

  -- Invalid line range
  valid, err = validator.validate_buffer_operation(bufnr, 0, 20)
  assert.falsy(valid, "Should reject line < 1")

  valid, err = validator.validate_buffer_operation(bufnr, 10, 200)
  assert.falsy(valid, "Should reject line > buffer size")

  valid, err = validator.validate_buffer_operation(bufnr, 20, 10)
  assert.falsy(valid, "Should reject start > end")

  -- Restore
  vim.api.nvim_buf_is_valid = old_valid
  vim.api.nvim_buf_line_count = old_count
end)

-- Test: retry prompt creation
runner.it(suite, "should create retry prompts", function()
  local prompt = validator.create_retry_prompt(
    "Original request",
    "Line numbers invalid",
    1
  )

  assert.truthy(prompt:match("VALIDATION ERRORS"), "Should include error section")
  assert.truthy(prompt:match("Original request"), "Should include original")
  assert.truthy(prompt:match("Attempt 1/3"), "Should show attempt count")
end)

-- Test: custom validators
runner.it(suite, "should support custom validators", function()
  -- Register custom validator
  validator.register_validator("test_validator", function(data)
    if data.value > 10 then
      return false, "Value too large"
    end
    return true, nil
  end)

  -- Test it
  local valid, err = validator.run_validator("test_validator", {value = 5})
  assert.truthy(valid, "Should pass custom validation")

  valid, err = validator.run_validator("test_validator", {value = 15})
  assert.falsy(valid, "Should fail custom validation")
  assert.equals(err, "Value too large")
end)

return suite