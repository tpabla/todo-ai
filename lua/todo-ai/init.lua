local M = {}
local scanner = require('todo-ai.scanner')
local chat = require('todo-ai.chat')
local config = require('todo-ai.config')

M.state = {
  chat_buf = nil,
}

function M.setup(opts)
  config.setup(opts or {})

  local logger = require('todo-ai.logger')
  logger.init(config.config)

  -- Start pi client
  local pi = require('todo-ai.pi_client')
  pi.start(config.config)
  chat._setup_pi_handlers()

  -- Setup optional integrations
  local integrations = require('todo-ai.integrations')
  integrations.setup_all()

  -- Log viewer
  vim.api.nvim_create_user_command('TodoAILogs', function()
    vim.cmd('edit ' .. logger.LOG_FILE)
  end, { desc = 'View Todo-AI debug logs' })

  -- @ai highlighting
  local ai_highlight = config.get('ai_highlight')
  if ai_highlight and ai_highlight.enabled then
    vim.api.nvim_set_hl(0, "TodoAI", {
      fg = ai_highlight.fg,
      bg = ai_highlight.bg,
      bold = ai_highlight.bold,
    })
    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
      group = vim.api.nvim_create_augroup("TodoAI_Highlighting", { clear = true }),
      pattern = "*",
      callback = function()
        pcall(function() vim.fn.matchadd("TodoAI", "@ai.*", 10, -1) end)
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

  M.process_todo(todos[1], bufnr)
end

function M.auto_scan()
  if not config.get('auto_scan') then return end
  M.scan_buffer()
end

function M.process_todo(todo, bufnr)
  local pi = require('todo-ai.pi_client')
  local ctx = require('todo-ai.context')

  M.open_chat()

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  chat.add_message('user', 'Processing TODO: ' .. todo.instruction)

  local context_text = ctx.build({
    bufnr = bufnr,
    file_path = file_path,
    todo = todo,
  })

  local message = string.format(
    "Resolve this TODO in %s at line %d: %s",
    file_path, todo.line, todo.instruction
  )

  if context_text then
    message = "<neovim_context>\n" .. context_text .. "\n</neovim_context>\n\n" .. message
  end

  chat.show_thinking()
  pi.prompt(message)
end

function M.open_chat()
  M.state.chat_buf = chat.create()
  chat.open(M.state.chat_buf)
end

function M.process_project_todos()
  local pi = require('todo-ai.pi_client')
  local ctx = require('todo-ai.context')

  M.open_chat()

  chat.add_message('system', '🔍 Scanning project for TODOs...')
  local todos_by_file = scanner.scan_project()

  if vim.tbl_isempty(todos_by_file) then
    chat.add_message('system', 'No @ai TODOs found in the project')
    return
  end

  local formatted_todos = scanner.format_project_todos(todos_by_file)
  local context_text = ctx.build({})

  local message = "Resolve all the following TODOs in this project:\n\n" .. formatted_todos
  if context_text then
    message = "<neovim_context>\n" .. context_text .. "\n</neovim_context>\n\n" .. message
  end

  chat.show_thinking()
  pi.prompt(message)
end

function M.abort()
  local pi = require('todo-ai.pi_client')
  pi.abort()
  chat.hide_thinking()
  chat.add_message('system', '⏹ Aborted.')
end

return M
