-- SEARCH/REPLACE transformation module
-- Delegates to Rust backend when available, falls back to Lua
local M = {}

-- Try to use the Rust backend for a synchronous call
local function rust_call(method, params)
  local ok, bridge = pcall(require, 'todo-ai.bridge')
  if not ok or not bridge.is_running() then
    return nil
  end
  local result, err = bridge.call_sync(method, params)
  if err then return nil end
  return result
end

-- Apply a single SEARCH/REPLACE transformation (Lua fallback)
function M.apply_single(content, search_text, replace_text)
  local start_pos, end_pos = content:find(search_text, 1, true)

  if not start_pos then
    return nil, "Search text not found"
  end

  local result = content:sub(1, start_pos - 1) .. replace_text .. content:sub(end_pos + 1)
  return result, nil
end

-- Apply multiple SEARCH/REPLACE changes to lines
function M.apply_changes(lines, changes)
  local logger = require('todo-ai.logger')

  -- Try Rust backend first
  local rust_result = rust_call('apply_changes', {lines = lines, changes = changes})
  if rust_result then
    logger.debug('search_replace: used Rust backend')
    return rust_result.lines, rust_result.applied_count, rust_result.errors
  end

  -- Lua fallback
  logger.debug('search_replace: using Lua fallback')
  local content = table.concat(lines, '\n')
  local applied_count = 0
  local errors = {}

  for i, change in ipairs(changes) do
    if change.search and change.replace then
      local result, err = M.apply_single(content, change.search, change.replace)
      if result then
        content = result
        applied_count = applied_count + 1
      else
        table.insert(errors, 'Change ' .. i .. ': ' .. (err or 'unknown error'))
      end
    else
      table.insert(errors, 'Change ' .. i .. ': missing search or replace field')
    end
  end

  local new_lines = vim.split(content, '\n', { plain = true })

  if #errors > 0 then
    return new_lines, applied_count, table.concat(errors, "; ")
  end

  return new_lines, applied_count, nil
end

-- Calculate position information for a change
function M.calculate_position(content, search_text)
  -- Try Rust backend
  local rust_result = rust_call('calculate_position', {content = content, search_text = search_text})
  if rust_result then
    return rust_result
  end

  -- Lua fallback
  local start_pos, end_pos = content:find(search_text, 1, true)

  if not start_pos then
    return nil
  end

  local before = content:sub(1, start_pos - 1)
  local start_line = select(2, before:gsub('\n', '\n')) + 1
  local search_lines = select(2, search_text:gsub('\n', '\n')) + 1
  local end_line = start_line + search_lines - 1

  return {
    start_pos = start_pos,
    end_pos = end_pos,
    start_line = start_line,
    end_line = end_line,
    line_count = search_lines
  }
end

-- Build display with changes applied
function M.build_display(original_lines, changes, rejected_indices)
  rejected_indices = rejected_indices or {}

  local accepted_changes = {}
  for i, change in ipairs(changes) do
    if not rejected_indices[i] then
      table.insert(accepted_changes, change)
    end
  end

  if #accepted_changes == 0 then
    return vim.deepcopy(original_lines)
  end

  local result, _, err = M.apply_changes(original_lines, accepted_changes)
  if err then
    local logger = require('todo-ai.logger')
    logger.error('search_replace', 'Failed to apply changes: ' .. err)
    return vim.deepcopy(original_lines)
  end

  return result
end

-- Track change regions for navigation
function M.track_change_regions(original_lines, changes, rejected_indices)
  rejected_indices = rejected_indices or {}

  -- Try Rust backend
  local rejected_list = {}
  for idx, _ in pairs(rejected_indices) do
    table.insert(rejected_list, idx)
  end
  local rust_result = rust_call('track_change_regions', {
    lines = original_lines,
    changes = changes,
    rejected_indices = rejected_list,
  })
  if rust_result then
    return rust_result
  end

  -- Lua fallback
  local regions = {}
  local content = table.concat(original_lines, '\n')

  for i, change in ipairs(changes) do
    if change and change.search and change.replace and not rejected_indices[i] then
      local pos_info = M.calculate_position(content, change.search)

      if pos_info then
        local replace_lines = vim.split(change.replace, '\n', { plain = true })

        table.insert(regions, {
          change_index = i,
          original_start = pos_info.start_line,
          original_end = pos_info.end_line,
          new_line_count = #replace_lines,
          search_text = change.search,
          replace_text = change.replace,
          description = change.description
        })
      end
    end
  end

  return regions
end

-- Validate a change structure
function M.validate_change(change)
  if not change then
    return false, "Change is nil"
  end

  if not change.search or type(change.search) ~= "string" then
    return false, "Missing or invalid 'search' field"
  end

  if not change.replace or type(change.replace) ~= "string" then
    return false, "Missing or invalid 'replace' field"
  end

  return true, nil
end

-- Validate all changes
function M.validate_changes(changes)
  if not changes or type(changes) ~= "table" then
    return false, "Changes must be a table"
  end

  for i, change in ipairs(changes) do
    local valid, err = M.validate_change(change)
    if not valid then
      return false, string.format("Change %d: %s", i, err)
    end
  end

  return true, nil
end

return M
