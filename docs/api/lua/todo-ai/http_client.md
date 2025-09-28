# http_client

HTTP client using Plenary's curl
@class HttpClient

## Class: HttpClient

```lua
HttpClient
```

## Functions

### M.request

```lua
function M.request(url, opts)
```

**Parameters:**

- `url` (string): 
- `opts` (table): 

**Returns:**

- table|nil response, string|nil error

### M.request_async_with_retry

```lua
function M.request_async_with_retry(url, opts, callback)
```

**Parameters:**

- `url` (string): 
- `callback` (function(success:): boolean, result: any)
- `opts` (table): 

### M.request_with_retry

```lua
function M.request_with_retry(url, opts)
```

**Parameters:**

- `url` (string): 
- `opts` (table): 

**Returns:**

- boolean success, any result

### M.request_async

```lua
function M.request_async(url, opts, callback)
```

**Parameters:**

- `url` (string): 
- `callback` (function(response:): table|nil, error: string|nil)
- `opts` (table): 
