-- Comprehensive test suite for visual mode functionality
describe("Visual mode functionality", function()
  local visual = require('todo-ai.visual')
  local init = require('todo-ai.init')
  local chat = require('todo-ai.chat')

  -- Helper to create a test buffer
  local function create_buffer(lines, filetype)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if filetype then
      vim.bo[buf].filetype = filetype
    end
    -- Set a name for the buffer
    local temp_name = '/tmp/test_file_' .. math.random(1000, 9999) .. '.lua'
    vim.api.nvim_buf_set_name(buf, temp_name)
    return buf
  end

  -- Helper to simulate visual selection
  local function simulate_visual_selection(buf, start_line, start_col, end_line, end_col)
    vim.api.nvim_set_current_buf(buf)
    -- Set visual marks
    vim.fn.setpos("'<", {buf, start_line, start_col, 0})
    vim.fn.setpos("'>", {buf, end_line, end_col, 0})
  end

  describe("get_visual_selection", function()
    it("should extract single line selection", function()
      local buf = create_buffer({"hello world", "test line", "another line"}, "lua")
      simulate_visual_selection(buf, 1, 1, 1, 5)

      local lines, start_line, end_line = visual.get_visual_selection()

      assert.is_not_nil(lines)
      assert.equals(1, start_line)
      assert.equals(1, end_line)
      assert.equals(1, #lines)
      assert.equals("hello", lines[1])

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should extract multi-line selection", function()
      local buf = create_buffer({"first line", "second line", "third line"}, "lua")
      simulate_visual_selection(buf, 1, 1, 3, 5)

      local lines, start_line, end_line = visual.get_visual_selection()

      assert.is_not_nil(lines)
      assert.equals(1, start_line)
      assert.equals(3, end_line)
      assert.equals(3, #lines)
      assert.equals("first line", lines[1])
      assert.equals("second line", lines[2])
      assert.equals("third", lines[3])

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should handle empty selection", function()
      local buf = create_buffer({"test"}, "lua")
      -- Don't set any visual marks

      local lines, start_line, end_line = visual.get_visual_selection()

      -- Should handle gracefully
      -- The function may return nil or empty based on implementation

      vim.api.nvim_buf_delete(buf, {force = true})
    end)
  end)

  describe("process_visual_selection", function()
    local original_gather_context
    local original_open_chat
    local original_send_to_backend
    local mock_context

    before_each(function()
      -- Mock the dependencies
      original_gather_context = init.gather_context
      original_open_chat = init.open_chat
      original_send_to_backend = chat.send_to_backend

      -- Create a mock context
      mock_context = {
        file_content = "full file content here",
        file_path = "/test/file.lua",
        language = "lua",
        line_number = 5,
        cached_context = {project = "test"},
        other_buffers = {
          {filename = "other.lua", filetype = "lua", content = "other content"}
        }
      }

      init.gather_context = function(bufnr, todo)
        return mock_context
      end

      init.open_chat = function()
        -- Mock chat opening
        return true
      end

      chat.send_to_backend = function(message)
        -- Capture the message for verification
        chat._test_last_message = message
        return true
      end

      chat.add_message = function(sender, message)
        -- Mock message adding
        chat._test_messages = chat._test_messages or {}
        table.insert(chat._test_messages, {sender = sender, message = message})
      end
    end)

    after_each(function()
      -- Restore original functions
      init.gather_context = original_gather_context
      init.open_chat = original_open_chat
      chat.send_to_backend = original_send_to_backend
      chat._test_last_message = nil
      chat._test_messages = nil
    end)

    it("should process selection and build proper context", function()
      local buf = create_buffer({
        "function test()",
        "  local x = 1",
        "  return x + 1",
        "end"
      }, "lua")

      simulate_visual_selection(buf, 2, 3, 3, 15)

      -- Mock the input window callback
      local input_callback = nil
      visual.create_input_window = function(callback)
        input_callback = callback
        -- Simulate user entering instruction
        vim.schedule(function()
          if input_callback then
            input_callback("make this async")
          end
        end)
      end

      -- Process the selection
      visual.process_visual_selection()

      -- Wait for scheduled functions
      vim.wait(50)

      -- Verify the todo was created correctly
      assert.is_not_nil(init.state.current_todo)
      assert.equals("make this async", init.state.current_todo.instruction)
      assert.equals(2, init.state.current_todo.line)
      assert.equals(3, init.state.current_todo.end_line)
      assert.is_true(init.state.current_todo.is_visual)

      -- Verify message was formatted correctly
      assert.is_not_nil(chat._test_last_message)
      assert.is_true(chat._test_last_message:match('mode="changes"') ~= nil)
      assert.is_true(chat._test_last_message:match('filename=') ~= nil)
      assert.is_true(chat._test_last_message:match('SEARCH/REPLACE format') ~= nil)

      -- Verify context was included
      assert.is_true(chat._test_last_message:match('Other Open Files:') ~= nil)
      assert.is_true(chat._test_last_message:match('other.lua') ~= nil)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should handle context with no cached_context", function()
      mock_context.cached_context = nil

      local buf = create_buffer({"test line"}, "lua")
      simulate_visual_selection(buf, 1, 1, 1, 9)

      -- Mock the input window
      visual.create_input_window = function(callback)
        vim.schedule(function()
          callback("test instruction")
        end)
      end

      visual.process_visual_selection()
      vim.wait(50)

      -- Should still work without cached context
      assert.is_not_nil(chat._test_last_message)
      -- Project Context should not be in message if nil
      assert.is_true(chat._test_last_message:match('Project Context:') == nil)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)

    it("should handle context with no other_buffers", function()
      mock_context.other_buffers = {}

      local buf = create_buffer({"test line"}, "lua")
      simulate_visual_selection(buf, 1, 1, 1, 9)

      visual.create_input_window = function(callback)
        vim.schedule(function()
          callback("test instruction")
        end)
      end

      visual.process_visual_selection()
      vim.wait(50)

      assert.is_not_nil(chat._test_last_message)
      -- Should still mention Other Open Files but list should be empty
      assert.is_true(chat._test_last_message:match('Other Open Files:') ~= nil)

      vim.api.nvim_buf_delete(buf, {force = true})
    end)
  end)

  describe("chat window interaction", function()
    it("should handle existing chat window", function()
      -- First create a chat window
      local chat_buf = chat.create()
      assert.is_not_nil(chat_buf)
      assert.is_true(vim.api.nvim_buf_is_valid(chat_buf))

      -- Try to create another one - should reuse existing
      local second_buf = chat.create()
      assert.equals(chat_buf, second_buf)

      -- Clean up
      if vim.api.nvim_buf_is_valid(chat_buf) then
        vim.api.nvim_buf_delete(chat_buf, {force = true})
      end
    end)

    it("should not error when chat window already exists", function()
      -- Create initial chat
      local chat_buf = chat.create()

      -- Open it
      init.open_chat()

      -- Try to open again - should not error
      assert.has_no.errors(function()
        init.open_chat()
      end)

      -- Clean up
      if vim.api.nvim_buf_is_valid(chat_buf) then
        vim.api.nvim_buf_delete(chat_buf, {force = true})
      end
    end)
  end)

  describe("input window", function()
    it("should create floating window with correct options", function()
      local callback_called = false
      local callback_value = nil

      visual.create_input_window(function(instruction)
        callback_called = true
        callback_value = instruction
      end)

      -- Check that a floating window was created
      local wins = vim.api.nvim_list_wins()
      local float_win = nil
      for _, win in ipairs(wins) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= '' then
          float_win = win
          break
        end
      end

      assert.is_not_nil(float_win)

      -- Check window configuration
      local config = vim.api.nvim_win_get_config(float_win)
      assert.equals('editor', config.relative)
      assert.equals(' TODO: @ai ', config.title)
      assert.equals('center', config.title_pos)

      -- Clean up
      vim.api.nvim_win_close(float_win, true)
    end)
  end)
end)