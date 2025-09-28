# http_client

HTTP client using Plenary's curl
@class HttpClient

## Class: HttpClient

```lua
HttpClient
```

## Functions

### M.request_async

```lua
function M.request_async(url, opts, callback)
```

**Parameters:**

- `callback` (function(response:): table|nil, error: string|nil)
- `url` (string): 
- `opts` (table): 

### M.request

```lua
function M.request(url, opts)
```

**Parameters:**

- `opts` (table): 
- `url` (string): 

**Returns:**

- table|nil response, string|nil error

### M.request_async_with_retry

```lua
function M.request_async_with_retry(url, opts, callback)
```

**Parameters:**

- `callback` (function(success:): boolean, result: any)
- `url` (string): 
- `opts` (table): 

### M.request_with_retry

```lua
function M.request_with_retry(url, opts)
```

**Parameters:**

- `opts` (table): 
- `url` (string): 

**Returns:**

- boolean success, any result
