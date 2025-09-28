# Unified Prompt Architecture

## Overview

The todo-ai plugin now uses a unified prompt generation and handling system for ALL code paths. This ensures consistency and maintainability across different interaction modes.

## Architecture

### Central Module: `unified_prompt.lua`

This module is the single source of truth for:
- Context creation and enrichment
- Prompt building (system + user)
- Provider communication
- Response handling

### Three Entry Points, One Flow

All three interaction modes now use the same underlying system:

```lua
-- TODO Processing
unified_prompt.process_todo(todo, bufnr)

-- Visual Mode
unified_prompt.process_visual(instruction, selected_text, start_line, end_line, bufnr)

-- Chat Messages
unified_prompt.process_chat_message(message)
```

## Key Components

### 1. Context Creation

Every interaction creates a unified context structure:

```lua
{
  -- Common fields
  instruction = "user's request",
  file_content = "full file content",
  file_path = "/path/to/file",
  filename = "file.lua",
  language = "lua",
  bufnr = buffer_number,

  -- Mode-specific fields
  is_todo = true,           -- for TODO mode
  is_visual = true,         -- for visual mode
  is_chat = true,           -- for chat mode
  selected_text = "...",    -- for visual mode
  line_number = 10,         -- for TODO/visual
  end_line = 15,            -- for visual mode
  surrounding_lines = {...}, -- for TODO mode

  -- Project context (all modes)
  project_root = "/project",
  cached_context = {...},
  other_buffers = {...},
  project_context = "..."
}
```

### 2. Prompt Building

The system builds prompts consistently:

```lua
{
  system = "schema and rules from prompt_config",
  user = "formatted user prompt from prompt_builder",
  full = "system + user combined"
}
```

### 3. Provider Communication

The system intelligently chooses the provider interface:

- `complete_async`: For providers that handle their own system prompts
- `chat_async`: For chat-based providers requiring message arrays

### 4. Response Handling

Unified response handling for all modes:

- **Changes mode**: Shows diff in buffer, adds to chat
- **Chat mode**: Displays explanation in chat
- **Error handling**: Consistent error messages

## Benefits

1. **DRY (Don't Repeat Yourself)**: No duplicate prompt generation logic
2. **Consistency**: All paths get the same context enrichment
3. **Maintainability**: Single place to update prompt logic
4. **Testing**: Easier to test with unified interface
5. **Extensibility**: Easy to add new modes or features

## Migration Guide

### Old Flow (Before)
```lua
-- Visual mode had its own prompt building
-- Chat had its own context gathering
-- TODO had its own provider communication
```

### New Flow (After)
```lua
-- All modes use unified_prompt module
-- Single source of truth for context and prompts
-- Consistent provider interface
```

## Testing

The unified system is thoroughly tested:

- `unified_prompt_spec.lua`: Unit tests for all components
- `integration_spec.lua`: End-to-end testing
- All existing tests continue to pass

## Future Improvements

The unified architecture makes it easy to add:

- New interaction modes
- Enhanced context gathering
- Better prompt templates
- Advanced response processing
- Multi-file operations