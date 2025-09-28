-- Integration tests for todo-ai plugin

local runner = require('test.test_runner')

-- Setup more complete vim mock for integration tests
runner.mock_vim()

-- Additional mocks for integration
vim.env = {
  ANTHROPIC_API_KEY = "test_key",
  OPENAI_API_KEY = "test_key",
}

vim.bo = setmetatable({}, {
  __index = function(t, bufnr)
    return setmetatable({}, {
      __index = function(tt, key)
        if key == 'filetype' then
          return 'lua'
        elseif key == 'modified' then
          return false
        elseif key == 'buflisted' then
          return true
        end
        return nil
      end,
      __newindex = function(tt, key, value)
        -- Store values
      end
    })
  end
})

-- Mock jobstart for async operations
vim.fn.jobstart = function(cmd, opts)
  -- Simulate successful response
  if opts and opts.on_stdout then
    vim.defer_fn(function()
      opts.on_stdout(1, {'{"changes": [], "explanation": "test"}'}, "stdout")
    end, 10)
  end
  if opts and opts.on_exit then
    vim.defer_fn(function()
      opts.on_exit(1, 0, "exit")
    end, 20)
  end
  return 1
end

runner.suite('Integration', {
  before_all = function()
    -- Load all modules
    package.loaded['todo-ai.logger'] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }
  end,

  ['test_provider_initialization'] = function()
    local providers = require('lua.todo-ai.providers')
    assert_not_nil(providers)

    -- Check provider registration
    local claude = providers.get('claude')
    assert_not_nil(claude, "Claude provider should be registered")

    local openai = providers.get('openai')
    assert_not_nil(openai, "OpenAI provider should be registered")
  end,

  ['test_config_loading'] = function()
    local config = require('lua.todo-ai.config')
    assert_not_nil(config)

    -- Test default values
    local provider = config.get('provider')
    assert_eq(provider, 'claude', "Default provider should be claude")

    local model = config.get('model')
    assert_type(model, 'string', "Model should be a string")

    -- Test setting values
    config.set('temperature', 0.5)
    assert_eq(config.get('temperature'), 0.5)
  end,

  ['test_schema_validation'] = function()
    local schema = require('lua.todo-ai.schema')
    assert_not_nil(schema.response_schema)

    -- Validate schema structure
    local props = schema.response_schema.properties
    assert_not_nil(props.changes)
    assert_not_nil(props.code_snippet)
    assert_not_nil(props.explanation)
  end,

  ['test_parser_integration'] = function()
    local parser = require('lua.todo-ai.parser')

    -- Test parsing valid response
    local response = [[{
      "changes": [
        {
          "start_line": 10,
          "end_line": 20,
          "code": "function test() return true end",
          "description": "Test function"
        }
      ],
      "explanation": "Added test function"
    }]]

    local result = parser.parse(response, 'claude')
    assert_not_nil(result.changes)
    assert_eq(#result.changes, 1)
    assert_eq(result.changes[1].start_line, 10)
  end,

  ['test_utils_integration'] = function()
    local utils = require('lua.todo-ai.utils')

    -- Test buffer validation
    local ok, err = utils.validate_buffer(1)
    assert_true(ok)

    -- Test JSON operations
    local data = {test = true, nested = {value = 123}}
    local json, err = utils.safe_json_encode(data)
    assert_not_nil(json)
    assert_nil(err)

    local decoded, err = utils.safe_json_decode(json)
    assert_not_nil(decoded)
    assert_eq(decoded.test, true)
    assert_eq(decoded.nested.value, 123)
  end,

  ['test_diff_module'] = function()
    local diff = require('lua.todo-ai.diff')
    assert_not_nil(diff)

    -- Test state initialization
    assert_type(diff.state, 'table')

    -- Test clean_code_block
    local cleaned = diff.clean_code_block('```lua\ncode\n```')
    assert_eq(cleaned, 'code')
  end,

  ['test_visual_module'] = function()
    local visual = require('lua.todo-ai.visual')
    assert_not_nil(visual)

    -- Test get_visual_selection with mock
    vim.fn.getpos = function(mark)
      if mark == "'<" then
        return {0, 1, 1, 0}
      elseif mark == "'>" then
        return {0, 5, 10, 0}
      end
    end

    vim.api.nvim_buf_get_lines = function(bufnr, start_line, end_line, strict)
      return {
        "line 1",
        "line 2",
        "line 3",
        "line 4",
        "line 5"
      }
    end

    local lines, start_line, end_line = visual.get_visual_selection()
    assert_not_nil(lines)
    assert_eq(start_line, 1)
    assert_eq(end_line, 5)
  end,

  ['test_chat_module'] = function()
    local chat = require('lua.todo-ai.chat')
    assert_not_nil(chat)

    -- Test state initialization
    assert_type(chat.state, 'table')
    assert_type(chat.state.messages, 'table')

    -- Test add_message
    chat.add_message('user', 'test message')
    assert_true(#chat.state.messages > 0)
  end,

  ['test_provider_request'] = function()
    local providers = require('lua.todo-ai.providers')

    -- Mock curl command
    local original_system = vim.fn.system
    vim.fn.system = function(cmd)
      if type(cmd) == 'table' and cmd[1] == 'curl' then
        return '{"changes": [], "explanation": "test response"}'
      end
      return original_system(cmd)
    end

    -- Test synchronous request
    local response, err = providers.request('http://test.com', {
      method = 'POST',
      headers = {},
      body = '{}',
    })

    assert_not_nil(response)
    assert_nil(err)

    -- Restore
    vim.fn.system = original_system
  end,

  ['test_error_handling'] = function()
    local utils = require('lua.todo-ai.utils')

    -- Test various error scenarios
    local ok, err = utils.validate_buffer(nil)
    assert_false(ok)
    assert_not_nil(err)

    ok, err = utils.validate_line_range(1, 0, 10)
    assert_false(ok)
    assert_not_nil(err)

    ok, err = utils.safe_json_decode('invalid json')
    assert_nil(ok)
    assert_not_nil(err)
  end,

  ['test_claude_provider_prompt'] = function()
    local claude = require('lua.todo-ai.providers.claude')

    -- Test system prompt generation
    local system_prompt = claude.get_system_prompt()
    assert_type(system_prompt, 'string')
    assert_true(system_prompt:match('changes'))
    assert_true(system_prompt:match('JSON'))

    -- Test build_prompt for different contexts
    local context = {
      file_path = 'test.lua',
      language = 'lua',
      file_content = '-- test file',
      line_number = 10,
      selected_text = 'selected code'
    }

    local prompt = claude.build_prompt('Fix this', vim.fn.json_encode(context))
    assert_type(prompt, 'string')
    assert_true(prompt:match('test.lua'))
    assert_true(prompt:match('selected code'))
  end,

  ['test_openai_provider'] = function()
    local openai = require('lua.todo-ai.providers.openai')
    assert_not_nil(openai)

    -- Test configuration
    assert_type(openai.api_url, 'string')
    assert_type(openai.default_model, 'string')
  end,

  ['test_ollama_provider'] = function()
    local ollama = require('lua.todo-ai.providers.ollama')
    assert_not_nil(ollama)

    -- Test configuration
    assert_type(ollama.api_url, 'string')
    assert_type(ollama.default_model, 'string')
  end,

  ['test_config_persistence'] = function()
    local config = require('lua.todo-ai.config')

    -- Set and get multiple values
    config.set('test_key', 'test_value')
    assert_eq(config.get('test_key'), 'test_value')

    config.set('nested', {key = 'value'})
    local nested = config.get('nested')
    assert_eq(nested.key, 'value')
  end,

  ['test_safe_callback_wrapper'] = function()
    local utils = require('lua.todo-ai.utils')

    local called = false
    local error_handled = false

    -- Test successful callback
    local cb = utils.safe_callback(function()
      called = true
      return 'success'
    end)

    local result = cb()
    assert_true(called)
    assert_eq(result, 'success')

    -- Test error handling
    cb = utils.safe_callback(
      function() error("test error") end,
      function(err) error_handled = true end
    )

    cb()
    assert_true(error_handled)
  end,

  ['test_resource_cleanup'] = function()
    local utils = require('lua.todo-ai.utils')

    local timer_stopped = false
    local original_timer_stop = vim.fn.timer_stop
    vim.fn.timer_stop = function(id)
      timer_stopped = true
      return true
    end

    utils.cleanup({
      {type = 'timer', id = 1}
    })

    assert_true(timer_stopped)

    vim.fn.timer_stop = original_timer_stop
  end,
})