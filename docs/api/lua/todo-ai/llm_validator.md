# llm_validator

@class LLMValidator
@field validators table<string, function>
@field retry_count number
@field max_retries number

## Class: LLMValidator

```lua
LLMValidator
```

### Fields

- **validators** (`table<string,`): function>
- **retry_count** (`number`): 
- **max_retries** (`number`): 

## Functions

### M.sanitize_content

```lua
function M.sanitize_content(content)
```

**Parameters:**

- `content` (string): 

**Returns:**

- string

### M.validate_chat_response

```lua
function M.validate_chat_response(response)
```

**Parameters:**

- `response` (table): 

**Returns:**

- boolean valid
- string|nil error
- table|nil cleaned_response

### M.validate_code_changes

```lua
function M.validate_code_changes(changes)
```

**Parameters:**

- `changes` (table[]): 

**Returns:**

- boolean valid
- string|nil error
- table|nil fixed_changes

### M.run_validator

```lua
function M.run_validator(name, data)
```

**Parameters:**

- `data` (any): 
- `name` (string): 

**Returns:**

- boolean valid
- string|nil error

### M.register_validator

```lua
function M.register_validator(name, validator)
```

**Parameters:**

- `validator` (function): 
- `name` (string): 

### M.validate_json

```lua
function M.validate_json(json_str)
```

**Parameters:**

- `json_str` (string): 

**Returns:**

- boolean valid
- any|nil data
- string|nil error

### M.validate_buffer_operation

```lua
function M.validate_buffer_operation(bufnr, start_line, end_line)
```

**Parameters:**

- `end_line` (number): 
- `bufnr` (number): 
- `start_line` (number): 

**Returns:**

- boolean valid
- string|nil error

### M.validate_file_path

```lua
function M.validate_file_path(path)
```

**Parameters:**

- `path` (string): 

**Returns:**

- boolean valid
- string|nil sanitized_path

### M.validated_request

```lua
function M.validated_request(provider, messages, config, callback)
```

**Parameters:**

- `messages` (table): 
- `config` (table): 
- `provider` (table): 
- `callback` (function): 

### M.create_retry_prompt

```lua
function M.create_retry_prompt(original_prompt, validation_errors, attempt)
```

**Parameters:**

- `attempt` (number): 
- `original_prompt` (string): 
- `validation_errors` (string): 

**Returns:**

- string

### M.validate_diff

```lua
function M.validate_diff(diff_text)
```

**Parameters:**

- `diff_text` (string): 

**Returns:**

- boolean valid
- string|nil error
- string|nil fixed_diff
