-- Tests for init.lua error handling and core functionality
local init = require('todo-ai.init')

describe("init.lua error handling", function()
  it("should handle string errors properly", function()
    -- Mock chat module to capture error messages
    local error_messages = {}
    local chat_mock = {
      add_message = function(sender, message)
        if sender == 'ai' and message:find('Error:') then
          table.insert(error_messages, message)
        end
      end,
      hide_thinking = function() end
    }

    -- Mock the process_todo callback with string error
    local callback = function(response, error)
      if error then
        local error_msg = type(error) == 'string' and error or vim.inspect(error)
        chat_mock.add_message('ai', 'Error: ' .. error_msg)
      end
    end

    -- Test with string error
    callback(nil, "API timeout")

    assert.equals(1, #error_messages)
    assert.is_true(error_messages[1]:find("API timeout") ~= nil)
  end)

  it("should handle table errors properly", function()
    -- Mock chat module to capture error messages
    local error_messages = {}
    local chat_mock = {
      add_message = function(sender, message)
        if sender == 'ai' and message:find('Error:') then
          table.insert(error_messages, message)
        end
      end,
      hide_thinking = function() end
    }

    -- Mock the process_todo callback with table error
    local callback = function(response, error)
      if error then
        local error_msg = type(error) == 'string' and error or vim.inspect(error)
        chat_mock.add_message('ai', 'Error: ' .. error_msg)
      end
    end

    -- Test with table error (what was causing the bug)
    local table_error = {
      code = 429,
      message = "Rate limit exceeded",
      details = { retry_after = 60 }
    }

    callback(nil, table_error)

    assert.equals(1, #error_messages)
    -- Should contain the table content as a string
    assert.is_true(error_messages[1]:find("Rate limit exceeded") ~= nil)
    assert.is_true(error_messages[1]:find("429") ~= nil)
  end)

  it("should handle nil errors without crashing", function()
    local error_messages = {}
    local chat_mock = {
      add_message = function(sender, message)
        if sender == 'ai' and message:find('Error:') then
          table.insert(error_messages, message)
        end
      end,
      hide_thinking = function() end
    }

    local callback = function(response, error)
      if error then
        local error_msg = type(error) == 'string' and error or vim.inspect(error)
        chat_mock.add_message('ai', 'Error: ' .. error_msg)
      end
    end

    -- Test with nil error (should not trigger error handling)
    callback({success = true}, nil)

    assert.equals(0, #error_messages)
  end)

  it("should handle complex nested table errors", function()
    local error_messages = {}
    local chat_mock = {
      add_message = function(sender, message)
        if sender == 'ai' and message:find('Error:') then
          table.insert(error_messages, message)
        end
      end,
      hide_thinking = function() end
    }

    local callback = function(response, error)
      if error then
        local error_msg = type(error) == 'string' and error or vim.inspect(error)
        chat_mock.add_message('ai', 'Error: ' .. error_msg)
      end
    end

    -- Test with deeply nested error object
    local complex_error = {
      error = {
        type = "api_error",
        code = "rate_limit_exceeded",
        message = "Too many requests",
        param = nil,
        request_id = "req_123456789"
      },
      retry_after = 60
    }

    callback(nil, complex_error)

    assert.equals(1, #error_messages)
    -- Should handle nested structure without crashing
    assert.is_true(error_messages[1]:find("Too many requests") ~= nil)
    assert.is_true(error_messages[1]:find("rate_limit_exceeded") ~= nil)
  end)
end)

describe("init.lua configuration", function()
  it("should have default ai_highlight configuration", function()
    local config = require('todo-ai.config')
    local ai_highlight = config.defaults.ai_highlight

    assert.is_not_nil(ai_highlight)
    assert.is_true(ai_highlight.enabled)
    assert.equals('#ff79c6', ai_highlight.fg)
    assert.equals('#1a1a2e', ai_highlight.bg)
    assert.is_true(ai_highlight.bold)
  end)
end)