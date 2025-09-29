-- Simple test for chat buffer protection
describe("Chat Buffer Protection", function()
  local unified_prompt
  local chat

  before_each(function()
    -- Clean state
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, buf, {force = true})
    end

    -- Require fresh modules
    package.loaded['todo-ai.unified_prompt'] = nil
    package.loaded['todo-ai.chat'] = nil
    package.loaded['todo-ai.init'] = nil
    unified_prompt = require('todo-ai.unified_prompt')
    chat = require('todo-ai.chat')
  end)

  it("blocks chat buffer modification", function()
    -- Create a buffer with chat name
    local chat_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(chat_buf, 'Todo-AI Chat')

    -- Mock response trying to modify it (with required filename field)
    local response = {
      mode = "changes",
      filename = "test.py",  -- Required field
      changes = {{search = "", replace = "bad code"}},
      explanation = "test"
    }

    -- Mock context pointing to chat buffer
    local context = {
      bufnr = chat_buf,
      mode = "chat"
    }

    -- This should fail early due to chat buffer check
    unified_prompt.handle_response(response, nil, context)

    -- Buffer should remain empty (no modifications)
    local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
    assert.equals(1, #lines) -- Empty buffer has one empty line
    assert.equals("", lines[1])
  end)

  it("returns nil when only chat buffer exists", function()
    -- Create only chat buffer
    local chat_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(chat_buf, 'Todo-AI Chat')
    vim.api.nvim_set_current_buf(chat_buf)

    -- Should return nil (no valid target)
    local target = unified_prompt.find_target_buffer()
    assert.is_nil(target)
  end)

  it("finds code buffer when available", function()
    -- Create code buffer first and set as current
    local code_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(code_buf, "/test/file.lua")
    vim.api.nvim_set_current_buf(code_buf)

    -- Store it in state as visual target
    local init = require('todo-ai.init')
    init.state.visual_target_buffer = code_buf

    -- Now create and switch to chat buffer
    local chat_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(chat_buf, 'Todo-AI Chat')
    vim.api.nvim_set_current_buf(chat_buf)

    -- Should find code buffer via visual_target_buffer
    local target = unified_prompt.find_target_buffer()
    assert.equals(code_buf, target)
  end)
end)