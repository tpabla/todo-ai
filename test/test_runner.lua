#!/usr/bin/env lua
-- Test runner for todo-ai plugin

local M = {}

-- ANSI color codes
local colors = {
  reset = '\27[0m',
  red = '\27[31m',
  green = '\27[32m',
  yellow = '\27[33m',
  blue = '\27[34m',
  cyan = '\27[36m',
}

-- Test state
M.tests = {}
M.current_suite = nil
M.stats = {
  passed = 0,
  failed = 0,
  skipped = 0,
  errors = {},
}

-- Test assertion functions
local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format(
      "%s\nExpected: %s\nActual: %s",
      message or "Assertion failed",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

local function assert_true(value, message)
  if not value then
    error(message or "Expected true, got " .. tostring(value))
  end
end

local function assert_false(value, message)
  if value then
    error(message or "Expected false, got " .. tostring(value))
  end
end

local function assert_nil(value, message)
  if value ~= nil then
    error(message or "Expected nil, got " .. vim.inspect(value))
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(message or "Expected non-nil value")
  end
end

local function assert_type(value, expected_type, message)
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

local function assert_error(fn, message)
  local ok, err = pcall(fn)
  if ok then
    error(message or "Expected function to throw error")
  end
  return err
end

local function assert_no_error(fn, message)
  local ok, result = pcall(fn)
  if not ok then
    error(string.format(
      "%s\nUnexpected error: %s",
      message or "Expected function to not throw error",
      result
    ))
  end
  return result
end

-- Create test suite
function M.suite(name, tests)
  M.tests[name] = tests
end

-- Run a single test
local function run_test(suite_name, test_name, test_fn)
  local status = 'passed'
  local error_msg = nil

  -- Setup test environment
  local env = {
    assert_eq = assert_eq,
    assert_true = assert_true,
    assert_false = assert_false,
    assert_nil = assert_nil,
    assert_not_nil = assert_not_nil,
    assert_type = assert_type,
    assert_error = assert_error,
    assert_no_error = assert_no_error,
  }

  -- Run test with environment
  local ok, err = pcall(function()
    setfenv(test_fn, setmetatable(env, { __index = _G }))
    test_fn()
  end)

  if not ok then
    status = 'failed'
    error_msg = err
    M.stats.failed = M.stats.failed + 1
    table.insert(M.stats.errors, {
      suite = suite_name,
      test = test_name,
      error = err
    })
  else
    M.stats.passed = M.stats.passed + 1
  end

  return status, error_msg
end

-- Run all tests
function M.run()
  print(colors.cyan .. "Running todo-ai tests..." .. colors.reset)
  print("")

  for suite_name, suite in pairs(M.tests) do
    print(colors.blue .. "Suite: " .. suite_name .. colors.reset)

    -- Run before_all if exists
    if suite.before_all then
      suite.before_all()
    end

    for test_name, test_fn in pairs(suite) do
      if type(test_fn) == 'function' and
         test_name ~= 'before_all' and
         test_name ~= 'after_all' and
         test_name ~= 'before_each' and
         test_name ~= 'after_each' then

        -- Run before_each if exists
        if suite.before_each then
          suite.before_each()
        end

        -- Run test
        local status, error_msg = run_test(suite_name, test_name, test_fn)

        -- Print result
        if status == 'passed' then
          print("  " .. colors.green .. "✓" .. colors.reset .. " " .. test_name)
        else
          print("  " .. colors.red .. "✗" .. colors.reset .. " " .. test_name)
          if error_msg then
            print("    " .. colors.red .. error_msg .. colors.reset)
          end
        end

        -- Run after_each if exists
        if suite.after_each then
          suite.after_each()
        end
      end
    end

    -- Run after_all if exists
    if suite.after_all then
      suite.after_all()
    end

    print("")
  end

  -- Print summary
  print(colors.cyan .. "Test Summary:" .. colors.reset)
  print(string.format(
    "  %s%d passed%s, %s%d failed%s, %s%d skipped%s",
    colors.green, M.stats.passed, colors.reset,
    colors.red, M.stats.failed, colors.reset,
    colors.yellow, M.stats.skipped, colors.reset
  ))

  if M.stats.failed > 0 then
    print("")
    print(colors.red .. "Failed tests:" .. colors.reset)
    for _, error in ipairs(M.stats.errors) do
      print(string.format("  %s.%s", error.suite, error.test))
    end
    os.exit(1)
  end

  os.exit(0)
end

-- Mock vim API for testing
function M.mock_vim()
  _G.vim = {
    api = {
      nvim_buf_is_valid = function(bufnr)
        return type(bufnr) == 'number' and bufnr > 0
      end,
      nvim_buf_get_lines = function(bufnr, start_line, end_line, strict)
        return {}
      end,
      nvim_buf_set_lines = function(bufnr, start_line, end_line, strict, lines)
        return true
      end,
      nvim_buf_line_count = function(bufnr)
        return 100
      end,
      nvim_create_namespace = function(name)
        return 1
      end,
      nvim_buf_add_highlight = function()
        return 1
      end,
      nvim_buf_clear_namespace = function()
        return true
      end,
      nvim_buf_set_extmark = function()
        return 1
      end,
      nvim_get_current_buf = function()
        return 1
      end,
      nvim_buf_get_name = function(bufnr)
        return "test.lua"
      end,
      nvim_list_bufs = function()
        return {1, 2, 3}
      end,
      nvim_win_is_valid = function(win)
        return type(win) == 'number' and win > 0
      end,
      nvim_create_buf = function()
        return 1
      end,
      nvim_open_win = function()
        return 1
      end,
      nvim_set_current_win = function()
        return true
      end,
      nvim_win_set_buf = function()
        return true
      end,
    },
    fn = {
      json_encode = function(obj)
        -- Simple JSON encoder for testing
        if type(obj) == 'table' then
          return '{}'
        end
        return tostring(obj)
      end,
      json_decode = function(str)
        -- Simple JSON decoder for testing
        if str == '{}' then
          return {}
        end
        error("Invalid JSON")
      end,
      getcwd = function()
        return "/test"
      end,
      expand = function(str)
        return str
      end,
      timer_start = function(delay, callback)
        return 1
      end,
      timer_stop = function(timer)
        return true
      end,
      system = function(cmd)
        return ""
      end,
      fnamemodify = function(path, mod)
        return "filename"
      end,
      filereadable = function(path)
        return 0
      end,
    },
    bo = {},
    log = {
      levels = {
        DEBUG = 0,
        INFO = 1,
        WARN = 2,
        ERROR = 3,
      }
    },
    notify = function(msg, level)
      print(msg)
    end,
    loop = {
      now = function()
        return os.time() * 1000
      end,
    },
    env = {},
    cmd = function(cmd)
      return true
    end,
    deepcopy = function(obj)
      -- Simple deepcopy for testing
      if type(obj) ~= 'table' then
        return obj
      end
      local copy = {}
      for k, v in pairs(obj) do
        copy[k] = vim.deepcopy(v)
      end
      return copy
    end,
    inspect = function(obj)
      return tostring(obj)
    end,
    split = function(str, sep)
      local result = {}
      for part in str:gmatch("[^" .. sep .. "]+") do
        table.insert(result, part)
      end
      return result
    end,
    defer_fn = function(fn, delay)
      fn()
    end,
  }
end

return M