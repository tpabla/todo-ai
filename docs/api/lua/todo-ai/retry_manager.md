# retry_manager

@class RetryManager

## Class: RetryManager

```lua
RetryManager
```

## Functions

### M.execute_with_retry

```lua
function M.execute_with_retry(fn, service_name, opts)
```

**Parameters:**

- `service_name` (string): Service name for logging
- `opts` (table?): Ignored (for compatibility)
- `fn` (function): Function to execute

**Returns:**

- boolean success, any result

### M.execute_with_retry_async

```lua
function M.execute_with_retry_async(fn, service_name, opts, callback)
```

**Parameters:**

- `service_name` (string): Service name for logging
- `callback` (function): Final callback(success, result)
- `fn` (function): Function that takes a callback(success, result)
- `opts` (table?): Ignored (for compatibility)
- `error_msg` (string): 
- `attempt` (number): 

**Returns:**

- boolean
- number
