# retry_manager

@class RetryManager

## Class: RetryManager

```lua
RetryManager
```

## Functions

### M.execute_with_retry_async

```lua
function M.execute_with_retry_async(fn, service_name, opts, callback)
```

**Parameters:**

- `callback` (function): Final callback(success, result)
- `error_msg` (string): 
- `attempt` (number): 
- `service_name` (string): Service name for logging
- `fn` (function): Function that takes a callback(success, result)
- `opts` (table?): Ignored (for compatibility)

**Returns:**

- boolean
- number

### M.execute_with_retry

```lua
function M.execute_with_retry(fn, service_name, opts)
```

**Parameters:**

- `service_name` (string): Service name for logging
- `fn` (function): Function to execute
- `opts` (table?): Ignored (for compatibility)

**Returns:**

- boolean success, any result
