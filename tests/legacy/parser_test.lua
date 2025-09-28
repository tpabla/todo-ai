-- Tests for parser module

local runner = require('test.test_runner')

-- Mock vim API
runner.mock_vim()

-- Mock logger
_G.package.loaded['todo-ai.logger'] = {
  debug = function() end,
  info = function() end,
  warn = function() end,
  error = function() end,
}

-- Load module
local parser = require('lua.todo-ai.parser')

runner.suite('Parser', {
  ['test_parse_json_response_with_changes'] = function()
    local json = [[{
      "changes": [
        {
          "start_line": 1,
          "end_line": 5,
          "code": "function test() end",
          "description": "Test function"
        }
      ],
      "explanation": "Added test function"
    }]]

    local result = parser.parse(json)
    assert_not_nil(result.changes)
    assert_eq(#result.changes, 1)
    assert_eq(result.changes[1].start_line, 1)
    assert_eq(result.changes[1].end_line, 5)
    assert_eq(result.changes[1].code, "function test() end")
    assert_eq(result.explanation, "Added test function")
  end,

  ['test_parse_json_response_with_code_snippet'] = function()
    local json = [[{
      "code_snippet": "print('hello')",
      "explanation": "Example code"
    }]]

    local result = parser.parse(json)
    assert_eq(result.code_snippet, "print('hello')")
    assert_eq(result.explanation, "Example code")
    assert_nil(result.changes)
  end,

  ['test_parse_json_response_with_new_file'] = function()
    local json = [[{
      "new_file": "test.lua",
      "changes": [
        {
          "start_line": 1,
          "end_line": 1,
          "code": "return {}"
        }
      ],
      "explanation": "Created new file"
    }]]

    local result = parser.parse(json)
    assert_eq(result.new_file, "test.lua")
    assert_not_nil(result.changes)
    assert_eq(result.explanation, "Created new file")
  end,

  ['test_parse_invalid_json'] = function()
    local result = parser.parse("not valid json")
    assert_not_nil(result)
    -- Should attempt to extract code from plain text
  end,

  ['test_parse_markdown_code_blocks'] = function()
    local markdown = [[
Here's the code:
```lua
function hello()
  print("world")
end
```

And more text
```python
def test():
    pass
```
    ]]

    local result = parser.parse(markdown)
    assert_not_nil(result)
    -- Should extract code blocks
  end,

  ['test_detect_format_json'] = function()
    local format = parser.detect_format('{"key": "value"}')
    assert_eq(format, 'json_response')
  end,

  ['test_detect_format_xml'] = function()
    local format = parser.detect_format('<code>test</code>')
    assert_eq(format, 'xml_structured')
  end,

  ['test_detect_format_markdown'] = function()
    local format = parser.detect_format('```\ncode\n```')
    assert_eq(format, 'markdown_formatted')
  end,

  ['test_extract_thinking_tags'] = function()
    local text = '<thinking>Planning approach</thinking>Other content'
    local thinking = parser.extract_thinking_tags(text)
    assert_not_nil(thinking.thinking)
    assert_eq(thinking.thinking, 'Planning approach')
  end,

  ['test_remove_thinking_tags'] = function()
    local text = '<thinking>Private</thinking>Public content'
    local cleaned = parser.remove_thinking_tags(text)
    assert_eq(cleaned, 'Public content')
  end,

  ['test_clean_code_block'] = function()
    -- Should remove markdown code fence
    local code = parser.clean_code_block('```lua\ncode\n```')
    assert_eq(code, 'code')

    -- Should handle language specifier
    code = parser.clean_code_block('```python\ncode\n```')
    assert_eq(code, 'code')

    -- Should return plain code unchanged
    code = parser.clean_code_block('plain code')
    assert_eq(code, 'plain code')
  end,

  ['test_looks_like_code'] = function()
    -- Function definition
    assert_true(parser.looks_like_code('function test() end'))
    assert_true(parser.looks_like_code('def test():'))
    assert_true(parser.looks_like_code('public void test() {'))

    -- Variable declarations
    assert_true(parser.looks_like_code('const x = 1'))
    assert_true(parser.looks_like_code('let y = 2'))
    assert_true(parser.looks_like_code('var z = 3'))

    -- Control structures
    assert_true(parser.looks_like_code('if (true) {'))
    assert_true(parser.looks_like_code('for i in range'))
    assert_true(parser.looks_like_code('while (condition)'))

    -- Not code
    assert_false(parser.looks_like_code('This is just regular text'))
    assert_false(parser.looks_like_code(''))
    assert_false(parser.looks_like_code(nil))
  end,

  ['test_parse_empty_response'] = function()
    local result = parser.parse('')
    assert_not_nil(result)
    assert_type(result, 'table')
  end,

  ['test_parse_nil_response'] = function()
    local result = parser.parse(nil)
    assert_not_nil(result)
    assert_type(result, 'table')
  end,

  ['test_format_thinking'] = function()
    local thinking = {
      thinking = "Main thought",
      approach = "Strategy"
    }

    local formatted = parser.format_thinking(thinking)
    assert_not_nil(formatted)
    assert_true(formatted:match("Main thought"))
    assert_true(formatted:match("Strategy"))
  end,

  ['test_parse_with_hint_claude'] = function()
    local json = '{"changes": [], "explanation": "test"}'
    local result = parser.parse(json, 'claude')
    assert_not_nil(result)
    assert_eq(result.format_detected, 'json_response')
  end,

  ['test_parse_xml_structured'] = function()
    local xml = [[
<response>
  <code>function test() end</code>
  <explanation>Test function</explanation>
</response>
    ]]

    local result = parser.parse(xml)
    assert_not_nil(result)
    -- XML parsing should extract content
  end,

  ['test_parse_multiple_changes'] = function()
    local json = [[{
      "changes": [
        {
          "start_line": 1,
          "end_line": 2,
          "code": "-- comment",
          "description": "Add comment"
        },
        {
          "start_line": 10,
          "end_line": 15,
          "code": "function new() end",
          "description": "Add function"
        }
      ],
      "explanation": "Multiple changes"
    }]]

    local result = parser.parse(json)
    assert_not_nil(result.changes)
    assert_eq(#result.changes, 2)
    assert_eq(result.changes[1].start_line, 1)
    assert_eq(result.changes[2].start_line, 10)
  end,

  ['test_parse_replace_buffer'] = function()
    local json = [[{
      "replace_buffer": true,
      "changes": [
        {
          "start_line": 1,
          "end_line": 999999,
          "code": "-- New content"
        }
      ],
      "explanation": "Replace entire buffer"
    }]]

    local result = parser.parse(json)
    assert_true(result.replace_buffer)
    assert_not_nil(result.changes)
  end,
})