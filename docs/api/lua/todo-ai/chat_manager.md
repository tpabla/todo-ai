# chat_manager

@class ChatManager
@field state ChatState
@field MAX_MESSAGES number Maximum messages to keep in memory
@field MAX_MESSAGE_LENGTH number Maximum length per message

## Class: ChatState

```lua
ChatState
```

### Fields

- **state** (`ChatState`): 
- **MAX_MESSAGES** (`number`): Maximum messages to keep in memory
- **MAX_MESSAGE_LENGTH** (`number`): Maximum length per message
- **messages** (`Message[]`): 
- **input_buf** (`number|nil`): 
- **display_buf** (`number|nil`): 
- **win** (`number|nil`): 
- **thinking_timer** (`number|nil`): 
- **thinking_frame** (`number`): 
- **thinking_line_num** (`number|nil`): 
- **edit_queue** (`Edit[]`): 
- **current_edit_index** (`number`): 
- **edit_preview_buf** (`number|nil`): 
- **message_count** (`number`): 
- **total_tokens** (`number`): 
- **role** (`string`): 'user'|'ai'|'system'
- **content** (`string`): 
- **timestamp** (`number`): 
- **token_estimate** (`number`): 

## Class: Message

```lua
Message
```

### Fields

- **state** (`ChatState`): 
- **MAX_MESSAGES** (`number`): Maximum messages to keep in memory
- **MAX_MESSAGE_LENGTH** (`number`): Maximum length per message
- **messages** (`Message[]`): 
- **input_buf** (`number|nil`): 
- **display_buf** (`number|nil`): 
- **win** (`number|nil`): 
- **thinking_timer** (`number|nil`): 
- **thinking_frame** (`number`): 
- **thinking_line_num** (`number|nil`): 
- **edit_queue** (`Edit[]`): 
- **current_edit_index** (`number`): 
- **edit_preview_buf** (`number|nil`): 
- **message_count** (`number`): 
- **total_tokens** (`number`): 
- **role** (`string`): 'user'|'ai'|'system'
- **content** (`string`): 
- **timestamp** (`number`): 
- **token_estimate** (`number`): 

## Class: ChatManager

```lua
ChatManager
```

### Fields

- **state** (`ChatState`): 
- **MAX_MESSAGES** (`number`): Maximum messages to keep in memory
- **MAX_MESSAGE_LENGTH** (`number`): Maximum length per message
- **messages** (`Message[]`): 
- **input_buf** (`number|nil`): 
- **display_buf** (`number|nil`): 
- **win** (`number|nil`): 
- **thinking_timer** (`number|nil`): 
- **thinking_frame** (`number`): 
- **thinking_line_num** (`number|nil`): 
- **edit_queue** (`Edit[]`): 
- **current_edit_index** (`number`): 
- **edit_preview_buf** (`number|nil`): 
- **message_count** (`number`): 
- **total_tokens** (`number`): 
- **role** (`string`): 'user'|'ai'|'system'
- **content** (`string`): 
- **timestamp** (`number`): 
- **token_estimate** (`number`): 

## Functions

### M.get_stats

```lua
function M.get_stats()
```

**Returns:**

- table

### M.hide_thinking

```lua
function M.hide_thinking()
```

### M.clear

```lua
function M.clear()
```

### M.render_messages

```lua
function M.render_messages(max_lines)
```

**Parameters:**

- `max_lines` (number|nil): 

**Returns:**

- string[]

### M.update_display

```lua
function M.update_display()
```

### M.add_message

```lua
function M.add_message(role, content)
```

**Parameters:**

- `content` (string): 
- `role` (string): 

**Returns:**

- number
- boolean success

### M.get_recent_messages

```lua
function M.get_recent_messages(max_tokens)
```

**Parameters:**

- `max_tokens` (number|nil): 

**Returns:**

- Message[]

### M.cleanup_old_messages

```lua
function M.cleanup_old_messages()
```

### M.cleanup_by_tokens

```lua
function M.cleanup_by_tokens()
```

### M.show_thinking

```lua
function M.show_thinking(model)
```

**Parameters:**

- `model` (string|nil): 
