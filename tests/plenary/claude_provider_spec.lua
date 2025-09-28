-- Tests for Claude provider callback signatures and response parsing
local claude = require('todo-ai.providers.claude')

describe("claude provider", function()
  local original_request_async
  local config = require('todo-ai.config')

  before_each(function()
    -- Setup config with timeouts
    config.setup({
      timeouts = {
        llm_request = 300000,
        health_check = 5000,
        default = 30000
      }
    })
    -- Mock the providers.request_async function
    original_request_async = require('todo-ai.providers').request_async
  end)

  after_each(function()
    -- Restore original function
    require('todo-ai.providers').request_async = original_request_async
  end)

  it("should handle successful response with changes", function()
    local callback_called = false
    local response_data, error_data = nil, nil

    -- Mock successful request with changes JSON
    require('todo-ai.providers').request_async = function(url, opts, callback)
      local mock_response = {
        content = {{
          text = '{\n  "changes": [\n    {\n      "start_line": 1,\n      "end_line": 10,\n      "code": "test code",\n      "description": "test change"\n    }\n  ],\n  "explanation": "test explanation"\n}',
          type = 'text'
        }}
      }
      callback(true, mock_response)
    end

    claude.complete_async('test instruction', 'test context', {}, function(response, error)
      callback_called = true
      response_data = response
      error_data = error
    end)

    assert.is_true(callback_called)
    assert.is_nil(error_data)
    assert.is_not_nil(response_data)
    assert.is_not_nil(response_data.changes)
    assert.equals(1, #response_data.changes)
    assert.equals("test code", response_data.changes[1].code)
  end)

  it("should handle API error responses", function()
    local callback_called = false
    local response_data, error_data = nil, nil

    -- Mock API error response
    require('todo-ai.providers').request_async = function(url, opts, callback)
      local mock_response = {
        error = {
          message = "Invalid API key"
        }
      }
      callback(true, mock_response)
    end

    claude.complete_async('test instruction', 'test context', {}, function(response, error)
      callback_called = true
      response_data = response
      error_data = error
    end)

    assert.is_true(callback_called)
    assert.is_nil(response_data)
    assert.is_not_nil(error_data)
    assert.matches("Claude API error:.*Invalid API key", error_data)
  end)

  it("should handle network/request errors", function()
    local callback_called = false
    local response_data, error_data = nil, nil

    -- Mock network error
    require('todo-ai.providers').request_async = function(url, opts, callback)
      callback(false, "Network timeout")
    end

    claude.complete_async('test instruction', 'test context', {}, function(response, error)
      callback_called = true
      response_data = response
      error_data = error
    end)

    assert.is_true(callback_called)
    assert.is_nil(response_data)
    assert.is_not_nil(error_data)
    assert.equals("Network timeout", error_data)
  end)

  it("should handle parser fallback for non-JSON content", function()
    local callback_called = false
    local response_data, error_data = nil, nil

    -- Mock response with invalid JSON (parser will treat as plain code)
    require('todo-ai.providers').request_async = function(url, opts, callback)
      local mock_response = {
        content = {{
          text = '{ invalid json',
          type = 'text'
        }}
      }
      callback(true, mock_response)
    end

    claude.complete_async('test instruction', 'test context', {}, function(response, error)
      callback_called = true
      response_data = response
      error_data = error
    end)

    assert.is_true(callback_called)
    assert.is_nil(error_data)
    assert.is_not_nil(response_data)
    -- Parser should treat invalid JSON as plain code
    assert.equals('plain_code', response_data.format_detected)
    assert.equals('{ invalid json', response_data.code)
  end)

  it("should handle missing content", function()
    local callback_called = false
    local response_data, error_data = nil, nil

    -- Mock response with no content
    require('todo-ai.providers').request_async = function(url, opts, callback)
      local mock_response = {
        content = {}
      }
      callback(true, mock_response)
    end

    claude.complete_async('test instruction', 'test context', {}, function(response, error)
      callback_called = true
      response_data = response
      error_data = error
    end)

    assert.is_true(callback_called)
    assert.is_nil(response_data)
    assert.is_not_nil(error_data)
    assert.matches("No content in response", error_data)
  end)

  it("should handle chat_async with same callback signature", function()
    local callback_called = false
    local response_data, error_data = nil, nil

    -- Mock successful chat response
    require('todo-ai.providers').request_async = function(url, opts, callback)
      local mock_response = {
        content = {{
          text = '{\n  "explanation": "Chat response",\n  "code_snippet": "print(\\"hello\\")"}\n}',
          type = 'text'
        }}
      }
      callback(true, mock_response)
    end

    local messages = {{role = 'user', content = 'test message'}}
    claude.chat_async(messages, {}, function(response, error)
      callback_called = true
      response_data = response
      error_data = error
    end)

    assert.is_true(callback_called)
    assert.is_nil(error_data)
    assert.is_not_nil(response_data)
  end)

  -- Integration test to ensure callback signature consistency
  it("should maintain consistent callback signatures across all async methods", function()
    local methods = {'complete_async', 'chat_async'}

    -- Mock API key to prevent early return
    local original_api_key = claude.api_key
    local original_env_key = vim.env.ANTHROPIC_API_KEY
    claude.api_key = 'test-api-key'
    vim.env.ANTHROPIC_API_KEY = 'test-api-key'

    for _, method_name in ipairs(methods) do
      local method = claude[method_name]
      assert.is_function(method, method_name .. " should be a function")

      -- Mock to capture callback signature
      local callback_args = {}
      local callback_called = false
      require('todo-ai.providers').request_async = function(url, opts, callback)
        -- Always call with success, simple response
        callback(true, {content = {{text = '{"explanation": "test"}', type = 'text'}}})
      end

      if method_name == 'chat_async' then
        method({{role = 'user', content = 'test'}}, {}, function(response, error)
          callback_called = true
          callback_args = {response, error}
        end)
      else
        method('test', 'test', {}, function(response, error)
          callback_called = true
          callback_args = {response, error}
        end)
      end

      assert.is_true(callback_called, method_name .. " callback should be called")
      -- On success: response should be table, error should be nil
      assert.is_table(callback_args[1], method_name .. " first arg should be response table on success")
      assert.is_nil(callback_args[2], method_name .. " second arg should be nil on success")
      -- Verify we actually got both arguments (even though table length is 1 due to trailing nil)
      assert.is_not_nil(callback_args[1], method_name .. " should have first argument")
      -- Second argument should exist but be nil
      assert.equals('nil', type(callback_args[2]), method_name .. " second arg should be nil type")
    end

    -- Restore original API key
    claude.api_key = original_api_key
    vim.env.ANTHROPIC_API_KEY = original_env_key
  end)
end)