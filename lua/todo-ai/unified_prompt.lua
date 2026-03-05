-- Unified prompt generation and handling for all code paths
-- Single source of truth for TODO scan, chat, and visual mode
local M = {}

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
        -- Get buffer content (limit size to avoid huge context)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local content = table.concat(lines, '\n')

        -- Limit content size (e.g., first 2000 chars)
        if #content > 2000 then
          content = content:sub(1, 2000) .. '\n... [content truncated]'
        end

        table.insert(other_buffers, {
          path = name,
          filename = vim.fn.fnamemodify(name, ':t'),
          filetype = vim.bo[bufnr].filetype,
          bufnr = bufnr,  -- Store bufnr for LSP collection
          content = content
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

  -- Add LSP context
  local config = require('todo-ai.config')
  local lsp_config = config.get('lsp_context')

  if lsp_config and lsp_config.enabled ~= false then
    local lsp_ok, lsp_context = pcall(require, 'todo-ai.lsp_context')
    if lsp_ok then
      -- Get focused LSP context for the current buffer
      local line = context.line_number or (context.is_visual and context.start_line) or nil
      local lsp_data = lsp_context.get_focused_context(context.bufnr, line, 0, lsp_config)
      if lsp_data then
        context.lsp = lsp_data
      end

      -- Get LSP context for all other open buffers if enabled
      if lsp_config.include_all_buffers ~= false then
        local all_buffers_lsp = {}
        for _, buf_info in ipairs(context.other_buffers or {}) do
          if buf_info.bufnr then
            -- Get simplified LSP data for other buffers (mainly diagnostics)
            local buf_lsp = lsp_context.get_buffer_diagnostics_summary(buf_info.bufnr)
            if buf_lsp then
              all_buffers_lsp[buf_info.filename] = buf_lsp
            end
          end
        end

        if vim.tbl_count(all_buffers_lsp) > 0 then
          context.all_buffers_lsp = all_buffers_lsp
        end
      end
    end
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

-- Send context to Rust backend for completion
function M.send_to_provider(context, callback)
  local backend = require('todo-ai.backend')

  if not backend.is_available() then
    error("Rust backend not available — cannot send to provider")
  end

  logger.info('unified_prompt', 'Sending to Rust backend via complete RPC')

  -- Send context directly — Rust builds prompts, calls provider, parses, validates
  backend.request("complete", context, function(result, rpc_err)
    if rpc_err then
      local err_msg = type(rpc_err) == 'table' and rpc_err.message or tostring(rpc_err)
      callback(nil, err_msg)
      return
    end
    callback(result, nil)
  end)
end

-- Handle provider response uniformly
function M.handle_response(response, error, context)
  local chat = require('todo-ai.chat')
  local diff = require('todo-ai.diff')
  local init = require('todo-ai.init')

  if error then
    chat.add_message('ai', '❌ **Error**: ' .. error)
    return
  end

  -- Response is already parsed and validated by Rust backend
  logger.debug('Response mode: ' .. tostring(response.mode))
  logger.debug('Response filename: ' .. tostring(response.filename))

  -- Show validation warnings if Rust returned them
  if response.validation_errors then
    logger.error('Schema validation warnings: ' .. vim.inspect(response.validation_errors))
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
    local target_buf = nil

    if response.filename then
      -- Build full path — prefer context.file_path if the filename matches
      -- to avoid path doubling (e.g. LLM returns "rust/src/main.rs" when cwd already includes "rust/")
      local full_path
      if response.filename:match('^/') then
        full_path = response.filename
      elseif context.file_path and context.file_path:match(response.filename:gsub('([%(%)%.%%%+%-%*%?%[%^%$])', '%%%1') .. '$') then
        full_path = context.file_path
      else
        full_path = vim.fn.getcwd() .. '/' .. response.filename
      end

      -- Get or create buffer
      target_buf = vim.fn.bufnr(full_path)
      if target_buf == -1 then
        target_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(target_buf, full_path)
        if vim.fn.filereadable(full_path) == 1 then
          vim.fn.bufload(target_buf)
        else
          -- Set filetype based on extension for new files
          local ext = full_path:match("%.([^.]+)$")
          if ext then
            vim.bo[target_buf].filetype = ext
          end
        end
      end

      -- Mark new files
      if vim.fn.filereadable(full_path) == 0 or
         (response.changes and #response.changes > 0 and response.changes[1].search == "") then
        response.new_file = true
      end
    else
      target_buf = context.bufnr
    end

    -- Fail if no buffer or if it's the chat buffer
    if not target_buf or M.is_chat_buffer(target_buf) then
      chat.add_message('ai', '❌ **Error**: No valid target buffer. Specify a filename or open a code file.')
      return
    end

    -- Show diff in the target buffer
    diff.show(target_buf, response)

    -- Add navigation help
    chat.add_message('system', '✨ Changes ready! Use `<leader>ta` to accept change at cursor, `<leader>tr` to reject. Navigate with `]]` and `[[`.')

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

  -- Add conversation history if provided
  if opts.conversation_history then
    context.conversation_history = opts.conversation_history
  end

  -- Show thinking animation
  chat.show_thinking(config.get('model'))

  -- Send to provider
  M.send_to_provider(context, function(response, error)
    chat.hide_thinking()
    M.handle_response(response, error, context)
  end)
end

-- Helper function to check if buffer is chat - used everywhere
function M.is_chat_buffer(bufnr)
  if not bufnr then return true end
  return vim.api.nvim_buf_get_name(bufnr):match('Todo%-AI Chat') ~= nil
end

-- Find target buffer - fail if none found
function M.find_target_buffer()
  local init = require('todo-ai.init')

  -- Check visual target buffer
  if init.state.visual_target_buffer and not M.is_chat_buffer(init.state.visual_target_buffer) then
    return init.state.visual_target_buffer
  end

  -- Check current buffer
  local current = vim.api.nvim_get_current_buf()
  if not M.is_chat_buffer(current) then
    return current
  end

  -- No valid buffer found - fail
  return nil
end

return M