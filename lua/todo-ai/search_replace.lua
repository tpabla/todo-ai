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

return M