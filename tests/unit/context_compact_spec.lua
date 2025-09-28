local runner = require('tests.test_runner')
local assert = runner.assert

-- Test suite for context_compact module
local suite = runner.describe("context_compact")

-- Mock vim functions
local original_vim = {}
local mock_data = {}

suite.before_all = function()
  -- Save original vim functions
  original_vim.fn = vim.fn
  original_vim.loop = vim.loop
  original_vim.api = vim.api

  -- Mock vim.fn functions
  vim.fn = setmetatable({}, {
    __index = function(_, key)
      if key == 'system' then
        return function(cmd)
          -- Return mock data based on command
          if cmd:match('find.*%.lua.*wc') then
            return "  10  \n"  -- Simulate wc output with spaces
          elseif cmd:match('find.*%.py.*wc') then
            return "\t5\t\n"  -- Simulate wc output with tabs
          elseif cmd:match('find.*%.js.*wc') then
            return "invalid\n"  -- Simulate invalid output
          elseif cmd:match('find.*%.ts.*wc') then
            return "0\n"  -- Zero files
          elseif cmd:match('find.*%.go.*wc') then
            return "abc123def\n"  -- Mixed alphanumeric
          elseif cmd:match('find.*%.rs.*wc') then
            return ""  -- Empty output
          elseif cmd:match('git status') then
            return "On branch main\nnothing to commit"
          elseif cmd:match('git remote') then
            return "origin\thttps://github.com/user/repo.git (fetch)"
          else
            return ""
          end
        end
      elseif key == 'getcwd' then
        return function() return '/test/project' end
      elseif key == 'isdirectory' then
        return function(dir) return dir == 'src' and 1 or 0 end
      elseif key == 'filereadable' then
        return function(file)
          if file == 'package.json' then return 1
          elseif file == '.todoai/context.md' then return 0
          else return 0
          end
        end
      elseif key == 'glob' then
        return function(pattern, _, _)
          if pattern:match('%.config') then
            return {'webpack.config.js', 'jest.config.json'}
          else
            return {}
          end
        end
      elseif key == 'fnamemodify' then
        return function(file, mod)
          if mod == ':t' then
            return file:match('[^/]+$') or file
          end
          return file
        end
      elseif key == 'mkdir' then
        return function() return 1 end
      elseif key == 'json_decode' then
        return function(str)
          -- Simple JSON mock
          if str == '{"name":"test"}' then
            return {name = "test"}
          end
          return {}
        end
      else
        return function() return "" end
      end
    end
  })

  -- Mock vim.loop
  vim.loop = {
    os_uname = function()
      return {
        sysname = "Darwin",
        release = "20.0.0",
        version = "Darwin Kernel Version 20.0.0"
      }
    end
  }
end

suite.after_all = function()
  -- Restore original vim functions
  vim.fn = original_vim.fn
  vim.loop = original_vim.loop
  vim.api = original_vim.api
end

-- Test: generate_compact handles various system command outputs
runner.it(suite, "should handle various wc output formats", function()
  local context = require('todo-ai.context_compact')

  -- This should not throw an error despite various output formats
  assert.no_error(function()
    local result = context.generate_compact()
    assert.not_nil(result, "Context should be generated")
    assert.type(result, "string", "Context should be a string")
  end, "Should handle various wc output formats without error")
end)

-- Test: tonumber edge cases
runner.it(suite, "should handle tonumber edge cases", function()
  local context = require('todo-ai.context_compact')

  -- Test with various problematic inputs
  local test_cases = {
    "  10  \n",      -- Spaces
    "\t5\t\n",       -- Tabs
    "invalid\n",     -- Non-numeric
    "",              -- Empty
    "abc123def\n",   -- Mixed
    "0\n",           -- Zero
    nil,             -- Nil
  }

  for _, test_input in ipairs(test_cases) do
    assert.no_error(function()
      -- Simulate the actual code path
      local count_str = test_input and test_input:match('%d+')
      if count_str then
        local count = tonumber(count_str)
        -- Should not throw
      end
    end, "Should handle input: " .. vim.inspect(test_input))
  end
end)

-- Test: generate_full creates valid context
runner.it(suite, "should generate valid full context", function()
  local context = require('todo-ai.context_compact')

  assert.no_error(function()
    local result = context.generate_full()
    assert.not_nil(result, "Full context should be generated")
    assert.type(result, "string", "Full context should be a string")
    assert.truthy(result:match("Project Context"), "Should contain header")
  end, "Should generate full context without errors")
end)

-- Test: encode_for_llm compression
runner.it(suite, "should compress context for LLM", function()
  local context = require('todo-ai.context_compact')

  local test_input = [[
    This is a test
    <!-- Comment to remove -->


    Multiple    spaces    here
  ]]

  local encoded = context.encode_for_llm(test_input)
  assert.not_nil(encoded, "Should return encoded string")
  assert.falsy(encoded:match('<!%-%-'), "Should remove comments")
  assert.falsy(encoded:match('\n\n\n'), "Should remove excessive newlines")
end)

-- Test: get_for_prompt returns valid data
runner.it(suite, "should return valid prompt context", function()
  local context = require('todo-ai.context_compact')

  assert.no_error(function()
    local result = context.get_for_prompt()
    assert.not_nil(result, "Prompt context should exist")
    assert.type(result, "string", "Prompt context should be string")
  end, "Should get prompt context without errors")
end)

-- Test: save function handles directory creation
runner.it(suite, "should handle save operations", function()
  local context = require('todo-ai.context_compact')

  assert.no_error(function()
    -- Should handle missing directory gracefully
    local result = context.save()
    -- Function should complete without throwing
  end, "Should handle save without errors")
end)

-- Test: parse_human_notes handles various formats
runner.it(suite, "should parse human notes correctly", function()
  local context = require('todo-ai.context_compact')

  local test_content = [[
## HUMAN NOTES
This is a note
Another line

## PROJECT CONTEXT
Other content
]]

  local notes = context.parse_human_notes(test_content)
  assert.not_nil(notes, "Should extract notes")
  assert.truthy(notes:match("This is a note"), "Should contain note content")
  assert.falsy(notes:match("PROJECT CONTEXT"), "Should not include other sections")
end)

-- Test: error recovery for file operations
runner.it(suite, "should handle file operation errors gracefully", function()
  -- Mock file read failure
  local old_io = io.open
  io.open = function() return nil, "Permission denied" end

  local context = require('todo-ai.context_compact')

  assert.no_error(function()
    context.load()  -- Should not throw even if file doesn't exist
  end, "Should handle missing file gracefully")

  io.open = old_io
end)

-- Test: validate context size limits
runner.it(suite, "should enforce size limits", function()
  local context = require('todo-ai.context_compact')

  -- Create large input
  local large_input = string.rep("x", 10000)

  local encoded = context.encode_for_llm(large_input)
  assert.truthy(#encoded <= 2100, "Should limit encoded size")  -- 2000 + "..."
end)

return suite