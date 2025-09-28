-- Tests for utils module

local runner = require('test.test_runner')

-- Mock vim API
runner.mock_vim()

-- Load module
local utils = require('lua.todo-ai.utils')

runner.suite('Utils', {
  ['test_validate_buffer_valid'] = function()
    local ok, err = utils.validate_buffer(1)
    assert_true(ok, "Should validate valid buffer")
    assert_nil(err, "Should not return error for valid buffer")
  end,

  ['test_validate_buffer_invalid'] = function()
    local ok, err = utils.validate_buffer(nil)
    assert_false(ok, "Should not validate nil buffer")
    assert_eq(err, utils.errors.INVALID_BUFFER)

    ok, err = utils.validate_buffer(0)
    assert_false(ok, "Should not validate buffer 0")
  end,

  ['test_validate_line_range_valid'] = function()
    local ok, err = utils.validate_line_range(1, 1, 10)
    assert_true(ok, "Should validate valid line range")
    assert_nil(err)
  end,

  ['test_validate_line_range_invalid'] = function()
    -- Invalid buffer
    local ok, err = utils.validate_line_range(nil, 1, 10)
    assert_false(ok)
    assert_eq(err, utils.errors.INVALID_BUFFER)

    -- Invalid start line
    ok, err = utils.validate_line_range(1, 0, 10)
    assert_false(ok)
    assert_true(err:match("start_line"))

    ok, err = utils.validate_line_range(1, 101, 110)
    assert_false(ok)
    assert_true(err:match("start_line"))

    -- Invalid end line
    ok, err = utils.validate_line_range(1, 10, 5)
    assert_false(ok)
    assert_true(err:match("end_line"))

    ok, err = utils.validate_line_range(1, 10, 101)
    assert_false(ok)
    assert_true(err:match("end_line"))
  end,

  ['test_safe_json_decode_valid'] = function()
    local result, err = utils.safe_json_decode('{}')
    assert_not_nil(result)
    assert_type(result, 'table')
    assert_nil(err)
  end,

  ['test_safe_json_decode_invalid'] = function()
    -- Nil input
    local result, err = utils.safe_json_decode(nil)
    assert_nil(result)
    assert_not_nil(err)

    -- Empty string
    result, err = utils.safe_json_decode('')
    assert_nil(result)
    assert_not_nil(err)

    -- Invalid JSON
    result, err = utils.safe_json_decode('not json')
    assert_nil(result)
    assert_true(err:match(utils.errors.PARSE_ERROR))

    -- Non-string input
    result, err = utils.safe_json_decode(123)
    assert_nil(result)
    assert_not_nil(err)
  end,

  ['test_safe_json_encode_valid'] = function()
    local result, err = utils.safe_json_encode({test = true})
    assert_not_nil(result)
    assert_type(result, 'string')
    assert_nil(err)
  end,

  ['test_safe_json_encode_invalid'] = function()
    local result, err = utils.safe_json_encode(nil)
    assert_nil(result)
    assert_not_nil(err)
  end,

  ['test_sanitize_path_valid'] = function()
    local result, err = utils.sanitize_path('test/file.lua')
    assert_eq(result, 'test/file.lua')
    assert_nil(err)

    -- Should normalize backslashes
    result, err = utils.sanitize_path('test\\file.lua')
    assert_eq(result, 'test/file.lua')
    assert_nil(err)
  end,

  ['test_sanitize_path_invalid'] = function()
    -- Nil path
    local result, err = utils.sanitize_path(nil)
    assert_nil(result)
    assert_not_nil(err)

    -- Path with parent directory
    result, err = utils.sanitize_path('../secret/file')
    assert_eq(result, 'secret/file')
    assert_nil(err)

    -- Absolute path
    result, err = utils.sanitize_path('/etc/passwd')
    assert_eq(result, 'etc/passwd')
    assert_nil(err)

    -- Invalid characters
    result, err = utils.sanitize_path('file<>:"|?*.txt')
    assert_nil(result)
    assert_true(err:match("invalid characters"))
  end,

  ['test_deep_copy'] = function()
    local original = {
      a = 1,
      b = {c = 2, d = {e = 3}},
      f = "test"
    }

    local copy = utils.deep_copy(original)

    -- Check values are copied
    assert_eq(copy.a, original.a)
    assert_eq(copy.b.c, original.b.c)
    assert_eq(copy.b.d.e, original.b.d.e)
    assert_eq(copy.f, original.f)

    -- Check it's a deep copy (modifying copy doesn't affect original)
    copy.a = 999
    copy.b.c = 999
    copy.b.d.e = 999

    assert_eq(original.a, 1)
    assert_eq(original.b.c, 2)
    assert_eq(original.b.d.e, 3)
  end,

  ['test_merge_tables'] = function()
    local t1 = {a = 1, b = {c = 2}}
    local t2 = {b = {d = 3}, e = 4}

    local result = utils.merge_tables(t1, t2)

    assert_eq(result.a, 1)
    assert_eq(result.b.c, 2)
    assert_eq(result.b.d, 3)
    assert_eq(result.e, 4)

    -- Original tables should not be modified
    assert_nil(t1.e)
    assert_nil(t1.b.d)
  end,

  ['test_validate_api_response_valid'] = function()
    local ok, err = utils.validate_api_response({data = "test"})
    assert_true(ok)
    assert_nil(err)
  end,

  ['test_validate_api_response_invalid'] = function()
    -- Nil response
    local ok, err = utils.validate_api_response(nil)
    assert_false(ok)
    assert_true(err:match("empty response"))

    -- Error response
    ok, err = utils.validate_api_response({error = {message = "API failed"}})
    assert_false(ok)
    assert_true(err:match("API failed"))
  end,

  ['test_format_error'] = function()
    local msg = utils.format_error("test error")
    assert_eq(msg, "[todo-ai] test error")

    msg = utils.format_error("test error", "context")
    assert_eq(msg, "[todo-ai] context: test error")
  end,

  ['test_validate_string_length'] = function()
    -- Valid strings
    local ok, err = utils.validate_string_length("test", 10)
    assert_true(ok)
    assert_nil(err)

    ok, err = utils.validate_string_length(nil, 10)
    assert_true(ok)

    -- Invalid strings
    ok, err = utils.validate_string_length("toolong", 3)
    assert_false(ok)
    assert_true(err:match("too long"))

    ok, err = utils.validate_string_length(123, 10)
    assert_false(ok)
    assert_true(err:match("expected string"))
  end,

  ['test_safe_substring'] = function()
    local result = utils.safe_substring("hello world", 1, 5)
    assert_eq(result, "hello")

    result = utils.safe_substring("hello", 3, 10)
    assert_eq(result, "llo")

    result = utils.safe_substring("hello", 10, 20)
    assert_eq(result, "")

    result = utils.safe_substring(nil)
    assert_eq(result, "")

    result = utils.safe_substring(123)
    assert_eq(result, "")
  end,

  ['test_safe_callback'] = function()
    local called = false
    local error_caught = false

    -- Successful callback
    local safe_fn = utils.safe_callback(function()
      called = true
      return "success"
    end)

    local result = safe_fn()
    assert_true(called)
    assert_eq(result, "success")

    -- Failing callback with error handler
    safe_fn = utils.safe_callback(
      function()
        error("test error")
      end,
      function(err)
        error_caught = true
      end
    )

    safe_fn()
    assert_true(error_caught)
  end,

  ['test_constants'] = function()
    assert_type(utils.constants.MAX_LINE_LENGTH, 'number')
    assert_type(utils.constants.CLAUDE_TIMEOUT, 'number')
    assert_true(utils.constants.CLAUDE_TIMEOUT > utils.constants.DEFAULT_TIMEOUT)
  end,
})