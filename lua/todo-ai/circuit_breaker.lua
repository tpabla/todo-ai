---Circuit breaker pattern for API resilience
---@class CircuitBreaker
local M = {}

---@class CircuitBreakerState
---@field failures number Number of consecutive failures
---@field last_failure_time number Timestamp of last failure
---@field state 'closed'|'open'|'half_open' Circuit state
---@field success_count number Successful calls in half-open state
local circuit_states = {}

-- Configuration
M.config = {
  failure_threshold = 5,      -- Open circuit after this many failures
  success_threshold = 2,       -- Close circuit after this many successes in half-open
  timeout = 60000,            -- Time in ms before trying half-open state
  reset_timeout = 300000,     -- Time in ms to fully reset statistics
}

---Initialize circuit breaker for a service
---@param service_name string
function M.init(service_name)
  if not circuit_states[service_name] then
    circuit_states[service_name] = {
      failures = 0,
      last_failure_time = 0,
      state = 'closed',
      success_count = 0,
    }
  end
end

---Check if circuit allows request
---@param service_name string
---@return boolean can_proceed
---@return string|nil error_message
function M.can_proceed(service_name)
  M.init(service_name)
  local circuit = circuit_states[service_name]

  -- Check if we should reset statistics
  if os.time() * 1000 - circuit.last_failure_time > M.config.reset_timeout then
    circuit.failures = 0
    circuit.state = 'closed'
    circuit.success_count = 0
  end

  if circuit.state == 'open' then
    -- Check if timeout has passed to try half-open
    if os.time() * 1000 - circuit.last_failure_time > M.config.timeout then
      circuit.state = 'half_open'
      circuit.success_count = 0
      return true
    end
    return false, string.format("Circuit breaker open for %s (failures: %d)",
                               service_name, circuit.failures)
  end

  return true
end

---Record successful call
---@param service_name string
function M.record_success(service_name)
  M.init(service_name)
  local circuit = circuit_states[service_name]

  if circuit.state == 'half_open' then
    circuit.success_count = circuit.success_count + 1
    if circuit.success_count >= M.config.success_threshold then
      -- Circuit can be closed
      circuit.state = 'closed'
      circuit.failures = 0
      circuit.success_count = 0
    end
  elseif circuit.state == 'closed' then
    -- Reset failure count on success
    circuit.failures = 0
  end
end

---Record failed call
---@param service_name string
---@param error_message string
function M.record_failure(service_name, error_message)
  M.init(service_name)
  local circuit = circuit_states[service_name]

  circuit.failures = circuit.failures + 1
  circuit.last_failure_time = os.time() * 1000

  if circuit.state == 'half_open' then
    -- Immediately open circuit again on failure in half-open state
    circuit.state = 'open'
  elseif circuit.failures >= M.config.failure_threshold then
    -- Open the circuit
    circuit.state = 'open'
  end
end

---Get circuit state
---@param service_name string
---@return table state
function M.get_state(service_name)
  M.init(service_name)
  return vim.deepcopy(circuit_states[service_name])
end

---Reset circuit breaker
---@param service_name string
function M.reset(service_name)
  circuit_states[service_name] = nil
end

---Reset all circuit breakers
function M.reset_all()
  circuit_states = {}
end

return M