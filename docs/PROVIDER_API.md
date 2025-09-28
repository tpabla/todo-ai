# Provider API Documentation

## Overview

TodoAI supports multiple LLM providers through a unified interface. Providers handle communication with AI services and response parsing.

## Built-in Providers

- **claude** - Anthropic Claude API
- **openai** - OpenAI GPT models
- **ollama** - Local Ollama models

## Provider Interface

Each provider must implement these methods:

```lua
-- Required fields
M.api_key = vim.env.PROVIDER_API_KEY  -- API key from environment
M.api_url = 'https://api.example.com/v1/endpoint'  -- API endpoint
M.default_model = 'model-name'  -- Default model to use

-- Required methods
function M.get_system_prompt()
  -- Returns the system prompt for the AI
  -- Must include schema instructions
end

function M.build_prompt(instruction, context)
  -- Build the user prompt from instruction and context
  -- @param instruction string User's request
  -- @param context string|table Context information
  -- @return string Formatted prompt
end
```

## Using Plenary for Testing

Plenary provides test utilities that work well with providers:

```lua
-- tests/plenary/provider_spec.lua
describe("my_provider", function()
  local provider

  before_each(function()
    -- Use Plenary's reload to get fresh instance
    require('plenary.reload').reload_module('todo-ai.providers.my_provider')
    provider = require('todo-ai.providers.my_provider')
  end)

  it("should build prompts correctly", function()
    local prompt = provider.build_prompt("test", "{}")
    assert.is_string(prompt)
  end)
end)
```

## HTTP Requests with Retry

Providers use the retry manager for resilient API calls:

```lua
local retry_manager = require('todo-ai.retry_manager')
local providers = require('todo-ai.providers')

-- Simple request with retry
local success, response = retry_manager.execute_with_retry(
  function()
    return providers.request(url, {
      method = 'POST',
      headers = headers,
      body = body
    })
  end,
  'provider_name',  -- Service name for circuit breaker
  {
    max_retries = 3,
    base_delay = 1000,
    exponential_base = 2
  }
)
```

## Creating a Custom Provider

### 1. Create the provider module

```lua
-- lua/todo-ai/providers/custom.lua
local M = {}

-- Configuration
M.api_key = vim.env.CUSTOM_API_KEY
M.api_url = 'https://api.custom.com/v1/chat'
M.default_model = 'custom-model-1'

-- Get system prompt with schema
function M.get_system_prompt()
  local schema = require('todo-ai.schema')
  return string.format([[
You are an AI assistant. Respond with valid JSON following this schema:
%s
]], schema.get_schema_description())
end

-- Build user prompt
function M.build_prompt(instruction, context)
  if type(context) == 'string' then
    -- Try parsing JSON context
    local ok, parsed = pcall(vim.fn.json_decode, context)
    if ok then
      context = parsed
    end
  end

  -- Format based on context type
  if context.selected_text then
    return string.format("File: %s\n\n%s\n\nRequest: %s",
      context.file_path,
      context.selected_text,
      instruction)
  else
    return instruction
  end
end

return M
```

### 2. Register the provider

```lua
-- In lua/todo-ai/providers/init.lua
function M.setup()
  M.providers.claude = require('todo-ai.providers.claude')
  M.providers.ollama = require('todo-ai.providers.ollama')
  M.providers.openai = require('todo-ai.providers.openai')
  M.providers.custom = require('todo-ai.providers.custom')  -- Add your provider
end
```

### 3. Configure in setup

```lua
require('todo-ai').setup({
  provider = 'custom',
  model = 'custom-model-1',
})
```

## Using Vim's Module System

Vim/Neovim provides built-in module caching and loading:

```lua
-- Module is cached after first require
local provider = require('todo-ai.providers.claude')

-- Force reload (useful for development/testing)
package.loaded['todo-ai.providers.claude'] = nil
local provider = require('todo-ai.providers.claude')

-- Or use Plenary's reload
require('plenary.reload').reload_module('todo-ai.providers.claude')
```

## Testing with Mocks

Use standard Lua patterns for mocking:

```lua
describe("provider with mocked HTTP", function()
  local provider
  local original_request

  before_each(function()
    provider = require('todo-ai.providers.custom')
    original_request = require('todo-ai.providers').request

    -- Mock the request function
    require('todo-ai.providers').request = function(url, opts)
      return {status = "ok", response = "mocked"}, nil
    end
  end)

  after_each(function()
    -- Restore original
    require('todo-ai.providers').request = original_request
  end)

  it("should handle mocked responses", function()
    -- Test with mock
  end)
end)
```

## Error Handling

Providers automatically get retry logic with exponential backoff:

```lua
-- Retryable errors (automatic retry):
- timeout
- connection errors
- rate limiting (429)
- server errors (5xx)

-- Non-retryable errors (immediate failure):
- Invalid API key (401)
- Invalid request (400)
- Not found (404)
```

## Circuit Breaker

After 5 consecutive failures, the circuit breaker opens and prevents requests for 60 seconds:

```lua
-- Check circuit state
local circuit_breaker = require('todo-ai.circuit_breaker')
local state = circuit_breaker.get_state('provider_name')

-- States:
-- 'closed' - Normal operation
-- 'open' - Blocking requests
-- 'half_open' - Testing recovery
```

## Configuration Options

```lua
{
  -- Provider selection
  provider = 'claude',
  model = 'claude-3-5-sonnet-20241022',

  -- Retry configuration
  retry_config = {
    max_retries = 3,
    base_delay = 1000,
    max_delay = 30000,
    exponential_base = 2,
    jitter = true,
  },

  -- Circuit breaker configuration
  circuit_config = {
    failure_threshold = 5,
    success_threshold = 2,
    timeout = 60000,
    reset_timeout = 300000,
  },
}
```

## Best Practices

1. **Use environment variables for API keys** - Never hardcode keys
2. **Implement proper error messages** - Help users understand failures
3. **Follow the schema** - Ensure responses match expected format
4. **Test with Plenary** - Use the provided test framework
5. **Handle rate limits** - Respect API rate limits
6. **Log appropriately** - Use debug level for verbose logs

## Examples

See the built-in providers for examples:
- `lua/todo-ai/providers/claude.lua` - Full-featured provider
- `lua/todo-ai/providers/ollama.lua` - Local model provider
- `lua/todo-ai/providers/openai.lua` - Simple API integration