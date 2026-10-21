---@module 'smart-splits.backend'

local rex = require('smart-splits-backend-rex.rex')

local M = {}

---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendResizeOpts
---@return boolean
function M.resize(direction, opts)
  if not rex.is_available() then
    return false
  end

  opts = opts or {}
  return rex.resize(direction, opts.amount or 1)
end

return M
