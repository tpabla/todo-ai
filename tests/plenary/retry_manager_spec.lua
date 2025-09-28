-- Tests for simplified retry_manager - focus on logic, not timing
local retry_manager = require('todo-ai.retry_manager')

describe("retry_manager", function()
  it("should succeed on first attempt", function()
    local call_count = 0
    local function test_fn()
      call_count = call_count + 1
      return "success"
    end

    local success, result = retry_manager.execute_with_retry(test_fn, "test_service")

    assert.is_true(success)
    assert.equals("success", result)
    assert.equals(1, call_count)
  end)

  it("should not retry non-retryable errors", function()
    local call_count = 0
    local function test_fn()
      call_count = call_count + 1
      error("Invalid API key")  -- Non-retryable
    end

    local success, result = retry_manager.execute_with_retry(test_fn, "test_service")

    assert.is_false(success)
    assert.equals(1, call_count)  -- Should not retry
  end)

  it("should detect retryable vs non-retryable errors correctly", function()
    local retryable_errors = {"timeout", "network", "rate limit", "429", "503"}
    local non_retryable_errors = {"Invalid API key", "Authentication failed", "Permission denied"}

    -- Test retryable errors (should retry once then succeed)
    for _, error_msg in ipairs(retryable_errors) do
      local call_count = 0
      local function test_fn()
        call_count = call_count + 1
        if call_count == 1 then
          error(error_msg)
        end
        return "success"
      end

      local success, result = retry_manager.execute_with_retry(test_fn, "test")
      assert.is_true(success, "Should retry for: " .. error_msg)
      assert.equals(2, call_count, "Should have retried for: " .. error_msg)
    end

    -- Test non-retryable errors (should not retry)
    for _, error_msg in ipairs(non_retryable_errors) do
      local call_count = 0
      local function test_fn()
        call_count = call_count + 1
        error(error_msg)
      end

      local success, result = retry_manager.execute_with_retry(test_fn, "test")
      assert.is_false(success, "Should not retry for: " .. error_msg)
      assert.equals(1, call_count, "Should not have retried for: " .. error_msg)
    end
  end)

  it("should handle async execution without errors", function()
    local completed = false
    local success_result, error_result = nil, nil

    retry_manager.execute_with_retry_async(
      function(callback) callback(true, "async_success") end,
      "test_async",
      nil,
      function(success, result)
        completed = true
        success_result, error_result = success, result
      end
    )

    -- Simple wait - we're testing logic, not timing
    vim.wait(50, function() return completed end)

    assert.is_true(completed)
    assert.is_true(success_result)
    assert.equals("async_success", error_result)
  end)
end)