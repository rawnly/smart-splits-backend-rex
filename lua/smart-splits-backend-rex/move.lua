---@module 'smart-splits.backend'

local rex = require('smart-splits-backend-rex.rex')

local M = {}

---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendMoveOpts
---@return boolean
function M.move(direction, opts)
  if not rex.is_available() then
    return false
  end

  opts = opts or {}
  local at_edge = opts.at_edge or 'stop'

  if rex.focus(direction) then
    return true
  end

  -- Rex has no wrap-around focus, so only 'split' is handled here. For 'wrap'
  -- and 'stop' return false and let smart-splits core deal with the edge.
  if at_edge == 'split' then
    return rex.split(direction)
  end

  return false
end

return M
