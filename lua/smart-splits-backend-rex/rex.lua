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

---Runs a Lua script with `rex do -e` and reports whether it returned `{ handled = true }`.
---@param script string
---@param args string[] `key=value` pairs exposed to the script as `rex.args`
---@return boolean
local function run_script(script, args)
  local result = M.run(vim.list_extend({ 'do', '-e', script }, args))
  if result == nil or result.code ~= 0 then
    return false
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout)
  return ok and type(decoded) == 'table' and decoded.handled == true
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
  return run_script(FOCUS_SCRIPT, { 'direction=' .. direction, 'wrap=' .. tostring(wrap == true) })
end

---Splits the current block, placing the new terminal in `direction`.
---@param direction SmartSplitsDirection
---@return boolean
function M.split(direction)
  return succeeded({ 'split', '--split=' .. SPLIT_PLACEMENT[direction] })
end

---Moves a border of the block `amount` cells in `direction` with the server's `session.resize_pane`, so no
---app client is involved. Prefers the block's right (or bottom) border, like Neovim, and falls back to
---its left (or top) one. `resize_pane` takes a ratio, so cells are converted with the block's size.
local RESIZE_SCRIPT = [[
local block_id, direction = rex.args.block, rex.args.direction
local amount = tonumber(rex.args.amount) or 1
local axis = (direction == 'left' or direction == 'right') and 'horizontal' or 'vertical'
local dim = axis == 'horizontal' and 3 or 4 -- index of w or h in a rect

local function first_block(node)
  while node.split do
    node = node.split.before
  end
  return node.block_id
end

-- Returns the block's leaf node and the splits above it, innermost first, with the block's side.
local function find(node, path)
  if node.block_id then
    return node.block_id == block_id and node or nil, path
  end
  if not node.split then
    return nil, path
  end
  for _, side in ipairs({ 'before', 'after' }) do
    local leaf = find(node.split[side], path)
    if leaf then
      table.insert(path, { node = node, side = side })
      return leaf, path
    end
  end
  return nil, path
end

local view = assert(rex.session.view({}))
local leaf, path
for _, window in ipairs(view.windows or {}) do
  for _, layer in ipairs(window.layers or {}) do
    if layer.layout and not leaf then
      leaf, path = find(layer.layout, {})
    end
  end
end
if not leaf then
  return { handled = false }
end

local target
for _, want in ipairs({ 'before', 'after' }) do
  for _, entry in ipairs(path) do
    if not target and entry.side == want and entry.node.split.direction == axis then
      target = entry
    end
  end
end
if not target then
  return { handled = false }
end

local size = assert(rex.block.call('com.superlogical.terminal', 'size', { block_id = block_id }))
local cells = axis == 'horizontal' and size.columns or size.rows
local split = target.node.split
local delta = amount * leaf.rect[dim] / (cells * target.node.rect[dim])
if direction == 'left' or direction == 'up' then
  delta = -delta
end
local ratio = math.min(0.99, math.max(0.01, split.ratio + delta))
if ratio == split.ratio then
  return { handled = false }
end
assert(rex.session.resize_pane({
  direction = axis,
  before_block_id = target.side == 'before' and block_id or first_block(split.before),
  after_block_id = target.side == 'after' and block_id or first_block(split.after),
  ratio = ratio,
}))
return { handled = true }
]]

---Moves a border of the current block `amount` cells in `direction`.
---Returns false when the block has no border on that axis.
---@param direction SmartSplitsDirection
---@param amount integer
---@return boolean
function M.resize(direction, amount)
  return run_script(RESIZE_SCRIPT, { 'block=' .. vim.env.REX_BLOCK, 'direction=' .. direction, 'amount=' .. amount })
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
