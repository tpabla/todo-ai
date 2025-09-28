local M = {}
local scanner = require('todo-ai.scanner')
local diff = require('todo-ai.diff_native')
local chat = require('todo-ai.chat')
local config = require('todo-ai.config')
-- Providers will be loaded after config setup
local providers

M.state = {
  current_todo = nil,
  pending_diff = nil,
  chat_buf = nil
}

function M.setup(opts)
  config.setup(opts or {})

  -- Load providers after config is set up
  providers = require('todo-ai.providers')
  providers.setup()

  -- Check dependencies
  local deps = require('todo-ai.dependencies')
  deps.check_dependencies()


  -- Setup optional integrations
  local integrations = require('todo-ai.integrations')
  integrations.setup_all()

  -- mini.diff handles its own highlights

  -- Setup @ai highlighting if enabled
  local ai_highlight = config.get('ai_highlight')
  if ai_highlight and ai_highlight.enabled then
    vim.api.nvim_set_hl(0, "TodoAI", {
      fg = ai_highlight.fg,
      bg = ai_highlight.bg,
      bold = ai_highlight.bold,
    })

    -- Setup @ai highlighting autocmd
    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
      group = vim.api.nvim_create_augroup("TodoAI_Highlighting", { clear = true }),
      pattern = "*",
      callback = function()
        -- Add @ai highlighting (highlight from @ai to end of line for fun!)
        pcall(function()
          vim.fn.matchadd("TodoAI", "@ai.*", 10, -1)
        end)
      end,
    })
  end

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

  -- Get provider (ensure providers is loaded)
  if not providers then
    providers = require('todo-ai.providers')
    providers.setup()
  end
  local provider_name = config.get('provider')
  local provider = providers.get(provider_name)

  if not provider then
    chat.hide_thinking()
    chat.add_message('ai', '❌ Error: Provider ' .. provider_name .. ' not found')

    -- Show helpful non-blocking notification
    vim.schedule(function()
      vim.notify(
        string.format("❌ Provider '%s' not configured\n\nPlease check your config:\n• Set provider to 'claude', 'openai', or 'ollama'\n• Ensure API key is set if required", provider_name),
        vim.log.levels.ERROR,
        { title = "Todo-AI Configuration", timeout = 5000 }
      )
    end)
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
      local error_msg = type(error) == 'string' and error or vim.inspect(error)
      chat.add_message('ai', '❌ Error: ' .. error_msg)

      -- Show non-blocking notification with more context
      vim.schedule(function()
        vim.notify(
          string.format("❌ TODO-AI Request Failed\n\n%s\n\nCheck your API key and network connection.", error_msg),
          vim.log.levels.ERROR,
          { title = "Todo-AI", timeout = 5000 }
        )
      end)
      return
    end

    -- Display changes (SEARCH/REPLACE format)
    if response.changes then
      -- Use new optimized diff display, passing the full raw TODO line
      local todo_text = ""
      if M.state.current_todo then
        -- Use the full_line which contains the complete TODO including "TODO: @ai"
        todo_text = M.state.current_todo.full_line or ("TODO: @ai " .. M.state.current_todo.instruction)
      end
      diff.show_response(bufnr, response, todo_text)
      M.state.pending_diff = response
    else
      -- No diff to display
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

  -- Add SEARCH/REPLACE changes with proper language formatting
  if response.changes then
    local language = response.language or vim.bo.filetype or 'text'
    table.insert(formatted, string.format('### 📄 Changes (%s)', language:gsub('^%l', string.upper)))

    for i, change in ipairs(response.changes) do
      if change.search and change.replace then
        table.insert(formatted, string.format('\n**Change %d**: %s',
          i, change.description or "Update"))
        -- Show search/replace in a clear format
        table.insert(formatted, string.format('```%s', language))
        table.insert(formatted, '<<<<<<< SEARCH')
        table.insert(formatted, change.search)
        table.insert(formatted, '=======')
        table.insert(formatted, change.replace)
        table.insert(formatted, '>>>>>>> REPLACE')
        table.insert(formatted, '```')
      end
    end
  end

  -- Add explanation if different from thinking
  if response.explanation and response.explanation ~= "" and response.explanation ~= "Generated code" then
    table.insert(formatted, '\n### 💬 Explanation\n' .. response.explanation)
  end

  -- Add parsed sections if interesting
  if response.parsed_sections and type(response.parsed_sections) == 'table' then
    -- Skip Additional Context section entirely since diffs are now properly formatted
    -- Only show if there are truly unique fields we haven't displayed
    local has_interesting = false
    for k, v in pairs(response.parsed_sections) do
      -- Skip all standard fields that are already displayed elsewhere
      if k ~= 'code' and k ~= 'explanation' and k ~= 'thinking' and
         k ~= 'changes' and k ~= 'edits' and k ~= 'code_snippet' and
         k ~= 'new_file' and k ~= 'replace_buffer' and
         k ~= 'language' then  -- Also skip changes and language
        has_interesting = true
        break
      end
    end

    -- Only show Additional Context if there are truly unique fields
    if has_interesting then
      table.insert(formatted, '\n### 📋 Additional Context')
      for k, v in pairs(response.parsed_sections) do
        if k ~= 'code' and k ~= 'explanation' and k ~= 'thinking' and
           k ~= 'changes' and k ~= 'edits' and k ~= 'code_snippet' and
           k ~= 'new_file' and k ~= 'replace_buffer' and
           k ~= 'language' then  -- Also skip changes and language
          -- Format value based on type
          local value_str
          if type(v) == 'table' then
            -- Only show first few items for arrays to avoid clutter
            if #v > 3 then
              value_str = string.format('[%d items]', #v)
            else
              value_str = vim.inspect(v, {depth = 1, indent = "  "})
            end
          elseif type(v) == 'string' then
            -- Truncate long strings
            if #v > 100 then
              value_str = v:sub(1, 100) .. '...'
            else
              value_str = v
            end
          else
            value_str = tostring(v)
          end
          table.insert(formatted, string.format('**%s**: %s', k, value_str))
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

-- Process all TODOs in the project
function M.process_project_todos()
  local scanner = require('todo-ai.scanner')
  local chat = require('todo-ai.chat')
  local config = require('todo-ai.config')
  local prompt_builder = require('todo-ai.prompt_builder')

  -- Open chat window first
  M.open_chat()

  -- Scan the project
  chat.add_message('system', '🔍 Scanning project for TODOs...')
  local todos_by_file = scanner.scan_project()

  if vim.tbl_isempty(todos_by_file) then
    chat.add_message('system', 'No @ai TODOs found in the project')
    return
  end

  -- Format all TODOs for context
  local formatted_todos = scanner.format_project_todos(todos_by_file)

  -- Build special prompt for project-wide TODOs
  local instruction = [[Process all the TODOs found in the project.
CRITICAL: Return changes in a logical order for a developer to review:
1. Group related changes together
2. Order by dependency (foundational changes first)
3. Provide reasoning in the explanation for each change about WHY this order makes sense
4. Each change should include the file path in the description]]

  local context = {
    project_todos = formatted_todos,
    mode = 'project_scan'
  }

  -- Get provider and process
  local provider_name = config.get('provider')
  local provider = require('todo-ai.providers')[provider_name]

  if not provider then
    chat.add_message('ai', 'Error: Provider ' .. provider_name .. ' not found')
    return
  end

  -- Show thinking indicator
  chat.show_thinking()

  -- Request completion
  provider.complete_async(instruction, vim.fn.json_encode(context), {
    model = config.get('model'),
    temperature = config.get('temperature')
  }, function(response, error)
    chat.hide_thinking()

    if error then
      chat.add_message('ai', 'Error: ' .. error)
      vim.notify('Error: ' .. error, vim.log.levels.ERROR)
      return
    end

    -- For project-wide changes, we need to handle multiple files
    if response.changes then
      -- Group changes by file
      local changes_by_file = {}
      for _, change in ipairs(response.changes) do
        -- Extract file from description or use current buffer
        local file = change.file or vim.api.nvim_get_current_buf()
        if not changes_by_file[file] then
          changes_by_file[file] = {}
        end
        table.insert(changes_by_file[file], change)
      end

      -- Store for sequential processing
      M.state.project_changes = changes_by_file
      M.state.current_file_index = 1
      local files = vim.tbl_keys(changes_by_file)
      M.state.project_files = files

      -- Start with first file
      if #files > 0 then
        local first_file = files[1]
        vim.cmd('edit ' .. first_file)

        -- Show diff for first file
        local bufnr = vim.api.nvim_get_current_buf()
        diff.show_response(bufnr, {changes = changes_by_file[first_file], explanation = response.explanation})
      end
    end

    -- Add to chat
    local formatted = M.format_response(response)
    if formatted and formatted ~= '' then
      chat.add_message('ai', formatted)
    end
  end)
end

-- Accept all project changes and save files
function M.accept_all_project_changes()
  if not M.state.project_changes then
    vim.notify("No project changes to accept", vim.log.levels.WARN)
    return
  end

  local success_count = 0
  local error_count = 0

  -- Process each file
  for file_path, changes in pairs(M.state.project_changes) do
    -- Read the file
    local file = io.open(file_path, "r")
    if file then
      local lines = {}
      for line in file:lines() do
        table.insert(lines, line)
      end
      file:close()

      -- Apply changes using schema helper
      local schema = require('todo-ai.schema')
      local modified_lines = schema.apply_changes(lines, changes)

      -- Write back to file
      file = io.open(file_path, "w")
      if file then
        for _, line in ipairs(modified_lines) do
          file:write(line .. "\n")
        end
        file:close()
        success_count = success_count + 1

        -- Clean up TODOs for this file
        M.cleanup_todos_in_file(file_path, changes)
      else
        error_count = error_count + 1
        vim.notify("Failed to write: " .. file_path, vim.log.levels.ERROR)
      end
    else
      error_count = error_count + 1
      vim.notify("Failed to read: " .. file_path, vim.log.levels.ERROR)
    end
  end

  -- Clear state
  M.state.project_changes = nil
  M.state.project_files = nil
  M.state.current_file_index = nil

  -- Report results
  local msg = string.format("✅ Applied changes to %d files", success_count)
  if error_count > 0 then
    msg = msg .. string.format(" (⚠️  %d errors)", error_count)
  end
  vim.notify(msg, vim.log.levels.INFO)

  -- Clear any open diffs
  diff.clear_diff()
end

-- Helper to cleanup TODOs in a specific file
function M.cleanup_todos_in_file(file_path, changes)
  -- Collect all todo_text from changes
  local todos_to_remove = {}
  for _, change in ipairs(changes) do
    if change.todo_text then
      todos_to_remove[change.todo_text] = true
    end
  end

  if not next(todos_to_remove) then
    return
  end

  -- Read file again
  local file = io.open(file_path, "r")
  if not file then
    return
  end

  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  -- Detect comment style for this file type
  local ext = file_path:match("%.([^%.]+)$")
  local comment_start = "//"  -- default

  if ext == "lua" then
    comment_start = "--"
  elseif ext == "py" or ext == "sh" then
    comment_start = "#"
  elseif ext == "vim" then
    comment_start = '"'
  end

  -- Find and remove TODOs
  local lines_to_remove = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line:match("TODO:%s*@ai%s+") then
      -- Extract instruction and check if we should remove it
      local instruction = line:match("@ai%s+(.+)$")
      if instruction then
        instruction = instruction:gsub("^%s+", ""):gsub("%s+$", "")

        -- Check if this TODO should be removed
        for todo_text, _ in pairs(todos_to_remove) do
          if instruction == todo_text or todo_text:find("^" .. vim.pesc(instruction)) then
            -- Mark this line and any continuation lines for removal
            lines_to_remove[i] = true

            -- Look for continuation lines
            local indent = line:match("^(%s*)")
            local j = i + 1
            while j <= #lines do
              local next_line = lines[j]
              local next_indent = next_line:match("^(%s*)")

              if next_indent == indent and next_line:match("^%s*" .. vim.pesc(comment_start)) then
                if not next_line:match("TODO") and not next_line:match("@ai") then
                  lines_to_remove[j] = true
                  j = j + 1
                else
                  break
                end
              else
                break
              end
            end
            break
          end
        end
      end
    end
    i = i + 1
  end

  -- Write back without removed lines
  if next(lines_to_remove) then
    file = io.open(file_path, "w")
    if file then
      for idx, line in ipairs(lines) do
        if not lines_to_remove[idx] then
          file:write(line .. "\n")
        end
      end
      file:close()
    end
  end
end

return M