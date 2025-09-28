-- Test suite for unified prompt generation system
describe("Unified prompt system", function()
  local unified = require('todo-ai.unified_prompt')
  local chat = require('todo-ai.chat')
  local init = require('todo-ai.init')

  -- Mock providers
  local mock_provider = {
    complete_async = function(instruction, context, opts, callback)
      -- Simulate successful response with changes
      vim.schedule(function()
        callback({
          mode = "changes",
          changes = {{
            search = "old code",
            replace = "new code",
            description = "Test change"
          }},
          explanation = "Test explanation",
          filename = "test.lua"
        }, nil)
      end)
    end
  }

  before_each(function()
    -- Setup mock provider
    local providers = require('todo-ai.providers')
    providers._providers = {test = mock_provider}
    providers._initialized = true

    -- Mock config
    local config = require('todo-ai.config')
    config.get = function(key)
      if key == 'provider' then return 'test' end
      if key == 'model' then return 'test-model' end
      if key == 'temperature' then return 0.7 end
      return nil
    end

    -- Mock chat functions
    chat.add_message = function() end
    chat.show_thinking = function() end
    chat.hide_thinking = function() end

    -- Mock init functions
    init.open_chat = function() end
    init.state = {}
  end)

  describe("create_context", function()
    it("should create TODO context correctly", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "function test()",
        "  -- TODO: @ai make async",
        "  return 1",
        "end"
      })
      vim.bo[buf].filetype = 'lua'

      local context = unified.create_context({
        mode = 'todo',
        bufnr = buf,
        instruction = "make async",
        line_number = 2
      })

      assert.equals('todo', context.mode)
      assert.equals('make async', context.instruction)
      assert.equals(2, context.line_number)
      assert.equals('lua', context.language)
      assert.is_true(context.is_todo)
      assert.is_not_nil(context.surrounding_lines)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should create visual context correctly", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "function test()",
        "  local x = 1",
        "  return x",
        "end"
      })
      vim.bo[buf].filetype = 'lua'

      local context = unified.create_context({
        mode = 'visual',
        bufnr = buf,
        instruction = "optimize this",
        selected_text = "  local x = 1\n  return x",
        start_line = 2,
        end_line = 3
      })

      assert.equals('visual', context.mode)
      assert.equals('optimize this', context.instruction)
      assert.equals("  local x = 1\n  return x", context.selected_text)
      assert.equals(2, context.line_number)
      assert.equals(3, context.end_line)
      assert.is_true(context.is_visual)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should create chat context correctly", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"test content"})

      local context = unified.create_context({
        mode = 'chat',
        bufnr = buf,
        instruction = "explain this code"
      })

      assert.equals('chat', context.mode)
      assert.equals('explain this code', context.instruction)
      assert.is_true(context.is_chat)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should enrich context with project information", function()
      local buf = vim.api.nvim_create_buf(false, true)

      local context = unified.create_context({
        mode = 'todo',
        bufnr = buf,
        instruction = "test",
        line_number = 1
      })

      -- Should have project enrichment fields
      assert.is_not_nil(context.project_root)
      assert.is_not_nil(context.other_buffers)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)
  end)

  describe("build_complete_prompt", function()
    it("should build prompt with system and user parts", function()
      local context = {
        instruction = "test instruction",
        file_content = "test content",
        file_path = "/test.lua",
        filename = "test.lua",
        language = "lua",
        is_todo = true,
        line_number = 1
      }

      local prompts = unified.build_complete_prompt(context)

      assert.is_not_nil(prompts.system)
      assert.is_not_nil(prompts.user)
      assert.is_not_nil(prompts.full)

      -- System prompt should include schema
      assert.is_true(prompts.system:match('mode="changes"') ~= nil)
      assert.is_true(prompts.system:match('mode="chat"') ~= nil)

      -- User prompt should include instruction
      assert.is_true(prompts.user:match('test instruction') ~= nil)
    end)

    it("should add visual mode hints", function()
      local context = {
        instruction = "optimize",
        selected_text = "code",
        filename = "test.lua",
        is_visual = true,
        file_content = "full content",
        language = "lua"
      }

      local prompts = unified.build_complete_prompt(context)

      -- Should have visual mode directive
      assert.is_true(prompts.user:match('mode="changes"') ~= nil)
      assert.is_true(prompts.user:match('filename="test.lua"') ~= nil)
    end)
  end)

  describe("send_to_provider", function()
    it("should use complete_async when available", function(done)
      local context = {
        instruction = "test",
        file_content = "content",
        language = "lua"
      }

      local called = false
      mock_provider.complete_async = function(instruction, ctx, opts, callback)
        called = true
        assert.equals("test", instruction)
        assert.is_not_nil(ctx)
        callback({mode = "changes", changes = {}}, nil)
      end

      unified.send_to_provider(context, function(response, error)
        assert.is_true(called)
        assert.is_nil(error)
        assert.equals("changes", response.mode)
        done()
      end)
    end)

    it("should fall back to chat_async", function(done)
      mock_provider.complete_async = nil
      mock_provider.chat_async = function(messages, opts, callback)
        assert.equals(2, #messages)
        assert.equals("system", messages[1].role)
        assert.equals("user", messages[2].role)
        callback({mode = "chat", explanation = "test"}, nil)
      end

      local context = {
        instruction = "test",
        file_content = "content",
        language = "lua"
      }

      unified.send_to_provider(context, function(response, error)
        assert.is_nil(error)
        assert.equals("chat", response.mode)
        done()
      end)
    end)
  end)

  describe("handle_response", function()
    it("should handle changes mode response", function()
      local diff_native = require('todo-ai.diff_native')
      local show_called = false
      diff_native.show_response = function(buf, response)
        show_called = true
      end

      local response = {
        mode = "changes",
        changes = {{search = "old", replace = "new"}},
        explanation = "Test"
      }

      local context = {bufnr = vim.api.nvim_create_buf(false, true)}

      unified.handle_response(response, nil, context)

      assert.is_true(show_called)

      vim.api.nvim_buf_delete(context.bufnr, {force = true})
    end)

    it("should handle chat mode response", function()
      local messages = {}
      chat.add_message = function(role, content)
        table.insert(messages, {role = role, content = content})
      end

      local response = {
        mode = "chat",
        explanation = "This is a chat response"
      }

      unified.handle_response(response, nil, {})

      assert.equals(1, #messages)
      assert.equals("ai", messages[1].role)
      assert.equals("This is a chat response", messages[1].content)
    end)

    it("should handle errors", function()
      local messages = {}
      chat.add_message = function(role, content)
        table.insert(messages, {role = role, content = content})
      end

      unified.handle_response(nil, "Test error", {})

      assert.equals(1, #messages)
      assert.is_true(messages[1].content:match("Test error") ~= nil)
    end)
  end)

  describe("process functions", function()
    it("should process TODO correctly", function()
      local todo = {
        instruction = "make async",
        line = 2,
        full_line = "-- TODO: @ai make async"
      }
      local buf = vim.api.nvim_create_buf(false, true)

      -- Should not error
      assert.has_no.errors(function()
        unified.process_todo(todo, buf)
      end)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should process visual selection correctly", function()
      local buf = vim.api.nvim_create_buf(false, true)

      assert.has_no.errors(function()
        unified.process_visual(
          "optimize",
          "selected code",
          1, 3,
          buf
        )
      end)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should process chat message correctly", function()
      assert.has_no.errors(function()
        unified.process_chat_message("explain this code")
      end)
    end)
  end)
end)