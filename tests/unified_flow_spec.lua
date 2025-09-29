-- Test the single unified flow for all requests
describe("Unified Flow", function()
  local unified_prompt

  before_each(function()
    -- Clean state
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, buf, {force = true})
    end

    package.loaded['todo-ai.unified_prompt'] = nil
    unified_prompt = require('todo-ai.unified_prompt')
  end)

  it("all requests go through unified_prompt.process", function()
    -- Mock the send_to_provider to avoid actual API calls
    unified_prompt.send_to_provider = function(context, callback)
      -- Just call the callback with a mock response
      callback({mode = "chat", explanation = "test"}, nil)
    end

    -- Track calls to process
    local process_calls = 0
    local original_process = unified_prompt.process

    unified_prompt.process = function(opts)
      process_calls = process_calls + 1
      -- Verify required fields
      assert.truthy(opts.instruction)
      return original_process(opts)
    end

    -- 1. Chat mode
    unified_prompt.process({
      instruction = "test chat",
      bufnr = vim.api.nvim_get_current_buf()
    })
    assert.equals(1, process_calls)

    -- 2. Visual mode
    unified_prompt.process({
      instruction = "test visual",
      selected_text = "some code",
      start_line = 1,
      end_line = 5,
      bufnr = vim.api.nvim_get_current_buf()
    })
    assert.equals(2, process_calls)

    -- 3. TODO mode
    unified_prompt.process({
      instruction = "TODO: test todo",
      todo = {
        line = 10,
        instruction = "TODO: test todo"
      },
      bufnr = vim.api.nvim_get_current_buf()
    })
    assert.equals(3, process_calls)
  end)

  it("fails fast on missing instruction", function()
    -- Should error immediately
    local ok, err = pcall(unified_prompt.process, {
      bufnr = vim.api.nvim_get_current_buf()
    })
    assert.is_false(ok)
    assert.truthy(err:match("instruction is required"))
  end)

  it("response validation fails loudly", function()
    local validator = require('todo-ai.schema_validator')

    -- Missing mode field
    local valid, errors = validator.validate_response({
      changes = {{search = "", replace = "code"}},
      filename = "test.py",
      explanation = "test"
    })
    assert.is_false(valid)
    assert.truthy(errors[1]:match("MISSING 'mode'"))

    -- Missing filename for changes mode
    valid, errors = validator.validate_response({
      mode = "changes",
      changes = {{search = "", replace = "code"}},
      explanation = "test"
    })
    assert.is_false(valid)
    assert.truthy(errors[1]:match("MISSING 'filename'"))

    -- Valid response passes
    valid, errors = validator.validate_response({
      mode = "changes",
      filename = "test.py",
      changes = {{search = "", replace = "code"}},
      explanation = "test"
    })
    assert.is_true(valid)
  end)
end)