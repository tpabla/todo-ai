-- Response parser module
-- Delegates to Rust backend (required)
local M = {}

local bridge = require('todo-ai.bridge')

-- Parse response from LLM
function M.parse(response, hint)
  local result, err = bridge.call_sync('parse_response', {
    response = response,
    hint = hint,
  })
  if err then
    error('parser.parse failed: ' .. err)
  end
  return result
end

return M
