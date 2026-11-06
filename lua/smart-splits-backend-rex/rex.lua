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
    -- A clean miss returns `handled = false`, so a failure here is a real error worth surfacing.
    local err = result and vim.trim(result.stderr) or ''
    if err ~= '' then
      vim.notify_once('smart-splits-backend-rex: ' .. err, vim.log.levels.WARN)
    end
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
---Splits between the block and the moved border keep their other panes' sizes, like Neovim and tmux.
---Exposed for tests.
M.RESIZE_SCRIPT = [[
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
local leaf, path, window
for _, w in ipairs(view.windows or {}) do
  for _, layer in ipairs(w.layers or {}) do
    if layer.layout and not leaf then
      leaf, path = find(layer.layout, {})
      window = leaf and w
    end
  end
end
-- A zoomed window hides its layout, so resizing would change splits the user can't see.
if not leaf or window.zoomed_block_id then
  return { handled = false }
end

local target, index
for _, want in ipairs({ 'before', 'after' }) do
  for i, entry in ipairs(path) do
    if not target and entry.side == want and entry.node.split.direction == axis then
      target, index = entry, i
    end
  end
end
if not target then
  return { handled = false }
end

local size = assert(rex.block.call('com.superlogical.terminal', 'size', { block_id = block_id }))
local cells = axis == 'horizontal' and size.columns or size.rows
local span = target.node.rect[dim]
if type(cells) ~= 'number' or cells <= 0 or span <= 0 then
  return { handled = false }
end

local function resize(entry, ratio)
  local split = entry.node.split
  assert(rex.session.resize_pane({
    direction = axis,
    before_block_id = entry.side == 'before' and block_id or first_block(split.before),
    after_block_id = entry.side == 'after' and block_id or first_block(split.after),
    ratio = ratio,
  }))
end

local old = target.node.split.ratio
local delta = amount * leaf.rect[dim] / (cells * span)
if direction == 'left' or direction == 'up' then
  delta = -delta
end
local ratio = math.min(0.99, math.max(0.01, old + delta))
if ratio == old then
  return { handled = false }
end
resize(target, ratio)

-- The block's side of the target grew by `grow` (a window fraction), and so did every split between it
-- and the block. Give the growth to the block's side of each, so their other panes keep their size.
local grow = (ratio - old) * span * (target.side == 'before' and 1 or -1)
for i = 1, index - 1 do
  local entry = path[i]
  local split = entry.node.split
  if split.direction == axis then
    local w = entry.node.rect[dim]
    local before = split.ratio * w + (entry.side == 'before' and grow or 0)
    resize(entry, before / (w + grow))
  end
end
return { handled = true }
]]

---Moves a border of the current block `amount` cells in `direction`.
---Returns false when the block has no border on that axis.
---@param direction SmartSplitsDirection
---@param amount integer
---@return boolean
function M.resize(direction, amount)
  return run_script(M.RESIZE_SCRIPT, { 'block=' .. vim.env.REX_BLOCK, 'direction=' .. direction, 'amount=' .. amount })
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
