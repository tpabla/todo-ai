-- Tests for context_compact module using Plenary
local context = require('todo-ai.context_compact')

describe("context_compact", function()
  -- Store original directory
  local original_cwd

  before_each(function()
    -- Save current directory
    original_cwd = vim.fn.getcwd()
    -- Create temp test directory
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, 'p')
    vim.fn.chdir(test_dir)

    -- Clear any cached context
    context.cache = nil
  end)

  after_each(function()
    -- Restore original directory
    if original_cwd then
      vim.fn.chdir(original_cwd)
    end
  end)

  describe("generate_compact", function()
    it("should generate compact context without errors", function()
      local result = context.generate_compact()
      assert.is_not_nil(result)
      assert.is_string(result)
    end)

    it("should handle missing directories gracefully", function()
      -- Even in empty directory, should not error
      local result = context.generate_compact()
      assert.is_not_nil(result)
      assert.is_string(result)
    end)
  end)

  describe("generate_full", function()
    it("should generate full context with proper structure", function()
      local result = context.generate_full()
      assert.is_not_nil(result)
      assert.is_string(result)
      assert.has_match(result, "Project Context", "Should contain header")
    end)

    it("should include human notes section", function()
      local result = context.generate_full()
      assert.has_match(result, "HUMAN NOTES", "Should have human notes section")
    end)
  end)

  describe("encode_for_llm", function()
    it("should compress context for LLM", function()
      local input = [[
        This is a test
        <!-- Comment to remove -->


        Multiple    spaces    here
      ]]

      local encoded = context.encode_for_llm(input)
      assert.is_not_nil(encoded)
      assert.is_string(encoded)
      assert.does_not_match(encoded, "<!%-%-", "Should remove comments")
      assert.does_not_match(encoded, "\n\n\n", "Should remove excessive newlines")
    end)

    it("should enforce size limits", function()
      local large_input = string.rep("x", 10000)
      local encoded = context.encode_for_llm(large_input)
      assert.is_true(#encoded <= 2100, "Should limit encoded size")
    end)
  end)

  describe("parse_human_notes", function()
    it("should extract human notes from context", function()
      local content = [[
## HUMAN NOTES
This is a note
Another line

## PROJECT CONTEXT
Other content
]]
      local notes = context.parse_human_notes(content)
      assert.is_not_nil(notes)
      assert.has_match(notes, "This is a note", "Should contain note content")
      assert.does_not_match(notes, "PROJECT CONTEXT", "Should not include other sections")
    end)

    it("should handle missing notes section", function()
      local content = "## PROJECT CONTEXT\nSome content"
      local notes = context.parse_human_notes(content)
      assert.is_nil(notes)
    end)
  end)

  describe("file operations", function()
    it("should save context to file", function()
      -- Create .todoai directory
      vim.fn.mkdir('.todoai', 'p')

      local success = context.save()
      assert.is_true(success, "Should save successfully")

      -- Check file was created
      local file_exists = vim.fn.filereadable('.todoai/context.md') == 1
      assert.is_true(file_exists, "Context file should exist")
    end)

    it("should load existing context", function()
      -- Create test context file
      vim.fn.mkdir('.todoai', 'p')
      local test_content = "## PROJECT CONTEXT\nTest content"
      local file = io.open('.todoai/context.md', 'w')
      file:write(test_content)
      file:close()

      local loaded = context.load()
      assert.is_not_nil(loaded)
      assert.equals(loaded, test_content)
    end)

    it("should handle missing context file gracefully", function()
      local loaded = context.load()
      assert.is_nil(loaded)
    end)
  end)

  describe("system command handling", function()
    it("should handle various wc output formats", function()
      -- Create some test files
      vim.fn.writefile({'test'}, 'test.lua')
      vim.fn.writefile({'test'}, 'test.py')

      assert.does_not_error(function()
        local result = context.generate_compact()
        assert.is_not_nil(result)
      end)
    end)

    it("should handle git commands", function()
      -- Initialize git repo for testing
      vim.fn.system('git init')
      vim.fn.system('git config user.name "Test"')
      vim.fn.system('git config user.email "test@test.com"')

      local result = context.generate_compact()
      assert.is_not_nil(result)
      -- Might include git info if available
    end)
  end)

  describe("caching", function()
    it("should cache generated context", function()
      -- First generation
      local result1 = context.get_for_prompt()
      assert.is_not_nil(result1)

      -- Mark cache time
      local cache_time = context.last_generated

      -- Second generation should use cache
      local result2 = context.get_for_prompt()
      assert.equals(result1, result2)
      assert.equals(cache_time, context.last_generated, "Should not regenerate")
    end)

    it("should invalidate cache after TTL", function()
      -- Generate and cache
      local result1 = context.get_for_prompt()

      -- Force cache expiry
      context.last_generated = 0

      -- Should regenerate
      local result2 = context.get_for_prompt()
      assert.is_not_nil(result2)
      assert.is_true(context.last_generated > 0, "Should have new timestamp")
    end)
  end)
end)