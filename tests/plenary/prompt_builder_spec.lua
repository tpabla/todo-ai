describe("prompt_builder", function()
  local prompt_builder = require("todo-ai.prompt_builder")
  local config = require("todo-ai.config")

  before_each(function()
    -- Setup config with defaults
    config.setup({
      timeouts = {
        llm_request = 300000,
        health_check = 5000,
        default = 30000
      }
    })
  end)

  describe("get_system_prompt", function()
    it("should include schema description", function()
      local prompt = prompt_builder.get_system_prompt()

      assert.is_string(prompt)
      assert.is_true(prompt:match("changes") ~= nil)
      assert.is_true(prompt:match("edits") ~= nil)
      assert.is_true(prompt:match("code_snippet") ~= nil)
    end)

    it("should include rules for TODO handling", function()
      local prompt = prompt_builder.get_system_prompt()

      assert.is_true(prompt:match("replacement code") ~= nil)
      assert.is_true(prompt:match("1%-indexed") ~= nil)
    end)

    it("should include examples", function()
      local prompt = prompt_builder.get_system_prompt()

      assert.is_true(prompt:match("multiple changes") ~= nil or
                    prompt:match("Examples") ~= nil)
    end)
  end)

  describe("build_user_prompt", function()
    it("should handle TODO mode with line number", function()
      local context = vim.fn.json_encode({
        file_path = "test.py",
        language = "python",
        file_content = "def test():\n    # TODO: implement\n    pass",
        line_number = 2,
        surrounding_lines = {}
      })

      local prompt = prompt_builder.build_user_prompt("implement test function", context)

      assert.is_string(prompt)
      assert.is_true(prompt:match("test.py") ~= nil)
      assert.is_true(prompt:match("python") ~= nil)
      assert.is_true(prompt:match("TODO at line 2") ~= nil)
      assert.is_true(prompt:match("implement test function") ~= nil)
    end)

    it("should handle visual selection mode", function()
      local context = vim.fn.json_encode({
        file_path = "test.js",
        language = "javascript",
        file_content = "full file content here",
        line_number = 5,
        end_line = 10,
        selected_text = "selected code block"
      })

      local prompt = prompt_builder.build_user_prompt("refactor this", context)

      assert.is_string(prompt)
      assert.is_true(prompt:match("Selected text") ~= nil or
                    prompt:match("lines 5%-10") ~= nil)
      assert.is_true(prompt:match("selected code block") ~= nil)
      assert.is_true(prompt:match("refactor this") ~= nil)
    end)

    it("should handle chat mode without line context", function()
      local context = "General context information"

      local prompt = prompt_builder.build_user_prompt("explain this concept", context)

      assert.is_string(prompt)
      assert.is_true(prompt:match("explain this concept") ~= nil)
      assert.is_true(prompt:match("General context information") ~= nil)
    end)

    it("should handle invalid JSON context gracefully", function()
      local context = "not valid json { broken"

      local prompt = prompt_builder.build_user_prompt("do something", context)

      assert.is_string(prompt)
      assert.is_true(prompt:match("do something") ~= nil)
      -- Should treat as plain text context
      assert.is_true(prompt:match("not valid json") ~= nil)
    end)
  end)

  describe("build_combined_prompt", function()
    it("should combine system and user prompts", function()
      local context = vim.fn.json_encode({
        file_path = "test.py",
        line_number = 5
      })

      local combined = prompt_builder.build_combined_prompt("fix bug", context)

      assert.is_string(combined)
      -- Should contain both system prompt elements
      assert.is_true(combined:match("JSON") ~= nil)
      assert.is_true(combined:match("changes") ~= nil)
      -- And user prompt elements
      assert.is_true(combined:match("fix bug") ~= nil)
      assert.is_true(combined:match("test.py") ~= nil)
    end)

    it("should work with simple text context", function()
      local combined = prompt_builder.build_combined_prompt(
        "write a function",
        "some context"
      )

      assert.is_string(combined)
      assert.is_true(combined:match("write a function") ~= nil)
      assert.is_true(combined:match("some context") ~= nil)
    end)
  end)

  describe("prompt optimization", function()
    it("should specify minimal data format in examples", function()
      local prompt = prompt_builder.get_system_prompt()

      -- Check that the prompt encourages minimal format
      assert.is_true(prompt:match("minimal") ~= nil or
                    prompt:match("efficient") ~= nil or
                    prompt:match("lines") ~= nil)
    end)

    it("should handle empty instruction gracefully", function()
      local context = vim.fn.json_encode({
        file_path = "test.py",
        line_number = 1
      })

      local prompt = prompt_builder.build_user_prompt("", context)

      assert.is_string(prompt)
      assert.is_true(prompt:match("test.py") ~= nil)
    end)
  end)
end)