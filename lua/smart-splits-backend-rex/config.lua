---@class RexBackend.Config
---@field enable boolean
---@field bin string Name or path of the `rex` executable
---@field timeout integer Milliseconds to wait for a `rex` command

---@alias RexBackend.PartialConfig { enable?: boolean, bin?: string, timeout?: integer }

local M = {}

---@type RexBackend.Config
M.defaults = {
  enable = true,
  bin = 'rex',
  timeout = 2000,
}

---@type RexBackend.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? RexBackend.PartialConfig
---@return RexBackend.Config
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend('force', M.defaults, opts)
  return M.options
end

return M
