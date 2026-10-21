---@module 'smart-splits.backend'

local config = require('smart-splits-backend-rex.config')
local health = require('smart-splits-backend-rex.health')
local move = require('smart-splits-backend-rex.move')
local resize = require('smart-splits-backend-rex.resize')
local rex = require('smart-splits-backend-rex.rex')

---@type SmartSplitsBackend
local M = {
  name = 'smart-splits-backend-rex',
  protocol_version = '3.0.0',
  setup = function(opts)
    config.setup(opts)
  end,
  detect = function()
    return config.options.enable and rex.is_available()
  end,
  move = move.move,
  resize = resize.resize,
  health = health.report,
}

return M
