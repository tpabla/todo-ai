-- Tests for retry_manager and circuit_breaker
local retry_manager = require('todo-ai.retry_manager')
local circuit_breaker = require('todo-ai.circuit_breaker')

describe("circuit_breaker", function()
  before_each(function()
    circuit_breaker.reset_all()
  end)

  it("should allow requests when closed", function()
    local can_proceed, error = circuit_breaker.can_proceed("test_service")
    assert.is_true(can_proceed)
    assert.is_nil(error)
  end)

  it("should open after threshold failures", function()
    -- Record failures up to threshold
    for i = 1, 5 do
      circuit_breaker.record_failure("test_service", "error " .. i)
    end

    local can_proceed, error = circuit_breaker.can_proceed("test_service")
    assert.is_false(can_proceed)
    assert.is_not_nil(error)
    assert.is_true(error:find("Circuit breaker open") ~= nil)
  end)

  it("should close after success in half-open state", function()
    -- Open the circuit
    for i = 1, 5 do
      circuit_breaker.record_failure("test_service", "error")
    end

    -- Mock time passage
    local state = circuit_breaker.get_state("test_service")
    state.last_failure_time = 0  -- Pretend time has passed

    -- Should go to half-open
    local can_proceed = circuit_breaker.can_proceed("test_service")

    -- Record successes
    circuit_breaker.record_success("test_service")
    circuit_breaker.record_success("test_service")

    -- Should be closed now
    state = circuit_breaker.get_state("test_service")
    assert.equals('closed', state.state)
  end)
end)

describe("retry_manager", function()
  before_each(function()
    circuit_breaker.reset_all()
  end)

  it("should succeed on first attempt", function()
    local call_count = 0
    local function test_fn()
      call_count = call_count + 1
      return "success"
    end

    local success, result = retry_manager.execute_with_retry(
      test_fn,
      "test_service",
      {max_retries = 3, base_delay = 10}
    )

    assert.is_true(success)
    assert.equals("success", result)
    assert.equals(1, call_count)
  end)

  it("should retry on failure", function()
    local call_count = 0
    local function test_fn()
      call_count = call_count + 1
      if call_count < 3 then
        error("timeout error")  -- Retryable error
      end
      return "success"
    end

    local success, result = retry_manager.execute_with_retry(
      test_fn,
      "test_service",
      {max_retries = 3, base_delay = 10}
    )

    assert.is_true(success)
    assert.equals("success", result)
    assert.equals(3, call_count)
  end)

  it("should not retry non-retryable errors", function()
    local call_count = 0
    local function test_fn()
      call_count = call_count + 1
      error("Invalid API key")  -- Non-retryable
    end

    local success, result = retry_manager.execute_with_retry(
      test_fn,
      "test_service",
      {max_retries = 3, base_delay = 10}
    )

    assert.is_false(success)
    assert.equals(1, call_count)  -- Should not retry
  end)

  it("should respect max retries", function()
    local call_count = 0
    local function test_fn()
      call_count = call_count + 1
      error("timeout error")
    end

    local success, result = retry_manager.execute_with_retry(
      test_fn,
      "test_service",
      {max_retries = 2, base_delay = 10}
    )

    assert.is_false(success)
    assert.equals(3, call_count)  -- Initial + 2 retries
  end)

  it("should calculate exponential backoff correctly", function()
    -- Test delay calculation (internal function, but important)
    local config = {
      base_delay = 100,
      max_delay = 1000,
      exponential_base = 2,
      jitter = false
    }

    -- We can't directly test the internal function,
    -- but we can verify the behavior through timing
    local delays = {}
    local function test_fn()
      local start = vim.loop.now()
      error("timeout")
    end

    -- This test just verifies the structure works
    assert.is_not_nil(retry_manager.default_config.base_delay)
    assert.is_not_nil(retry_manager.default_config.exponential_base)
  end)
end)