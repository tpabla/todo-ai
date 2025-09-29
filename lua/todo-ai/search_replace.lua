-- SEARCH/REPLACE transformation module
-- Handles the core logic for applying SEARCH/REPLACE changes
local M = {}

-- Apply a single SEARCH/REPLACE transformation
function M.apply_single(content, search_text, replace_text)
  -- Find the search text in content
  local start_pos, end_pos = content:find(search_text, 1, true)

  if not start_pos then
    return nil, "Search text not found"
  end

  -- Replace the first occurrence
  local result = content:sub(1, start_pos - 1) .. replace_text .. content:sub(end_pos + 1)
  return result, nil
end

-- Apply multiple SEARCH/REPLACE changes to lines
function M.apply_changes(lines, changes)
  local logger = require('todo-ai.logger')
  local content = table.concat(lines, '\n')
  local applied_count = 0
  local errors = {}

  logger.debug('Applying ' .. #changes .. ' changes to content (' .. #content .. ' chars)')

  for i, change in ipairs(changes) do
    if change.search and change.replace then
      logger.debug('Change ' .. i .. ': searching for "' .. change.search:sub(1, 100) .. '..."')
      local result, err = M.apply_single(content, change.search, change.replace)
      if result then
        content = result
        applied_count = applied_count + 1
        logger.debug('Change ' .. i .. ': applied successfully')
      else
        logger.error('Change ' .. i .. ': failed - ' .. (err or 'unknown error'))
        table.insert(errors, 'Change ' .. i .. ': ' .. (err or 'unknown error'))
      end
    else
      logger.error('Change ' .. i .. ': missing search or replace field')
      table.insert(errors, 'Change ' .. i .. ': missing search or replace field')
    end
  end

  -- Split back into lines
  local new_lines = vim.split(content, '\n', { plain = true })

  if #errors > 0 then
    return new_lines, applied_count, table.concat(errors, "; ")
  end

  return new_lines, applied_count, nil
end

-- Calculate position information for a change
function M.calculate_position(content, search_text)
  local start_pos, end_pos = content:find(search_text, 1, true)

  if not start_pos then
    return nil
  end

  -- Calculate line numbers
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

  -- Filter out rejected changes
  local accepted_changes = {}
  for i, change in ipairs(changes) do
    if not rejected_indices[i] then
      table.insert(accepted_changes, change)
    end
  end

  -- Apply accepted changes
  if #accepted_changes == 0 then
    return vim.deepcopy(original_lines)
  end

  local result, _, err = M.apply_changes(original_lines, accepted_changes)
  if err then
    -- Log error but return original if application fails
    local logger = require('todo-ai.logger')
    logger.error('search_replace', 'Failed to apply changes: ' .. err)
    return vim.deepcopy(original_lines)
  end

  return result
end

-- Track change regions for navigation
function M.track_change_regions(original_lines, changes, rejected_indices)
  rejected_indices = rejected_indices or {}
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