# chat_vim

@class ChatVim
@field state ChatVimState

## Class: ChatVimState

```lua
ChatVimState
```

### Fields

- **state** (`ChatVimState`): 
- **chat_buf** (`number|nil`): 
- **chat_win** (`number|nil`): 
- **input_start_line** (`number`): 
- **is_inserting** (`boolean`): 
- **conversation** (`table[]`): 
- **waiting_for_response** (`boolean`): 

## Class: ChatVim

```lua
ChatVim
```

### Fields

- **state** (`ChatVimState`): 
- **chat_buf** (`number|nil`): 
- **chat_win** (`number|nil`): 
- **input_start_line** (`number`): 
- **is_inserting** (`boolean`): 
- **conversation** (`table[]`): 
- **waiting_for_response** (`boolean`): 

## Functions

### M.add_response

```lua
function M.add_response(content)
```

**Parameters:**

- `content` (string): 

### M.clear_conversation

```lua
function M.clear_conversation()
```

### M.close

```lua
function M.close()
```

### M.get_input

```lua
function M.get_input()
```

**Returns:**

- string|nil

### M.build_context

```lua
function M.build_context()
```

**Returns:**

- table

### M.setup_autocmds

```lua
function M.setup_autocmds()
```

### M.open

```lua
function M.open()
```

### M.setup_keybindings

```lua
function M.setup_keybindings()
```

### M.send_message

```lua
function M.send_message()
```

### M.initialize_buffer

```lua
function M.initialize_buffer()
```

### M.move_to_input

```lua
function M.move_to_input()
```

### M.update_buffer

```lua
function M.update_buffer()
```

### M.add_message_to_buffer

```lua
function M.add_message_to_buffer(lines, role, content)
```

**Parameters:**

- `lines` (string[]): 
- `role` (string): 
- `content` (string): 

### M.new_conversation

```lua
function M.new_conversation()
```

### M.clear_input

```lua
function M.clear_input()
```

### M.handle_code_changes

```lua
function M.handle_code_changes(changes)
```

**Parameters:**

- `changes` (table[]): 

### M.process_message

```lua
function M.process_message(message)
```

**Parameters:**

- `message` (string): 
