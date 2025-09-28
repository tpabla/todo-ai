#!/usr/bin/env lua
-- Main test runner script

-- Add project to path
package.path = package.path .. ";?.lua;lua/?.lua;test/?.lua"

-- Mock vim.tbl_contains for testing
if not vim then
  _G.vim = {}
end
vim.tbl_contains = function(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

-- Load test runner
local runner = require('test_runner')

-- Load all test suites
require('utils_test')
require('parser_test')
require('schema_test')

-- Run all tests
runner.run()