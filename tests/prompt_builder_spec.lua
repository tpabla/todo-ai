-- Test suite for prompt builder with context support
describe("Prompt builder context", function()
  local prompt_builder = require('todo-ai.prompt_builder')

  describe("build_user_prompt with visual selection", function()
    it("should include project context when available", function()
      local context = {
        selected_text = "local x = 1",
        file_path = "/test/file.lua",
        language = "lua",
        file_content = "full file content",
        line_number = 5,
        end_line = 5,
        cached_context = {
          project_name = "test_project",
          dependencies = {"plenary.nvim"}
        },
        other_buffers = {
          {name = "other.lua", type = "lua"},
          {name = "test.py", type = "python"}
        }
      }

      local instruction = "make this async"
      local prompt = prompt_builder.build_user_prompt(instruction, vim.fn.json_encode(context))

      -- Verify prompt includes context
      assert.is_true(prompt:match("Project Context:") ~= nil)
      assert.is_true(prompt:match("test_project") ~= nil)
      assert.is_true(prompt:match("Other Open Files:") ~= nil)
      assert.is_true(prompt:match("other.lua") ~= nil)
      assert.is_true(prompt:match("test.py") ~= nil)

      -- Verify it still includes the main content
      assert.is_true(prompt:match("local x = 1") ~= nil)
      assert.is_true(prompt:match("make this async") ~= nil)
      assert.is_true(prompt:match("SEARCH/REPLACE format") ~= nil)
    end)

    it("should handle missing context fields gracefully", function()
      local context = {
        selected_text = "local x = 1",
        file_path = "/test/file.lua",
        language = "lua",
        file_content = "full file content",
        line_number = 5,
        end_line = 5
        -- No cached_context or other_buffers
      }

      local instruction = "test"
      local prompt = prompt_builder.build_user_prompt(instruction, vim.fn.json_encode(context))

      -- Should still work without optional context
      assert.is_not_nil(prompt)
      assert.is_true(prompt:match("local x = 1") ~= nil)

      -- Should not error on missing fields
      assert.is_true(prompt:match("Project Context:") == nil)
    end)
  end)

  describe("build_user_prompt with TODO mode", function()
    it("should include project context for TODO processing", function()
      local context = {
        file_path = "/test/file.lua",
        language = "lua",
        file_content = "function test()\n  -- TODO: @ai make async\n  return 1\nend",
        line_number = 2,
        surrounding_lines = {
          {line_number = 1, content = "function test()", is_target = false},
          {line_number = 2, content = "  -- TODO: @ai make async", is_target = true},
          {line_number = 3, content = "  return 1", is_target = false}
        },
        cached_context = {
          project_name = "test_project"
        },
        other_buffers = {
          {name = "helper.lua", type = "lua"}
        }
      }

      local instruction = "make async"
      local prompt = prompt_builder.build_user_prompt(instruction, vim.fn.json_encode(context))

      -- Verify context is included
      assert.is_true(prompt:match("Project Context:") ~= nil)
      assert.is_true(prompt:match("test_project") ~= nil)
      assert.is_true(prompt:match("Other Open Files:") ~= nil)
      assert.is_true(prompt:match("helper.lua") ~= nil)

      -- Verify TODO-specific content
      assert.is_true(prompt:match("TODO at line 2") ~= nil)
      assert.is_true(prompt:match("make async") ~= nil)
    end)
  end)

  describe("get_system_prompt", function()
    it("should use prompt_config for schema description", function()
      local system_prompt = prompt_builder.get_system_prompt()

      -- Should include mode detection rules
      assert.is_true(system_prompt:match('mode="changes"') ~= nil)
      assert.is_true(system_prompt:match('mode="chat"') ~= nil)

      -- Should include inference rules
      assert.is_true(system_prompt:match("intent to modify") ~= nil)
      assert.is_true(system_prompt:match("intent to understand") ~= nil)

      -- Should include filename field
      assert.is_true(system_prompt:match('"filename"') ~= nil)
    end)
  end)
end)