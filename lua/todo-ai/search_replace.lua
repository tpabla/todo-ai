-- SEARCH/REPLACE transformation module
-- Delegates to Rust backend (required)
local M = {}

local bridge = require('todo-ai.bridge')

-- Apply multiple SEARCH/REPLACE changes to lines
function M.apply_changes(lines, changes)
  local result, err = bridge.call_sync('apply_changes', {lines = lines, changes = changes})
  if err then
    error('search_replace.apply_changes failed: ' .. err)
  end
  return result.lines, result.applied_count, result.errors
end

-- Calculate position information for a change
function M.calculate_position(content, search_text)
  local result, err = bridge.call_sync('calculate_position', {content = content, search_text = search_text})
  if err then
    error('search_replace.calculate_position failed: ' .. err)
  end
  return result
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

  local rejected_list = {}
  for idx, _ in pairs(rejected_indices) do
    table.insert(rejected_list, idx)
  end

  local result, err = bridge.call_sync('track_change_regions', {
    lines = original_lines,
    changes = changes,
    rejected_indices = rejected_list,
  })
  if err then
    error('search_replace.track_change_regions failed: ' .. err)
  end
  return result
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
