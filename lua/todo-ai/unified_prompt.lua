-- Unified prompt generation and handling for all code paths
-- Single source of truth for TODO scan, chat, and visual mode
local M = {}

local prompt_builder = require('todo-ai.prompt_builder')
local prompt_config = require('todo-ai.prompt_config')
local parser = require('todo-ai.parser')
local logger = require('todo-ai.logger')

-- Unified context structure that all paths should use
-- This ensures consistency across TODO, visual, and chat modes
function M.create_context(opts)
  opts = opts or {}

  -- Required fields
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local instruction = opts.instruction or ""

  -- Get buffer information
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local file_content = table.concat(lines, '\n')
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local filename = vim.fn.fnamemodify(file_path, ':t')
  local filetype = vim.bo[bufnr].filetype

  -- Build base context
  local context = {
    instruction = instruction,
    file_content = file_content,
    file_path = file_path,
    filename = filename,
    language = filetype,
    bufnr = bufnr
  }

  -- Add mode-specific fields
  if opts.mode == 'visual' then
    context.selected_text = opts.selected_text
    context.line_number = opts.start_line
    context.end_line = opts.end_line
    context.is_visual = true
  elseif opts.mode == 'todo' then
    context.line_number = opts.line_number
    context.surrounding_lines = M.get_surrounding_lines(lines, opts.line_number, 20)
    context.is_todo = true
  elseif opts.mode == 'chat' then
    -- Pure chat mode - no specific line context
    context.is_chat = true
  end

  -- Add project context (same for all modes)
  context = M.enrich_with_project_context(context)

  return context
end

-- Enrich context with project-level information
function M.enrich_with_project_context(context)
  -- Get project root
  local project_root = vim.fn.getcwd()
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if git_root ~= '' then
    project_root = git_root
  end
  context.project_root = project_root

  -- Load cached project context if available
  local cache_path = project_root .. '/.todoai/context.json'
  if vim.fn.filereadable(cache_path) == 1 then
    local cache_file = io.open(cache_path, 'r')
    if cache_file then
      local ok, cached = pcall(vim.fn.json_decode, cache_file:read('*all'))
      if ok then
        context.cached_context = cached
      end
      cache_file:close()
    end
  end

  -- Get other open buffers for context
  local other_buffers = {}
  local current_bufnr = context.bufnr
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= current_bufnr and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' and not name:match('^Todo%-AI Chat') then
        table.insert(other_buffers, {
          path = name,
          filename = vim.fn.fnamemodify(name, ':t'),
          filetype = vim.bo[bufnr].filetype
        })
      end
    end
  end
  context.other_buffers = other_buffers

  -- Load compact project context
  local ok, context_module = pcall(require, 'todo-ai.context_compact')
  if ok then
    context.project_context = context_module.get_for_prompt()
  end

  return context
end

-- Get surrounding lines for TODO context
function M.get_surrounding_lines(lines, target_line, radius)
  local start_line = math.max(1, target_line - radius)
  local end_line = math.min(#lines, target_line + radius)

  local result = {}
  for i = start_line, end_line do
    table.insert(result, {
      line_number = i,
      content = lines[i],
      is_target = i == target_line
    })
  end

  return result
end

-- Build the complete prompt (system + user) for any mode
function M.build_complete_prompt(context)
  -- Get system prompt (schema and rules)
  local system_prompt = prompt_config.get_schema_description()

  -- Build user prompt based on context
  local context_json = vim.fn.json_encode(context)
  local user_prompt = prompt_builder.build_user_prompt(context.instruction, context_json)

  -- Add mode-specific hints if needed
  if context.is_visual then
    user_prompt = user_prompt .. '\n\nIMPORTANT: Return the code changes in JSON format with mode="changes" and filename="' .. context.filename .. '"'
  elseif context.is_todo then
    user_prompt = user_prompt .. '\n\nIMPORTANT: Use mode="changes" to provide code modifications for the TODO.'
  end

  return {
    system = system_prompt,
    user = user_prompt,
    full = system_prompt .. "\n\n" .. user_prompt
  }
end

-- Send prompt to provider and handle response
function M.send_to_provider(context, callback)
  local providers = require('todo-ai.providers')
  local config = require('todo-ai.config')

  -- Ensure providers are initialized
  if not providers._initialized then
    providers.setup()
  end

  local provider_name = config.get('provider')
  local provider = providers.get(provider_name)

  if not provider then
    callback(nil, 'Provider ' .. provider_name .. ' not found')
    return
  end

  -- Build the prompt
  local prompts = M.build_complete_prompt(context)

  -- Use complete_async for TODO processing style (includes system prompt)
  if provider.complete_async then
    -- Send as instruction + context (provider will add system prompt)
    provider.complete_async(context.instruction, vim.fn.json_encode(context), {
      model = config.get('model'),
      temperature = config.get('temperature')
    }, callback)
  elseif provider.chat_async then
    -- For chat-based providers, send as messages
    local messages = {
      {role = 'system', content = prompts.system},
      {role = 'user', content = prompts.user}
    }

    provider.chat_async(messages, {
      model = config.get('model'),
      temperature = config.get('temperature')
    }, callback)
  else
    callback(nil, 'Provider does not support async operations')
  end
end

-- Handle provider response uniformly
function M.handle_response(response, error, context)
  local chat = require('todo-ai.chat')
  local diff_native = require('todo-ai.diff_native')
  local init = require('todo-ai.init')

  if error then
    chat.add_message('ai', '❌ **Error**: ' .. error)
    return
  end

  -- Parse response if it's a string
  if type(response) == 'string' then
    response = parser.parse(response, context.instruction)
  end

  -- Handle based on response mode
  if response.mode == "chat" then
    -- Pure conversational response - just render the explanation as markdown
    local content = response.explanation or "No response received"
    chat.add_message('ai', content)

  elseif response.mode == "changes" or (response.changes and #response.changes > 0) then
    -- Code changes mode
    if response.explanation and response.explanation ~= "" then
      chat.add_message('ai', "### 💬 Explanation\n" .. response.explanation)
    end

    -- Determine target buffer
    local target_buf = context.bufnr

    -- If response specifies a filename, try to find that buffer
    if response.filename then
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local buf_name = vim.api.nvim_buf_get_name(buf)
          -- Make sure it's not the chat buffer
          if not buf_name:match('Todo%-AI Chat') and buf_name:match(response.filename .. "$") then
            target_buf = buf
            break
          end
        end
      end
    end

    -- CRITICAL: Never apply changes to the chat buffer
    local target_buf_name = vim.api.nvim_buf_get_name(target_buf or 0)
    if target_buf_name:match('Todo%-AI Chat') then
      chat.add_message('ai', "❌ **Error**: Cannot modify the chat buffer. Please open a code file and try again.")
      return
    end

    -- Show diff in the target buffer
    diff_native.show_response(target_buf, response)

    -- Add navigation help
    chat.add_message('system', '✨ Changes ready for review! Use `]d` / `[d` to navigate, `<leader>ta` to accept, `<leader>tr` to reject.')

  else
    -- Fallback for unrecognized response format
    -- Just show the explanation if available, otherwise show error
    local content = response.explanation
    if content and content ~= "" then
      chat.add_message('ai', content)
    else
      chat.add_message('ai', "⚠️ Unexpected response format. Please try rephrasing your question.")
    end
  end
end

-- Unified processing function that handles all modes
function M.process(opts)
  local chat = require('todo-ai.chat')
  local init = require('todo-ai.init')
  local config = require('todo-ai.config')

  -- Validate required fields
  if not opts.instruction then
    error("instruction is required")
  end

  -- Determine mode based on provided options
  local mode
  if opts.todo then
    mode = 'todo'
  elseif opts.selected_text then
    mode = 'visual'
  else
    mode = 'chat'
  end

  -- Build state object based on mode
  local state_obj
  if mode == 'todo' then
    state_obj = opts.todo
  elseif mode == 'visual' then
    state_obj = {
      instruction = opts.instruction,
      line = opts.start_line,
      end_line = opts.end_line,
      selected_text = opts.selected_text,
      is_visual = true,
      bufnr = opts.bufnr
    }
  end

  -- Store state if needed
  if state_obj then
    init.state.current_todo = state_obj
  end
  if mode == 'visual' then
    init.state.visual_target_buffer = opts.bufnr
  end

  -- Open chat
  init.open_chat()

  -- Add appropriate user message
  if mode == 'todo' then
    chat.add_message('user', 'Processing TODO: ' .. opts.instruction)
  elseif mode == 'visual' then
    -- Show clean, user-friendly message for visual mode
    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ':t')
    local line_range = string.format("lines %d-%d", opts.start_line, opts.end_line)

    -- Build a clean message showing what the user asked for
    local user_message = string.format("**Task:** %s\n\n**File:** %s (%s)\n\n**Selected text:**\n```\n%s\n```",
      opts.instruction,
      filename,
      line_range,
      opts.selected_text
    )
    chat.add_message('user', user_message)
  else
    -- Chat mode - no special message needed, user already typed it
  end

  -- Create unified context
  local context_opts = {
    mode = mode,
    bufnr = opts.bufnr,
    instruction = opts.instruction
  }

  -- Add mode-specific fields
  if mode == 'todo' then
    context_opts.line_number = opts.todo.line
  elseif mode == 'visual' then
    context_opts.selected_text = opts.selected_text
    context_opts.start_line = opts.start_line
    context_opts.end_line = opts.end_line
  end

  local context = M.create_context(context_opts)

  -- Show thinking animation
  chat.show_thinking(config.get('model'))

  -- Send to provider
  M.send_to_provider(context, function(response, error)
    chat.hide_thinking()
    M.handle_response(response, error, context)
  end)
end

-- Helper function to find appropriate target buffer for chat mode
function M.find_target_buffer()
  local init = require('todo-ai.init')

  -- Try visual target buffer first
  if init.state.visual_target_buffer and vim.api.nvim_buf_is_valid(init.state.visual_target_buffer) then
    return init.state.visual_target_buffer
  end

  -- Find the most recent non-chat buffer
  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)

  -- If not in chat buffer, use current
  if not buf_name:match('Todo%-AI Chat') then
    return current_buf
  end

  -- Find the last buffer that wasn't the chat
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    local win_buf_name = vim.api.nvim_buf_get_name(win_buf)
    if not win_buf_name:match('Todo%-AI Chat') and win_buf_name ~= '' then
      return win_buf
    end
  end

  -- Try the alternate buffer
  local alt_buf = vim.fn.bufnr('#')
  if alt_buf > 0 and vim.api.nvim_buf_is_valid(alt_buf) then
    local alt_buf_name = vim.api.nvim_buf_get_name(alt_buf)
    if not alt_buf_name:match('Todo%-AI Chat') then
      return alt_buf
    end
  end

  -- Last resort: use the last known code buffer
  if init.state.last_code_buffer and vim.api.nvim_buf_is_valid(init.state.last_code_buffer) then
    return init.state.last_code_buffer
  end

  return nil
end

return M