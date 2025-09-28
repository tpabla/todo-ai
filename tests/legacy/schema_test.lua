-- Tests for schema module

local runner = require('test.test_runner')

-- Mock vim API
runner.mock_vim()

-- Load module
local schema = require('lua.todo-ai.schema')

runner.suite('Schema', {
  ['test_schema_structure'] = function()
    assert_not_nil(schema.response_schema)
    assert_eq(schema.response_schema.type, "object")
    assert_not_nil(schema.response_schema.properties)
  end,

  ['test_schema_properties'] = function()
    local props = schema.response_schema.properties

    -- Check changes array
    assert_not_nil(props.changes)
    assert_eq(props.changes.type, "array")
    assert_not_nil(props.changes.items)
    assert_eq(props.changes.items.type, "object")

    local change_props = props.changes.items.properties
    assert_not_nil(change_props.start_line)
    assert_eq(change_props.start_line.type, "integer")
    assert_not_nil(change_props.end_line)
    assert_eq(change_props.end_line.type, "integer")
    assert_not_nil(change_props.code)
    assert_eq(change_props.code.type, "string")

    -- Check code_snippet
    assert_not_nil(props.code_snippet)
    assert_eq(props.code_snippet.type, "string")

    -- Check explanation
    assert_not_nil(props.explanation)
    assert_eq(props.explanation.type, "string")

    -- Check new_file
    assert_not_nil(props.new_file)
    assert_eq(props.new_file.type, "string")

    -- Check replace_buffer
    assert_not_nil(props.replace_buffer)
    assert_eq(props.replace_buffer.type, "boolean")
  end,

  ['test_get_schema_description'] = function()
    local description = schema.get_schema_description()
    assert_type(description, "string")
    assert_true(description:match("changes"))
    assert_true(description:match("start_line"))
    assert_true(description:match("end_line"))
    assert_true(description:match("code_snippet"))
  end,

  ['test_examples'] = function()
    assert_not_nil(schema.examples)

    -- Check multiple_changes example
    assert_not_nil(schema.examples.multiple_changes)
    assert_type(schema.examples.multiple_changes, "string")

    -- Check info_snippet example
    assert_not_nil(schema.examples.info_snippet)
    assert_type(schema.examples.info_snippet, "string")

    -- Check new_file example
    assert_not_nil(schema.examples.new_file)
    assert_type(schema.examples.new_file, "string")

    -- Check full_replacement example
    assert_not_nil(schema.examples.full_replacement)
    assert_type(schema.examples.full_replacement, "string")

    -- Check visual_selection example
    assert_not_nil(schema.examples.visual_selection)
    assert_type(schema.examples.visual_selection, "string")
  end,

  ['test_changes_required_fields'] = function()
    local required = schema.response_schema.properties.changes.items.required
    assert_not_nil(required)
    assert_true(vim.tbl_contains(required, "start_line"))
    assert_true(vim.tbl_contains(required, "end_line"))
    assert_true(vim.tbl_contains(required, "code"))
  end,

  ['test_validate_changes_structure'] = function()
    -- Valid change
    local valid_change = {
      start_line = 1,
      end_line = 5,
      code = "test code",
      description = "optional"
    }

    -- This would be used by a validator
    assert_eq(type(valid_change.start_line), "number")
    assert_eq(type(valid_change.end_line), "number")
    assert_eq(type(valid_change.code), "string")
    assert_true(valid_change.end_line >= valid_change.start_line)
  end,

  ['test_schema_descriptions'] = function()
    local props = schema.response_schema.properties

    -- All properties should have descriptions
    assert_not_nil(props.changes.description)
    assert_not_nil(props.code_snippet.description)
    assert_not_nil(props.explanation.description)
    assert_not_nil(props.new_file.description)
    assert_not_nil(props.replace_buffer.description)

    -- Descriptions should be informative
    assert_true(#props.changes.description > 10)
    assert_true(#props.code_snippet.description > 10)
  end,

  ['test_examples_are_valid_json'] = function()
    -- Each example should be valid JSON
    for name, example in pairs(schema.examples) do
      local ok, result = pcall(vim.fn.json_decode, example)
      assert_true(ok, "Example '" .. name .. "' should be valid JSON")
      assert_type(result, "table", "Example '" .. name .. "' should decode to table")
    end
  end,

  ['test_examples_follow_schema'] = function()
    -- Parse multiple_changes example
    local ok, result = pcall(vim.fn.json_decode, schema.examples.multiple_changes)
    assert_true(ok)
    assert_not_nil(result.changes)
    assert_type(result.changes, "table")
    assert_true(#result.changes > 0)

    local change = result.changes[1]
    assert_type(change.start_line, "number")
    assert_type(change.end_line, "number")
    assert_type(change.code, "string")

    -- Parse info_snippet example
    ok, result = pcall(vim.fn.json_decode, schema.examples.info_snippet)
    assert_true(ok)
    assert_not_nil(result.code_snippet)
    assert_type(result.code_snippet, "string")
    assert_nil(result.changes)

    -- Parse new_file example
    ok, result = pcall(vim.fn.json_decode, schema.examples.new_file)
    assert_true(ok)
    assert_not_nil(result.new_file)
    assert_type(result.new_file, "string")
    assert_not_nil(result.changes)
  end,
})