# Troubleshooting Guide

## Common Issues

### 1. API Key Not Found

**Error:** `API key not found` or `401 Unauthorized`

**Solution:**
```bash
# Set your API key in environment
export ANTHROPIC_API_KEY="your-key-here"
export OPENAI_API_KEY="your-key-here"

# Or in your shell config (~/.bashrc, ~/.zshrc)
echo 'export ANTHROPIC_API_KEY="your-key"' >> ~/.zshrc
source ~/.zshrc
```

### 2. Circuit Breaker Open

**Error:** `Circuit breaker open for provider_name (failures: 5)`

**Cause:** Too many consecutive failures

**Solution:**
```vim
" Check circuit state
:lua print(vim.inspect(require('todo-ai.circuit_breaker').get_state('claude')))

" Reset circuit breaker
:lua require('todo-ai.circuit_breaker').reset('claude')

" Or wait 60 seconds for automatic recovery
```

### 3. Timeout Errors

**Error:** `Command timed out after 30000ms`

**Solution:**
```lua
-- Increase timeout in config
require('todo-ai').setup({
  retry_config = {
    max_delay = 60000,  -- Increase max delay
  }
})
```

### 4. Rate Limiting

**Error:** `429 Too Many Requests`

**Solution:**
- Wait for automatic retry with exponential backoff
- Reduce request frequency
- Check API rate limits for your plan

### 5. Invalid JSON Response

**Error:** `Failed to parse response`

**Debug:**
```vim
" Enable debug logging
:lua require('todo-ai.config').set('log_level', 'DEBUG')

" Check logs
:!tail -f /tmp/todo-ai.log
```

### 6. Tests Hanging

**Issue:** Tests take too long or hang

**Solution:**
```bash
# Use test mode for synchronous execution
nvim --headless -c "lua vim.g.todo_ai_test_mode = true" -l tests/run_tests.lua
```

## Debug Commands

### Check Plugin Health

```vim
" Check configuration
:lua print(vim.inspect(require('todo-ai.config').get_all()))

" Check provider
:lua print(require('todo-ai.config').get('provider'))

" Test provider connection
:lua require('todo-ai.providers').test_connection()
```

### View Logs

```vim
" Open log file
:edit /tmp/todo-ai.log

" Tail logs in terminal
:!tail -f /tmp/todo-ai.log

" Clear old logs
:!rm /tmp/todo-ai.log
```

### Check Dependencies

```vim
" Check required dependencies
:lua require('todo-ai.dependencies').check_dependencies()

" Check Plenary installation
:lua print(pcall(require, 'plenary'))
```

## Performance Issues

### Slow Context Generation

**Problem:** Context generation takes too long

**Solution:**
```lua
-- Limit context size
require('todo-ai.config').set('max_context_size', 50000)

-- Use cached context
local context = require('todo-ai.context_compact')
context.CACHE_TTL = 600000  -- 10 minutes
```

### Memory Usage

**Problem:** High memory usage with large conversations

**Solution:**
```lua
-- Automatic cleanup is enabled
-- Manual cleanup if needed
:lua require('todo-ai.chat_manager').cleanup_old_messages()

-- Check message count
:lua print(#require('todo-ai.chat_manager').state.messages)
```

## Network Issues

### Proxy Configuration

```bash
# Set proxy for curl
export https_proxy="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
```

### SSL Certificate Issues

```bash
# Disable SSL verification (not recommended for production)
export CURL_CA_BUNDLE=""
```

## Recovery Procedures

### Reset All State

```vim
" Reset circuit breakers
:lua require('todo-ai.circuit_breaker').reset_all()

" Clear chat history
:lua require('todo-ai.chat_manager').reset()

" Clear context cache
:lua require('todo-ai.context_compact').last_generated = 0
```

### Reload Plugin

```vim
" Using Plenary
:lua require('plenary.reload').reload_module('todo-ai')

" Manual reload
:lua package.loaded['todo-ai'] = nil
:lua require('todo-ai').setup()
```

### Emergency Disable

```vim
" Temporarily disable auto features
:lua vim.g.todo_ai_disabled = true

" Re-enable
:lua vim.g.todo_ai_disabled = false
```

## Getting Help

### Diagnostic Information

When reporting issues, include:

```vim
" Version info
:version

" Plugin config
:lua print(vim.inspect(require('todo-ai.config').get_all()))

" Error messages
:messages

" Log tail (last 50 lines)
:!tail -50 /tmp/todo-ai.log
```

### Test Individual Components

```lua
-- Test secure execution
local secure = require('todo-ai.secure_exec')
local valid, err = secure.validate_command("ls")
print(valid, err)

-- Test retry manager
local retry = require('todo-ai.retry_manager')
local success, result = retry.execute_with_retry(
  function() return "test" end,
  "test_service",
  {max_retries = 0}
)
print(success, result)

-- Test LLM validator
local validator = require('todo-ai.llm_validator')
local valid, data = validator.validate_json('{"test": true}')
print(valid, vim.inspect(data))
```

## Known Limitations

1. **Async operations in test mode** - Tests run synchronously for speed
2. **Large file handling** - Files over 1MB may be slow
3. **Complex diffs** - Very complex changes may require manual review
4. **Rate limits** - API rate limits vary by provider and plan

## FAQ

**Q: Why is the plugin not loading?**
A: Check `:scriptnames` to see if the plugin is loaded. Ensure it's in your runtimepath.

**Q: Can I use multiple providers?**
A: Yes, change provider with `:lua require('todo-ai.config').set('provider', 'openai')`

**Q: How do I disable automatic features?**
A: Set `auto_scan_on_save = false` in setup

**Q: Where are my API keys stored?**
A: Only in environment variables, never in files

**Q: How do I contribute or report bugs?**
A: Visit https://github.com/tpabla/todo-ai/issues