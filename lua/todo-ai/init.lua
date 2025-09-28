local M = {}
local scanner = require('todo-ai.scanner')
local diff = require('todo-ai.diff')
local chat = require('todo-ai.chat')
local config = require('todo-ai.config')
local providers = require('todo-ai.providers')

M.state = {
  current_todo = nil,
  pending_diff = nil,
  chat_buf = nil
}

function M.setup(opts)
  config.setup(opts or {})

  -- Check dependencies
  local deps = require('todo-ai.dependencies')
  deps.check_dependencies()
  deps.setup_render_markdown()

  -- Setup minimalist diff highlights
  require('todo-ai.diff').setup_highlights()

  -- Setup providers
  providers.setup()
end


function M.scan_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local todos = scanner.find_todos(bufnr)

  if #todos == 0 then
    vim.notify('No TODO: @ai found in current buffer', vim.log.levels.INFO)
    return
  end

  -- Process first TODO found
  M.process_todo(todos[1], bufnr)
end

function M.auto_scan()
  if not config.get('auto_scan') then
    return
  end
  M.scan_buffer()
end

function M.process_todo(todo, bufnr)
  M.state.current_todo = todo

  -- Open chat immediately and show processing message
  M.open_chat()
  chat.add_message('user', 'Processing: ' .. todo.instruction)

  -- Show thinking with model name
  local model = config.get('model')
  chat.show_thinking(model)

  -- Gather context
  local context = M.gather_context(bufnr, todo)

  -- Get provider
  local provider_name = config.get('provider')
  local provider = providers.get(provider_name)

  if not provider then
    chat.hide_thinking()
    chat.add_message('ai', 'Error: Provider ' .. provider_name .. ' not found')
    vim.notify('Error: Provider ' .. provider_name .. ' not found', vim.log.levels.ERROR)
    return
  end

  -- Build context string
  local context_str = vim.fn.json_encode(context)

  -- Request completion from provider
  provider.complete_async(todo.instruction, context_str, {
    model = config.get('model'),
    temperature = config.get('temperature')
  }, function(response, error)
    -- Hide thinking spinner
    chat.hide_thinking()

    if error then
      chat.add_message('ai', 'Error: ' .. error)
      vim.notify('Error: ' .. error, vim.log.levels.ERROR)
      return
    end

    -- Display diff based on new schema
    if response.changes and #response.changes > 0 then
      -- TODO replacements use changes format now
      local change = response.changes[1]
      diff.show_range(bufnr, change.start_line or todo.line, change.end_line or todo.line, change.code, change.description or response.explanation)
      M.state.pending_diff = response
    elseif response.code_snippet then
      -- Just informational, no diff
      M.state.pending_diff = nil
    end

    -- Store the target buffer filetype for proper formatting
    response.target_filetype = vim.bo[bufnr].filetype

    -- Add formatted response to chat
    local formatted = M.format_response(response)
    if formatted and formatted ~= '' then
      chat.add_message('ai', formatted)
    else
      -- Fallback to simple display
      if response.changes then
        chat.add_message('ai', 'Generated changes for lines')
      elseif response.code_snippet then
        chat.add_message('ai', 'Code example:\n```\n' .. response.code_snippet .. '\n```')
      end
      if response.explanation then
        chat.add_message('ai', response.explanation)
      end
    end
  end)
end

function M.gather_context(bufnr, todo)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local file_content = table.concat(lines, '\n')
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  -- Load project context
  local context_module = require('todo-ai.context_compact')
  local project_context = context_module.get_for_prompt()

  -- Get other open buffers for context (read-only)
  local other_buffers = {}
  for _, other_bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if other_bufnr ~= bufnr and vim.api.nvim_buf_is_loaded(other_bufnr) and vim.bo[other_bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(other_bufnr)
      if name ~= '' and not name:match('^Todo%-AI Chat') then
        local other_lines = vim.api.nvim_buf_get_lines(other_bufnr, 0, math.min(100, vim.api.nvim_buf_line_count(other_bufnr)), false)
        table.insert(other_buffers, {
          path = name,
          filename = vim.fn.fnamemodify(name, ':t'),
          filetype = vim.bo[other_bufnr].filetype,
          content = table.concat(other_lines, '\n')
        })
      end
    end
  end

  -- Get project root
  local project_root = vim.fn.getcwd()
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if git_root ~= '' then
    project_root = git_root
  end

  -- Read .todoai cache if exists
  local cache_path = project_root .. '/.todoai/context.json'
  local cached_context = nil
  if vim.fn.filereadable(cache_path) == 1 then
    local cache_file = io.open(cache_path, 'r')
    if cache_file then
      cached_context = vim.fn.json_decode(cache_file:read('*all'))
      cache_file:close()
    end
  end

  return {
    file_content = file_content,
    file_path = file_path,
    language = vim.bo[bufnr].filetype,
    line_number = todo.line,
    surrounding_lines = M.get_surrounding_lines(lines, todo.line, 20),
    project_root = project_root,
    project_context = project_context,  -- Compact project context
    cached_context = cached_context,
    other_buffers = other_buffers  -- Additional context from open buffers
  }
end

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

function M.accept_change()
  if not M.state.pending_diff then
    vim.notify('No pending changes to accept', vim.log.levels.INFO)
    return
  end

  diff.accept(M.state.current_todo)
  M.state.pending_diff = nil
  M.state.current_todo = nil

  vim.notify('Changes accepted', vim.log.levels.INFO)
end

function M.reject_change()
  if not M.state.pending_diff then
    vim.notify('No pending changes to reject', vim.log.levels.INFO)
    return
  end

  diff.reject()
  M.state.pending_diff = nil
  M.state.current_todo = nil

  vim.notify('Changes rejected', vim.log.levels.INFO)
end

function M.format_response(response)
  -- Format the response for display
  local formatted = {}

  -- Add thinking/reasoning section if present
  if response.thinking_formatted then
    table.insert(formatted, response.thinking_formatted)
  end

  -- Add generated code or changes
  if response.changes then
    table.insert(formatted, '### 📄 Code Changes')
    for i, change in ipairs(response.changes) do
      table.insert(formatted, string.format('\n**Change %d** (lines %d-%d): %s\n```%s\n%s\n```',
        i, change.start_line, change.end_line,
        change.description or '',
        vim.bo.filetype or '',
        change.code))
    end
  elseif response.code_snippet then
    table.insert(formatted, '### 📄 Code Example\n```' .. (vim.bo.filetype or '') .. '\n' .. response.code_snippet .. '\n```')
  end

  -- Add explanation if different from thinking
  if response.explanation and response.explanation ~= "" and response.explanation ~= "Generated code" then
    table.insert(formatted, '\n### 💬 Explanation\n' .. response.explanation)
  end

  -- Add parsed sections if interesting
  if response.parsed_sections and type(response.parsed_sections) == 'table' then
    local has_interesting = false
    for k, v in pairs(response.parsed_sections) do
      if k ~= 'code' and k ~= 'explanation' and k ~= 'thinking' then
        has_interesting = true
        break
      end
    end

    if has_interesting then
      table.insert(formatted, '\n### 📋 Additional Context')
      for k, v in pairs(response.parsed_sections) do
        if k ~= 'code' and k ~= 'explanation' and k ~= 'thinking' then
          table.insert(formatted, string.format('**%s**: %s', k, tostring(v)))
        end
      end
    end
  end

  -- Only show format detection if there was an error parsing
  if response.error and response.format_detected then
    table.insert(formatted, '\n> *Format detection failed: ' .. response.format_detected .. '*')
  end

  return table.concat(formatted, '\n')
end

function M.open_chat()
  if not M.state.chat_buf or not vim.api.nvim_buf_is_valid(M.state.chat_buf) then
    M.state.chat_buf = chat.create()
  end

  chat.open(M.state.chat_buf)
end


function M.open_config()
  local config_path = vim.fn.expand(vim.fn.stdpath('config') .. '/lua/todo-ai/config.lua')
  vim.cmd('edit ' .. config_path)
end

return M