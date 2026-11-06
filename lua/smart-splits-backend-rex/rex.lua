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

---Moves the nearest border in `direction`, falling back to the opposite border at the layout edge.
---Uses the server API so resizing does not depend on app focus or Remote Control.
local RESIZE_SCRIPT = [[
local direction = rex.args.direction
local horizontal = direction == 'left' or direction == 'right'
local axis = horizontal and 'horizontal' or 'vertical'
local forwards = direction == 'right' or direction == 'down'
local primary
local fallback

local function visit(node)
  if node.block_id then
    return node.block_id == rex.args.block_id
  end
  local split = node.split
  if not split then
    return false
  end
  local before = visit(split.before)
  local after = visit(split.after)
  if (before or after) and split.direction == axis then
    if before == forwards then
      primary = primary or { split = split, before = before }
    else
      fallback = fallback or { split = split, before = before }
    end
  end
  return before or after
end

local view = assert(rex.session.view({}))
for _, window in ipairs(view.windows or {}) do
  for _, layer in ipairs(window.layers or {}) do
    if layer.layout and visit(layer.layout) and window.zoomed_block_id then
      return { handled = false }
    end
  end
end

local target = primary or fallback
if not target then
  return { handled = false }
end
local split = target.split

local function first_block(node)
  if node.block_id then
    return node.block_id
  end
  return first_block(node.split.before)
end

local size = assert(rex.block.call('com.superlogical.terminal', 'size', { block_id = rex.args.block_id }))
local cells = horizontal and size.columns or size.rows
if cells <= 0 then
  return { handled = false }
end
-- Descendant ratios stay fixed, so scale the step to change the current pane by the requested cells.
local share = target.before and split.ratio or (1 - split.ratio)
local delta = rex.args.amount * share / cells
local min_ratio = math.min(0.01, split.ratio)
local max_ratio = math.max(0.99, split.ratio)
local ratio = math.max(min_ratio, math.min(max_ratio, split.ratio + (forwards and delta or -delta)))
if ratio == split.ratio then
  return { handled = false }
end
assert(rex.session.resize_pane({
  direction = axis,
  before_block_id = first_block(split.before),
  after_block_id = first_block(split.after),
  ratio = ratio,
}))
return { handled = true }
]]

---@param direction SmartSplitsDirection
---@param amount integer
---@return boolean
function M.resize(direction, amount)
  local result = M.run({
    'do',
    '-e',
    RESIZE_SCRIPT,
    'block_id=' .. vim.env.REX_BLOCK,
    'direction=' .. direction,
    'amount=' .. amount,
  })
  if result == nil or result.code ~= 0 then
    return false
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout)
  return ok and type(decoded) == 'table' and decoded.handled == true
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
