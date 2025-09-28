#!/usr/bin/env lua

-- Test runner script for TodoAI plugin
-- Run with: lua run_tests.lua

-- Add project to path
package.path = package.path .. ";./lua/?.lua;./tests/?.lua"

-- Mock Neovim API for testing outside of Neovim
if not vim then
  _G.vim = {
    fn = {},
    api = {},
    loop = {
      hrtime = function() return os.clock() * 1000000000 end,
      now = function() return os.time() * 1000 end,
    },
    log = {
      levels = {
        DEBUG = 0,
        INFO = 1,
        WARN = 2,
        ERROR = 3,
      }
    },
    bo = {},
    o = { background = 'dark' },
    env = {},
    split = function(str, sep)
      local t = {}
      for s in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(t, s)
      end
      return t
    end,
    inspect = function(v)
      if type(v) == "table" then
        local s = "{"
        for k, val in pairs(v) do
          s = s .. tostring(k) .. "=" .. tostring(val) .. ","
        end
        return s .. "}"
      end
      return tostring(v)
    end,
    deep_equal = function(a, b)
      if type(a) ~= type(b) then return false end
      if type(a) ~= "table" then return a == b end
      for k, v in pairs(a) do
        if not vim.deep_equal(v, b[k]) then return false end
      end
      for k, v in pairs(b) do
        if not vim.deep_equal(v, a[k]) then return false end
      end
      return true
    end,
    deepcopy = function(orig)
      local copy
      if type(orig) == 'table' then
        copy = {}
        for k, v in next, orig, nil do
          copy[vim.deepcopy(k)] = vim.deepcopy(v)
        end
        setmetatable(copy, vim.deepcopy(getmetatable(orig)))
      else
        copy = orig
      end
      return copy
    end,
    tbl_contains = function(t, value)
      for _, v in ipairs(t) do
        if v == value then return true end
      end
      return false
    end,
    tbl_extend = function(behavior, ...)
      local result = {}
      for i = 1, select('#', ...) do
        local t = select(i, ...)
        if t then
          for k, v in pairs(t) do
            result[k] = v
          end
        end
      end
      return result
    end,
    tbl_keys = function(t)
      local keys = {}
      for k in pairs(t) do
        table.insert(keys, k)
      end
      return keys
    end,
    list_slice = function(t, start, stop)
      local result = {}
      stop = stop or #t
      for i = start, stop do
        table.insert(result, t[i])
      end
      return result
    end,
    startswith = function(str, prefix)
      return str:sub(1, #prefix) == prefix
    end,
    wait = function(ms)
      -- Simple busy wait for testing
      local start = os.clock()
      while (os.clock() - start) * 1000 < ms do end
    end,
    defer_fn = function(fn, ms)
      -- In tests, execute immediately
      fn()
    end,
    notify = function(msg, level)
      print("NOTIFY: " .. msg)
    end,
    cmd = function(cmd) end,
    api = {
      nvim_create_namespace = function(name) return 1 end,
      nvim_buf_is_valid = function(bufnr) return bufnr == 1 end,
      nvim_buf_line_count = function(bufnr) return 100 end,
      nvim_buf_get_lines = function(bufnr, start, stop, strict)
        return {"line1", "line2", "line3"}
      end,
      nvim_buf_set_lines = function(bufnr, start, stop, strict, lines) end,
      nvim_buf_add_highlight = function(bufnr, ns, hl, line, col_start, col_end) end,
      nvim_buf_clear_namespace = function(bufnr, ns, start_line, end_line) end,
      nvim_buf_set_extmark = function(bufnr, ns, line, col, opts) return 1 end,
      nvim_create_buf = function(listed, scratch) return 1 end,
      nvim_win_set_buf = function(win, buf) end,
      nvim_win_is_valid = function(win) return win == 1 end,
      nvim_win_get_cursor = function(win) return {1, 0} end,
      nvim_win_set_cursor = function(win, pos) end,
      nvim_get_current_buf = function() return 1 end,
      nvim_get_current_win = function() return 1 end,
      nvim_buf_get_name = function(bufnr) return "test.lua" end,
      nvim_buf_set_name = function(bufnr, name) end,
      nvim_buf_set_option = function(bufnr, option, value) end,
      nvim_win_set_option = function(win, option, value) end,
      nvim_set_hl = function(ns, name, opts) end,
      nvim_create_autocmd = function(event, opts) return 1 end,
      nvim_create_augroup = function(name, opts) return 1 end,
      nvim_list_uis = function()
        return {{width = 100, height = 50}}
      end,
      nvim_open_win = function(buf, enter, opts) return 1 end,
      nvim_win_close = function(win, force) end,
      nvim_buf_delete = function(buf, opts) end,
    },
    fn = {
      system = function(cmd) return "" end,
      getcwd = function() return "/test/project" end,
      isdirectory = function(dir) return 0 end,
      filereadable = function(file) return 0 end,
      readfile = function(file)
        -- Return empty table for file contents
        return {}
      end,
      glob = function(pattern, nosuf, list) return {} end,
      fnamemodify = function(file, mods) return file end,
      mkdir = function(dir, flags) return 1 end,
      json_encode = function(t) return "{}" end,
      json_decode = function(s)
        -- Simple JSON parser for testing
        if not s or s == '' then return {} end

        -- First, strip markdown code blocks if present
        local stripped = s
        if s:match('```json') then
          -- Remove markdown code block markers
          stripped = s:gsub('^```json%s*\n', ''):gsub('\n```%s*$', '')
        end

        -- Handle specific test cases
        if stripped == '{"name":"test"}' then
          return {name = "test"}
        elseif stripped == '{"key": "value", "number": 42}' then
          return {key = "value", number = 42}
        elseif stripped == '{"key": "value"}' then
          return {key = "value"}
        elseif stripped == '{"key": "value",}' then
          -- Fix trailing comma - return parsed result
          return {key = "value"}
        elseif stripped == "{'key': 'value'}" then
          -- Fix single quotes - return parsed result
          return {key = "value"}
        end
        -- Default
        return {}
      end,
      stdpath = function(what) return "/tmp/nvim" end,
      jobstart = function(cmd, opts) return 1 end,
      jobstop = function(job_id) return 1 end,
      timer_start = function(delay, callback, opts) return 1 end,
      timer_stop = function(timer) end,
      getfsize = function(file) return 0 end,
      getpid = function() return 12345 end,
    }
  }
end

-- Load test runner
local runner = require('tests.test_runner')

-- Import test suites
local function load_tests()
  -- Unit tests
  require('tests.unit.context_compact_spec')
  require('tests.unit.llm_validator_spec')
  require('tests.unit.secure_exec_spec')

  -- Add more test files as they're created
end

-- Main execution
local function main()
  print("\n" .. string.rep("=", 50))
  print("TodoAI Test Suite")
  print(string.rep("=", 50))

  -- Load all tests
  local ok, err = pcall(load_tests)
  if not ok then
    print("Error loading tests: " .. tostring(err))
    os.exit(1)
  end

  -- Run tests
  local exit_code = runner.run_all()

  print("\n" .. string.rep("=", 50))
  if exit_code == 0 then
    print("✅ All tests passed!")
  else
    print("❌ Some tests failed. Please review the output above.")
  end
  print(string.rep("=", 50) .. "\n")

  os.exit(exit_code)
end

main()