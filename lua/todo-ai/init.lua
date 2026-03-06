local M = {}
local scanner = require('todo-ai.scanner')
local diff = require('todo-ai.diff')
local chat = require('todo-ai.chat')
local config = require('todo-ai.config')

M.state = {
  current_todo = nil,
  pending_diff = nil,
  chat_buf = nil
}

function M.setup(opts)
  config.setup(opts or {})

  -- Initialize logger with config
  local logger = require('todo-ai.logger')
  logger.init(config.config)

  -- Check dependencies
  local deps = require('todo-ai.dependencies')
  deps.check_dependencies()

  -- Start Rust backend
  local backend = require('todo-ai.backend')
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local binary = plugin_dir .. "/rust/target/release/todo-ai-backend"
  if vim.fn.executable(binary) == 1 then
    backend.start(config.config)
  else
    error("todo-ai-backend binary not found at: " .. binary .. " — run 'make build-rust'")
  end

  -- Setup optional integrations
  local integrations = require('todo-ai.integrations')
  integrations.setup_all()

  -- Add command to view logs
  vim.api.nvim_create_user_command('TodoAILogs', function()
    vim.cmd('edit ' .. logger.LOG_FILE)
  end, {desc = 'View Todo-AI debug logs'})

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
  -- Use unified prompt system for ALL processing
  local unified_prompt = require('todo-ai.unified_prompt')
  unified_prompt.process({
    instruction = todo.instruction,
    todo = todo,
    bufnr = bufnr
  })
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
  diff.accept_at_cursor()
end

function M.reject_change()
  diff.reject_at_cursor()
end

function M.open_chat()
  -- Store the current buffer if it's not the chat buffer (for context)
  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)
  if not buf_name:match('Todo%-AI Chat') and buf_name ~= '' then
    M.state.last_code_buffer = current_buf
  end

  -- Always call create() which now handles existing buffers properly
  M.state.chat_buf = chat.create()
  chat.open(M.state.chat_buf)
end


function M.open_config()
  local config_path = vim.fn.expand(vim.fn.stdpath('config') .. '/lua/todo-ai/config.lua')
  vim.cmd('edit ' .. config_path)
end

-- Process all TODOs in the project
function M.process_project_todos()
  local unified_prompt = require('todo-ai.unified_prompt')

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

  -- Build instruction
  local instruction = [[Process all the TODOs found in the project.
CRITICAL: Return changes in a logical order for a developer to review:
1. Group related changes together
2. Order by dependency (foundational changes first)
3. Provide reasoning in the explanation for each change about WHY this order makes sense
4. Each change should include the file path in the description]]

  -- Create context for the backend
  local context = unified_prompt.create_context({
    mode = 'chat',
    instruction = instruction,
  })
  context.project_todos = formatted_todos
  context.mode = 'project_scan'

  -- Show thinking indicator
  chat.show_thinking(config.get('model'))

  -- Send through unified prompt (routes to Rust backend)
  unified_prompt.send_to_provider(context, function(response, err)
    chat.hide_thinking()
    unified_prompt.handle_response(response, err, context)
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
      local search_replace = require('todo-ai.search_replace')
      local modified_lines = search_replace.apply_changes(lines, changes)

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