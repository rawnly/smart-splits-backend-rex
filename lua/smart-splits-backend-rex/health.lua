local config = require('smart-splits-backend-rex.config')
local rex = require('smart-splits-backend-rex.rex')

local M = {}

function M.report()
  if rex.has_cli() then
    vim.health.ok(string.format('`%s` executable found', config.options.bin))
  else
    vim.health.error(string.format('`%s` executable not found in PATH', config.options.bin), {
      'Install Rex, or set `bin` in the backend options',
    })
    return
  end

  if rex.in_rex() then
    vim.health.ok('Running inside a Rex terminal')
  else
    vim.health.warn('Not running inside a Rex terminal', {
      'REX_SESSION and REX_BLOCK are not set, so the backend is inactive',
    })
    return
  end

  local version = rex.version()
  if version then
    vim.health.ok('Connected to Rex server ' .. version)
  else
    vim.health.error('Could not reach the Rex server', { 'Try `rex api call server.version`' })
  end
end

---@return nil
function M.check()
  vim.health.start('backend-rex')
  M.report()
end

return M
