---@class TestRunner
---@field suites table<string, TestSuite>
---@field results TestResults
local M = {}

---@class TestSuite
---@field name string
---@field tests table<string, function>
---@field before_each function|nil
---@field after_each function|nil
---@field before_all function|nil
---@field after_all function|nil

---@class TestResults
---@field total number
---@field passed number
---@field failed number
---@field errors table[]
---@field duration number

M.suites = {}
M.results = {
  total = 0,
  passed = 0,
  failed = 0,
  errors = {},
  duration = 0
}

-- ANSI color codes for terminal output
M.colors = {
  reset = '\27[0m',
  red = '\27[31m',
  green = '\27[32m',
  yellow = '\27[33m',
  blue = '\27[34m',
  magenta = '\27[35m',
  cyan = '\27[36m',
  bold = '\27[1m',
}

---Create a new test suite
---@param name string
---@return TestSuite
function M.describe(name)
  local suite = {
    name = name,
    tests = {},
    before_each = nil,
    after_each = nil,
    before_all = nil,
    after_all = nil,
  }

  M.suites[name] = suite
  return suite
end

---Add a test to the current suite
---@param suite TestSuite
---@param name string
---@param test_fn function
function M.it(suite, name, test_fn)
  suite.tests[name] = test_fn
end

---Assert helper functions
M.assert = {}

---Assert equality
---@param actual any
---@param expected any
---@param message string|nil
function M.assert.equals(actual, expected, message)
  if actual ~= expected then
    error(string.format(
      "%s\nExpected: %s\nActual: %s",
      message or "Assertion failed",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

---Assert deep equality
---@param actual any
---@param expected any
---@param message string|nil
function M.assert.deep_equals(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(string.format(
      "%s\nExpected: %s\nActual: %s",
      message or "Deep equality assertion failed",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

---Assert truthy
---@param value any
---@param message string|nil
function M.assert.truthy(value, message)
  if not value then
    error(message or string.format("Expected truthy value, got: %s", vim.inspect(value)))
  end
end

---Assert falsy
---@param value any
---@param message string|nil
function M.assert.falsy(value, message)
  if value then
    error(message or string.format("Expected falsy value, got: %s", vim.inspect(value)))
  end
end

---Assert nil
---@param value any
---@param message string|nil
function M.assert.is_nil(value, message)
  if value ~= nil then
    error(message or string.format("Expected nil, got: %s", vim.inspect(value)))
  end
end

---Assert not nil
---@param value any
---@param message string|nil
function M.assert.not_nil(value, message)
  if value == nil then
    error(message or "Expected non-nil value")
  end
end

---Assert error is thrown
---@param fn function
---@param pattern string|nil
---@param message string|nil
function M.assert.throws(fn, pattern, message)
  local ok, err = pcall(fn)
  if ok then
    error(message or "Expected function to throw an error")
  end
  if pattern and not string.match(tostring(err), pattern) then
    error(string.format(
      "%s\nExpected error matching: %s\nActual error: %s",
      message or "Error pattern mismatch",
      pattern,
      tostring(err)
    ))
  end
end

---Assert no error is thrown
---@param fn function
---@param message string|nil
function M.assert.no_error(fn, message)
  local ok, err = pcall(fn)
  if not ok then
    error(string.format(
      "%s\nUnexpected error: %s",
      message or "Expected no error",
      tostring(err)
    ))
  end
end

---Assert type
---@param value any
---@param expected_type string
---@param message string|nil
function M.assert.type(value, expected_type, message)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error(string.format(
      "%s\nExpected type: %s\nActual type: %s",
      message or "Type assertion failed",
      expected_type,
      actual_type
    ))
  end
end

---Assert table contains
---@param table table
---@param value any
---@param message string|nil
function M.assert.contains(table, value, message)
  if not vim.tbl_contains(table, value) then
    error(string.format(
      "%s\nTable does not contain: %s\nTable: %s",
      message or "Contains assertion failed",
      vim.inspect(value),
      vim.inspect(table)
    ))
  end
end

---Mock helper
---@param module_name string
---@param method_name string
---@param mock_fn function
---@return function restore
function M.mock(module_name, method_name, mock_fn)
  local module = require(module_name)
  local original = module[method_name]
  module[method_name] = mock_fn

  return function()
    module[method_name] = original
  end
end

---Spy helper
---@param module_name string
---@param method_name string
---@return table spy
function M.spy(module_name, method_name)
  local module = require(module_name)
  local original = module[method_name]
  local spy = {
    calls = {},
    call_count = 0,
  }

  module[method_name] = function(...)
    spy.call_count = spy.call_count + 1
    table.insert(spy.calls, {...})
    return original(...)
  end

  spy.restore = function()
    module[method_name] = original
  end

  return spy
end

---Run a single test
---@param suite_name string
---@param test_name string
---@param test_fn function
---@param suite TestSuite
---@return boolean success
---@return string|nil error
function M.run_test(suite_name, test_name, test_fn, suite)
  local success = true
  local error_msg = nil

  -- Run before_each if exists
  if suite.before_each then
    local ok, err = pcall(suite.before_each)
    if not ok then
      return false, string.format("before_each failed: %s", err)
    end
  end

  -- Run the test
  local ok, err = pcall(test_fn)
  if not ok then
    success = false
    error_msg = tostring(err)
  end

  -- Run after_each if exists
  if suite.after_each then
    local ok2, err2 = pcall(suite.after_each)
    if not ok2 then
      return false, string.format("after_each failed: %s", err2)
    end
  end

  return success, error_msg
end

---Run all tests in a suite
---@param suite_name string
---@param suite TestSuite
function M.run_suite(suite_name, suite)
  print(M.colors.bold .. M.colors.blue .. "\n● " .. suite_name .. M.colors.reset)

  -- Run before_all if exists
  if suite.before_all then
    local ok, err = pcall(suite.before_all)
    if not ok then
      print(M.colors.red .. "  ✗ before_all failed: " .. err .. M.colors.reset)
      return
    end
  end

  for test_name, test_fn in pairs(suite.tests) do
    M.results.total = M.results.total + 1
    local success, error_msg = M.run_test(suite_name, test_name, test_fn, suite)

    if success then
      M.results.passed = M.results.passed + 1
      print(M.colors.green .. "  ✓ " .. test_name .. M.colors.reset)
    else
      M.results.failed = M.results.failed + 1
      print(M.colors.red .. "  ✗ " .. test_name .. M.colors.reset)
      if error_msg then
        -- Clean up error message
        local clean_error = error_msg:gsub("^.-:%d+: ", "")
        print(M.colors.red .. "    → " .. clean_error .. M.colors.reset)
        table.insert(M.results.errors, {
          suite = suite_name,
          test = test_name,
          error = clean_error
        })
      end
    end
  end

  -- Run after_all if exists
  if suite.after_all then
    local ok, err = pcall(suite.after_all)
    if not ok then
      print(M.colors.red .. "  ✗ after_all failed: " .. err .. M.colors.reset)
    end
  end
end

---Run all test suites
function M.run_all()
  local start_time = vim.loop.hrtime()

  print(M.colors.bold .. M.colors.cyan .. "\n🧪 Running TodoAI Test Suite" .. M.colors.reset)
  print(M.colors.cyan .. "═══════════════════════════" .. M.colors.reset)

  -- Reset results
  M.results = {
    total = 0,
    passed = 0,
    failed = 0,
    errors = {},
    duration = 0
  }

  -- Run all suites
  for suite_name, suite in pairs(M.suites) do
    M.run_suite(suite_name, suite)
  end

  -- Calculate duration
  M.results.duration = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

  -- Print summary
  M.print_summary()

  -- Return exit code
  return M.results.failed == 0 and 0 or 1
end

---Print test summary
function M.print_summary()
  print(M.colors.cyan .. "\n═══════════════════════════" .. M.colors.reset)
  print(M.colors.bold .. "Test Summary" .. M.colors.reset)
  print(M.colors.cyan .. "═══════════════════════════" .. M.colors.reset)

  if M.results.failed == 0 then
    print(M.colors.green .. M.colors.bold ..
          string.format("✓ All %d tests passed!", M.results.total) ..
          M.colors.reset)
  else
    print(M.colors.red .. M.colors.bold ..
          string.format("✗ %d/%d tests failed", M.results.failed, M.results.total) ..
          M.colors.reset)
  end

  print(string.format("\nTotal:   %d", M.results.total))
  print(M.colors.green .. string.format("Passed:  %d", M.results.passed) .. M.colors.reset)
  if M.results.failed > 0 then
    print(M.colors.red .. string.format("Failed:  %d", M.results.failed) .. M.colors.reset)
  end
  print(string.format("Time:    %.2fms", M.results.duration))

  -- Print errors if any
  if #M.results.errors > 0 then
    print(M.colors.red .. "\n" .. M.colors.bold .. "Failed Tests:" .. M.colors.reset)
    for _, err in ipairs(M.results.errors) do
      print(M.colors.red .. string.format("  • %s > %s", err.suite, err.test) .. M.colors.reset)
      print(M.colors.yellow .. "    " .. err.error .. M.colors.reset)
    end
  end
end

---Clear all test suites
function M.reset()
  M.suites = {}
  M.results = {
    total = 0,
    passed = 0,
    failed = 0,
    errors = {},
    duration = 0
  }
end

return M