#!/usr/bin/env lua

---@diagnostic disable: undefined-global

-- API Documentation Generator for TodoAI
-- Extracts LuaLS annotations and generates markdown documentation

local M = {}

---Parse a Lua file for LuaLS annotations
---@param file_path string
---@return table parsed_info
function M.parse_file(file_path)
  local file = io.open(file_path, 'r')
  if not file then
    return {}
  end

  local content = file:read('*all')
  file:close()

  local info = {
    classes = {},
    functions = {},
    types = {},
    file_doc = nil
  }

  -- Extract file-level documentation
  local file_doc = content:match('^%-%-%-(.-)%s*local')
  if file_doc then
    info.file_doc = file_doc:gsub('^%-%-%-?%s*', ''):gsub('%s*%-%-%-?%s*', '\n')
  end

  -- Extract @class definitions
  for class_def in content:gmatch('%-%-%-@class%s+([^\n]+)') do
    local class_name = class_def:match('^(%S+)')
    if class_name then
      info.classes[class_name] = {
        name = class_name,
        definition = class_def,
        fields = {},
        methods = {}
      }
    end
  end

  -- Extract @field definitions
  for field_def in content:gmatch('%-%-%-@field%s+([^\n]+)') do
    local field_name, field_type, field_desc = field_def:match('^(%S+)%s+([^%s]+)(.*)$')
    if field_name and field_type then
      -- Find the class this field belongs to
      for class_name, class_info in pairs(info.classes) do
        table.insert(class_info.fields, {
          name = field_name,
          type = field_type,
          description = field_desc and field_desc:match('^%s*(.*)') or ''
        })
      end
    end
  end

  -- Extract functions with their annotations
  local function_pattern = '(%-%-%-.-\n)function%s+([%w_.]+)%s*%(([^)]*)%)'
  for annotations, func_name, params in content:gmatch(function_pattern) do
    local func_info = {
      name = func_name,
      params = {},
      returns = {},
      description = '',
      annotations = annotations
    }

    -- Parse parameters
    for param in params:gmatch('[^,]+') do
      local clean_param = param:match('^%s*(.-)%s*$')
      if clean_param ~= '' then
        table.insert(func_info.params, clean_param)
      end
    end

    -- Parse annotations
    for annotation in annotations:gmatch('%-%-%-@([^\n]+)') do
      local cmd, rest = annotation:match('^(%S+)%s*(.*)')
      if cmd == 'param' then
        local param_name, param_type, param_desc = rest:match('^(%S+)%s+([^%s]+)(.*)$')
        if param_name and param_type then
          func_info.params[param_name] = {
            type = param_type,
            description = param_desc and param_desc:match('^%s*(.*)') or ''
          }
        end
      elseif cmd == 'return' then
        table.insert(func_info.returns, rest)
      elseif not cmd:match('^[a-z_]+$') then
        -- Description line
        func_info.description = func_info.description .. ' ' .. annotation
      end
    end

    -- Clean up description
    func_info.description = func_info.description:match('^%s*(.-)%s*$') or ''

    info.functions[func_name] = func_info
  end

  return info
end

---Generate markdown documentation for a file
---@param file_info table
---@param file_path string
---@return string markdown
function M.generate_markdown(file_info, file_path)
  local lines = {}

  -- File header
  local module_name = file_path:match('([^/]+)%.lua$') or file_path
  table.insert(lines, '# ' .. module_name)
  table.insert(lines, '')

  if file_info.file_doc then
    table.insert(lines, file_info.file_doc)
    table.insert(lines, '')
  end

  -- Classes
  for class_name, class_info in pairs(file_info.classes) do
    table.insert(lines, '## Class: ' .. class_name)
    table.insert(lines, '')
    table.insert(lines, '```lua')
    table.insert(lines, class_info.definition)
    table.insert(lines, '```')
    table.insert(lines, '')

    -- Fields
    if #class_info.fields > 0 then
      table.insert(lines, '### Fields')
      table.insert(lines, '')
      for _, field in ipairs(class_info.fields) do
        table.insert(lines, string.format('- **%s** (`%s`): %s',
          field.name, field.type, field.description))
      end
      table.insert(lines, '')
    end
  end

  -- Functions
  if next(file_info.functions) then
    table.insert(lines, '## Functions')
    table.insert(lines, '')

    for func_name, func_info in pairs(file_info.functions) do
      table.insert(lines, '### ' .. func_name)
      table.insert(lines, '')

      if func_info.description ~= '' then
        table.insert(lines, func_info.description)
        table.insert(lines, '')
      end

      -- Function signature
      local param_list = {}
      for _, param in ipairs(func_info.params) do
        table.insert(param_list, param)
      end

      table.insert(lines, '```lua')
      table.insert(lines, string.format('function %s(%s)', func_name, table.concat(param_list, ', ')))
      table.insert(lines, '```')
      table.insert(lines, '')

      -- Parameters
      if type(func_info.params) == 'table' and next(func_info.params) then
        table.insert(lines, '**Parameters:**')
        table.insert(lines, '')
        for param_name, param_info in pairs(func_info.params) do
          if type(param_info) == 'table' then
            table.insert(lines, string.format('- `%s` (%s): %s',
              param_name, param_info.type, param_info.description))
          end
        end
        table.insert(lines, '')
      end

      -- Returns
      if #func_info.returns > 0 then
        table.insert(lines, '**Returns:**')
        table.insert(lines, '')
        for _, ret in ipairs(func_info.returns) do
          table.insert(lines, '- ' .. ret)
        end
        table.insert(lines, '')
      end
    end
  end

  return table.concat(lines, '\n')
end

---Generate documentation for all Lua files in a directory
---@param source_dir string
---@param output_dir string
function M.generate_docs(source_dir, output_dir)
  -- Ensure output directory exists
  os.execute('mkdir -p ' .. output_dir)

  -- Find all Lua files
  local handle = io.popen('find ' .. source_dir .. ' -name "*.lua" -type f')
  if not handle then
    print("Error: Could not list Lua files")
    return
  end

  local files = {}
  for file in handle:lines() do
    table.insert(files, file)
  end
  handle:close()

  -- Generate docs for each file
  for _, file_path in ipairs(files) do
    print("Processing: " .. file_path)

    local file_info = M.parse_file(file_path)
    local markdown = M.generate_markdown(file_info, file_path)

    -- Create output file path
    local rel_path = file_path:gsub('^' .. source_dir .. '/?', '')
    local out_path = output_dir .. '/' .. rel_path:gsub('%.lua$', '.md')

    -- Ensure output subdirectory exists
    local out_dir = out_path:match('(.+)/[^/]+$')
    if out_dir then
      os.execute('mkdir -p ' .. out_dir)
    end

    -- Write documentation
    local out_file = io.open(out_path, 'w')
    if out_file then
      out_file:write(markdown)
      out_file:close()
      print("Generated: " .. out_path)
    else
      print("Error: Could not write to " .. out_path)
    end
  end
end

-- Main execution
if arg and arg[0] and arg[0]:match('generate_docs%.lua$') then
  local source_dir = arg[1] or 'lua/todo-ai'
  local output_dir = arg[2] or 'docs/api'

  print("Generating API documentation...")
  print("Source: " .. source_dir)
  print("Output: " .. output_dir)
  print()

  M.generate_docs(source_dir, output_dir)

  print()
  print("Documentation generation complete!")
end

return M