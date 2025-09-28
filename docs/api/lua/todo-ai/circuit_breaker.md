# circuit_breaker

Circuit breaker pattern for API resilience
@class CircuitBreaker

## Class: CircuitBreaker

```lua
CircuitBreaker
```

### Fields

- **failures** (`number`): Number of consecutive failures
- **last_failure_time** (`number`): Timestamp of last failure
- **state** (`'closed'|'open'|'half_open'`): Circuit state
- **success_count** (`number`): Successful calls in half-open state

## Class: CircuitBreakerState

```lua
CircuitBreakerState
```

### Fields

- **failures** (`number`): Number of consecutive failures
- **last_failure_time** (`number`): Timestamp of last failure
- **state** (`'closed'|'open'|'half_open'`): Circuit state
- **success_count** (`number`): Successful calls in half-open state

## Functions

### M.reset_all

```lua
function M.reset_all()
```

### M.record_failure

```lua
function M.record_failure(service_name, error_message)
```

**Parameters:**

- `error_message` (string): 
- `service_name` (string): 

### M.record_success

```lua
function M.record_success(service_name)
```

**Parameters:**

- `service_name` (string): 

### M.reset

```lua
function M.reset(service_name)
```

**Parameters:**

- `service_name` (string): 

### M.init

```lua
function M.init(service_name)
```

**Parameters:**

- `service_name` (string): 

### M.can_proceed

```lua
function M.can_proceed(service_name)
```

**Parameters:**

- `service_name` (string): 

**Returns:**

- boolean can_proceed
- string|nil error_message

### M.get_state

```lua
function M.get_state(service_name)
```

**Parameters:**

- `service_name` (string): 

**Returns:**

- table state
