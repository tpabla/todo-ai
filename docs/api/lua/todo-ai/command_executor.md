# command_executor

Command executor using Plenary's Job
@class CommandExecutor

## Class: CommandExecutor

```lua
CommandExecutor
```

## Functions

### M.execute_async

```lua
function M.execute_async(cmd, opts, callback)
```

**Parameters:**

- `opts` (table): Options
- `cmd` (string[]): Command array
- `callback` (function(success:): boolean, output: string|nil, error: string|nil)

### M.execute

```lua
function M.execute(cmd, opts, callback)
```

**Parameters:**

- `opts` (table): Options {timeout: number, cwd: string}
- `cmd` (string[]): Command array
- `callback` (function(success:): boolean, output: string|nil, error: string|nil)

### M.execute_sync

```lua
function M.execute_sync(cmd, opts)
```

**Parameters:**

- `opts?` (table): Options
- `cmd` (string[]): Command array

**Returns:**

- boolean success, string|nil output, string|nil error
