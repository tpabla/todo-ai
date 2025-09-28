#!/usr/bin/env lua

-- Simple test for the scanner module
package.path = "./lua/?.lua;" .. package.path

-- Mock vim globals for testing
_G.vim = {
  bo = { commentstring = "-- %s" },
  pesc = function(str)
    -- Simple escape for pattern matching
    return str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  end,
  split = function(str, sep)
    local result = {}
    for match in str:gmatch("[^" .. sep .. "]+") do
      table.insert(result, match)
    end
    return result
  end
}

local scanner = require('todo-ai.scanner')

-- Test data
local test_lines = {
  "-- Test file for multi-line TODO handling",
  "",
  "function example()",
  "  -- TODO: @ai implement a function that",
  "  -- validates user input and returns true",
  "  -- if the input is valid, false otherwise",
  "",
  "  -- TODO: @ai add error handling here",
  "",
  "  -- Single line TODO",
  "  -- TODO: @ai add logging",
  "",
  "  return true",
  "end"
}

-- Test multi-line extraction
print("Testing multi-line TODO extraction:")
print("=" .. string.rep("=", 40))

-- Test line 4 (first multi-line TODO)
local todo1 = scanner.parse_line(test_lines[4], 4, test_lines)
if todo1 then
  print("TODO at line 4:")
  print("  Instruction: " .. todo1.instruction)
  print("")
end

-- Test line 8 (single-line TODO)
local todo2 = scanner.parse_line(test_lines[8], 8, test_lines)
if todo2 then
  print("TODO at line 8:")
  print("  Instruction: " .. todo2.instruction)
  print("")
end

-- Test line 11 (another single-line TODO)
local todo3 = scanner.parse_line(test_lines[11], 11, test_lines)
if todo3 then
  print("TODO at line 11:")
  print("  Instruction: " .. todo3.instruction)
  print("")
end

print("Test complete!")