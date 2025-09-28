# retry_manager

Retry manager with exponential backoff
@class RetryManager

## Class: RetryConfig

```lua
RetryConfig
```

### Fields

- **max_retries** (`number`): Maximum number of retry attempts
- **base_delay** (`number`): Base delay in milliseconds
- **max_delay** (`number`): Maximum delay in milliseconds
- **exponential_base** (`number`): Base for exponential backoff (typically 2)
- **jitter** (`boolean`): Add random jitter to prevent thundering herd

## Class: RetryManager

```lua
RetryManager
```

### Fields

- **max_retries** (`number`): Maximum number of retry attempts
- **base_delay** (`number`): Base delay in milliseconds
- **max_delay** (`number`): Maximum delay in milliseconds
- **exponential_base** (`number`): Base for exponential backoff (typically 2)
- **jitter** (`boolean`): Add random jitter to prevent thundering herd

## Functions

### M.execute_with_retry

```lua
function M.execute_with_retry(fn, service_name, config)
```

**Parameters:**

- `attempt` (number): Current attempt (0-indexed)
- `fn` (function): The function to execute
- `config?` (RetryConfig): Optional retry configuration
- `service_name` (string): Name of the service (for circuit breaker)
- `error_message` (string): 
- `config` (RetryConfig): 

**Returns:**

- number delay_ms
- boolean
- boolean success, any result_or_error

### M.get_stats

```lua
function M.get_stats(service_name)
```

**Parameters:**

- `service_name` (string): 

**Returns:**

- table

### M.execute_with_retry_async

```lua
function M.execute_with_retry_async(fn, service_name, config, callback)
```

**Parameters:**

- `callback` (function(success:): boolean, result: any)
- `config?` (RetryConfig): Optional retry configuration
- `fn` (function): The async function to execute (takes callback)
- `service_name` (string): Name of the service
