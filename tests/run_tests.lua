#!/usr/bin/env lua

-- Test runner with automatic cleanup for hanging nvim processes

local function cleanup_nvim()
  os.execute("pkill -f 'nvim --headless' 2>/dev/null || true")
end

local function run_tests()
  -- Set trap for cleanup on exit
  os.execute("trap 'pkill -f \"nvim --headless\"' EXIT INT TERM")

  -- Build the nvim command with timeout
  local cmd = table.concat({
    "timeout 30",
    "nvim --headless",
    "-u tests/minimal_init.lua",
    "-c 'lua require(\"plenary.test_harness\").test_directory(\"tests/plenary/\", {minimal_init=\"tests/minimal_init.lua\", sequential=true})'",
    "-c 'qa!'"
  }, " ")

  print("Running tests...")
  local result = os.execute(cmd)

  -- Always cleanup
  cleanup_nvim()

  return result == 0
end

-- Check for hanging processes before starting
local check_cmd = "ps aux | grep -v grep | grep 'nvim --headless' || true"
local check = io.popen(check_cmd)
local existing = check:read("*a")
check:close()

if existing and existing ~= "" then
  print("Warning: Found existing nvim headless processes, cleaning up...")
  cleanup_nvim()
end

-- Run tests
local success = run_tests()

if success then
  print("\n✅ All tests passed!")
  os.exit(0)
else
  print("\n❌ Tests failed!")
  cleanup_nvim()
  os.exit(1)
end
