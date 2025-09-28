-- Integration test for visual mode with context
describe("Visual mode integration", function()
  local visual = require('todo-ai.visual')
  local init = require('todo-ai.init')
  local chat = require('todo-ai.chat')

  it("should handle full visual mode flow without errors", function()
    -- Create a test buffer
    local test_content = {
      "local function process_data(data)",
      "  for i, item in ipairs(data) do",
      "    print(item)",
      "  end",
      "end"
    }

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, test_content)
    vim.bo[buf].filetype = 'lua'
    local temp_name = '/tmp/integration_test.lua'
    vim.api.nvim_buf_set_name(buf, temp_name)
    vim.api.nvim_set_current_buf(buf)

    -- Set visual selection marks (select the for loop)
    vim.fn.setpos("'<", {buf, 2, 3, 0})
    vim.fn.setpos("'>", {buf, 4, 6, 0})

    -- Mock the gather_context to provide test context
    local original_gather = init.gather_context
    init.gather_context = function(bufnr, todo)
      return {
        file_content = table.concat(test_content, '\n'),
        file_path = temp_name,
        language = "lua",
        line_number = todo.line,
        end_line = todo.end_line,
        selected_text = todo.selected_text,
        cached_context = {
          project_name = "test_project",
          description = "Test project for integration testing"
        },
        other_buffers = {
          {filename = "main.lua", filetype = "lua", path = "/tmp/main.lua"},
          {filename = "config.json", filetype = "json", path = "/tmp/config.json"}
        }
      }
    end

    -- Mock chat functions
    local messages_sent = {}
    chat.add_message = function(sender, message)
      table.insert(messages_sent, {sender = sender, message = message})
    end

    chat.send_to_backend = function(message)
      table.insert(messages_sent, {sender = "backend", message = message})
    end

    -- Mock the open_chat to not actually open a window
    init.open_chat = function()
      -- Just create the buffer, don't open window
      init.state.chat_buf = chat.create()
    end

    -- Mock the input window to auto-complete
    visual.create_input_window = function(callback)
      -- Simulate user entering instruction
      vim.schedule(function()
        callback("convert to async iterator pattern")
      end)
    end

    -- Run the visual mode processing
    assert.has_no.errors(function()
      visual.process_visual_selection()
    end)

    -- Wait for async operations
    vim.wait(100)

    -- Verify the flow completed
    assert.is_not_nil(init.state.current_todo)
    assert.equals("convert to async iterator pattern", init.state.current_todo.instruction)
    assert.is_true(init.state.current_todo.is_visual)

    -- Verify message was sent with all context
    local backend_message = nil
    for _, msg in ipairs(messages_sent) do
      if msg.sender == "backend" then
        backend_message = msg.message
        break
      end
    end

    assert.is_not_nil(backend_message)

    -- Verify the message uses prompt builder format (SEARCH/REPLACE)
    assert.is_true(backend_message:match("SEARCH/REPLACE") ~= nil or backend_message:match("search") ~= nil)

    -- Verify file information is included
    assert.is_true(backend_message:match("integration_test.lua") ~= nil)

    -- Verify the important directive is there
    assert.is_true(backend_message:match('mode="changes"') ~= nil)
    assert.is_true(backend_message:match('filename="integration_test.lua"') ~= nil)

    -- Cleanup
    init.gather_context = original_gather
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, {force = true})
    end
    if init.state.chat_buf and vim.api.nvim_buf_is_valid(init.state.chat_buf) then
      vim.api.nvim_buf_delete(init.state.chat_buf, {force = true})
    end
  end)

  it("should handle chat window already existing", function()
    -- First create and open a chat
    init.state.chat_buf = chat.create()
    assert.is_not_nil(init.state.chat_buf)

    -- Create a test buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"test line"})
    vim.api.nvim_buf_set_name(buf, "/tmp/test2.lua")
    vim.api.nvim_set_current_buf(buf)

    -- Set visual selection
    vim.fn.setpos("'<", {buf, 1, 1, 0})
    vim.fn.setpos("'>", {buf, 1, 9, 0})

    -- Mock functions
    init.gather_context = function(bufnr, todo)
      return {
        file_content = "test line",
        file_path = "/tmp/test2.lua",
        language = "lua",
        line_number = 1,
        other_buffers = {}
      }
    end

    chat.send_to_backend = function(message)
      return true
    end

    chat.add_message = function(sender, message)
      return true
    end

    visual.create_input_window = function(callback)
      vim.schedule(function()
        callback("test")
      end)
    end

    -- This should not error even with chat already open
    assert.has_no.errors(function()
      visual.process_visual_selection()
    end)

    vim.wait(50)

    -- Cleanup
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, {force = true})
    end
    if init.state.chat_buf and vim.api.nvim_buf_is_valid(init.state.chat_buf) then
      vim.api.nvim_buf_delete(init.state.chat_buf, {force = true})
    end
  end)
end)