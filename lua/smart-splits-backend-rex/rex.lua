local config = require('smart-splits-backend-rex.config')

---Thin wrapper around the `rex` CLI. Every terminal Rex opens has `REX_SESSION`
---and `REX_BLOCK` set, and the CLI acts on that session and block by default.
---@see https://www.superlogical.com/rex/docs/automate/cli

local M = {}

---@alias RexBackend.Result { code: integer, stdout: string, stderr: string }

---Maps a smart-splits direction to the `--split` placement `rex split` takes.
---@type table<SmartSplitsDirection, string>
local SPLIT_PLACEMENT = {
  left = 'left',
  right = 'right',
  up = 'above',
  down = 'below',
}

---@return boolean
function M.in_rex()
  local session = vim.env.REX_SESSION
  local block = vim.env.REX_BLOCK
  return session ~= nil and session ~= '' and block ~= nil and block ~= ''
end

---@return boolean
function M.has_cli()
  return vim.fn.executable(config.options.bin) == 1
end

---@return boolean
function M.is_available()
  return M.in_rex() and M.has_cli()
end

---Runs `rex <args...>` and waits for it to exit.
---@param args string[]
---@return RexBackend.Result?
function M.run(args)
  local cmd = { config.options.bin }
  vim.list_extend(cmd, args)

  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok then
    return nil
  end

  local result = proc:wait(config.options.timeout)
  return { code = result.code, stdout = result.stdout or '', stderr = result.stderr or '' }
end

---@param args string[]
---@return boolean
local function succeeded(args)
  local result = M.run(args)
  return result ~= nil and result.code == 0
end

---`rex focus` exits 0 even at the edge of the layout, so focus through the API instead and compare the
---session's structural revision, which changes only when the focus moved.
local FOCUS_SCRIPT = [[
local view = assert(rex.session.view({}))
local result = assert(rex.session.focus_direction({ direction = rex.args.direction, wrap = rex.args.wrap == true }))
return { handled = result.revision ~= view.revision }
]]

---Focuses the nearest block in `direction`, or the one on the other side with `wrap`.
---Returns false when there is no block to focus.
---@param direction SmartSplitsDirection
---@param wrap? boolean
---@return boolean
function M.focus(direction, wrap)
  local result = M.run({ 'do', '-e', FOCUS_SCRIPT, 'direction=' .. direction, 'wrap=' .. tostring(wrap == true) })
  if result == nil or result.code ~= 0 then
    return false
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout)
  return ok and type(decoded) == 'table' and decoded.handled == true
end

---Splits the current block, placing the new terminal in `direction`.
---@param direction SmartSplitsDirection
---@return boolean
function M.split(direction)
  return succeeded({ 'split', '--split=' .. SPLIT_PLACEMENT[direction] })
end

---Moves the border of the current pane via the app's `pane.resize` action.
---Needs the Rex app running with Remote Control enabled.
---@param direction SmartSplitsDirection
---@param amount integer
---@return boolean
function M.resize(direction, amount)
  return succeeded({ 'do', 'pane.resize', 'direction=' .. direction, 'amount=' .. amount })
end

---@return string? version
function M.version()
  local result = M.run({ 'api', 'call', 'server.version' })
  if result == nil or result.code ~= 0 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout)
  if ok and type(decoded) == 'table' then
    return decoded.rex_version
  end
  return nil
end

return M
