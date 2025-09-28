# config_manager

@class ConfigManager
@field config table
@field defaults table
@field config_path string
@field project_config_path string

## Class: ConfigManager

```lua
ConfigManager
```

### Fields

- **config** (`table`): 
- **defaults** (`table`): 
- **config_path** (`string`): 
- **project_config_path** (`string`): 

## Functions

### M.get

```lua
function M.get(key)
```

**Parameters:**

- `key` (string): Dot-separated path (e.g., "rate_limits.claude.max_requests")

**Returns:**

- any value

### M.init

```lua
function M.init()
```

**Parameters:**

- `config` (table): 
- `path` (string): 

**Returns:**

- table|nil config, string|nil error
- boolean success, string|nil error

### M.save

```lua
function M.save(scope)
```

**Parameters:**

- `scope` (string|nil): 'global' or 'project' (default: 'project')

**Returns:**

- boolean success, string|nil error

### M.apply_env_overrides

```lua
function M.apply_env_overrides()
```

### M.validate

```lua
function M.validate()
```

**Returns:**

- boolean valid, string[]|nil errors

### M.open_in_editor

```lua
function M.open_in_editor(scope)
```

**Parameters:**

- `scope` (string|nil): 'global' or 'project'

### M.merge_configs

```lua
function M.merge_configs(base, override)
```

**Parameters:**

- `override` (table): 
- `base` (table): 

**Returns:**

- table merged

### M.reset

```lua
function M.reset(scope)
```

**Parameters:**

- `scope` (string|nil): 'all', 'global', or 'project'

### M.get_info

```lua
function M.get_info()
```

**Returns:**

- table info

### M.set

```lua
function M.set(key, value, persist)
```

**Parameters:**

- `key` (string): Dot-separated path
- `persist` (boolean|nil): Whether to save to file
- `value` (any): 
