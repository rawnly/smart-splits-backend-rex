local h = require('tests.helpers')

---@param call string[]
---@return string[] `rex do` arguments after the script
local function resize_args(call)
  assert.are.same({ 'do', '-e' }, { call[1], call[2] })
  return vim.list_slice(call, 4)
end

describe('resize()', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  it('resizes the current block through the server', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', { code = 0, stdout = '{"handled":true}\n' })
    assert.is_true(backend.resize('right', { amount = 5 }))
    assert.are.equal(1, #h.calls)
    assert.are.same({ 'block=block:test', 'direction=right', 'amount=5' }, resize_args(h.calls[1]))
  end)

  it('defaults the amount to 1', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', { code = 0, stdout = '{"handled":true}\n' })
    assert.is_true(backend.resize('up', {}))
    assert.are.same({ 'block=block:test', 'direction=up', 'amount=1' }, resize_args(h.calls[1]))
  end)

  it('returns false when there is no border to move', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', { code = 0, stdout = '{"handled":false}\n' })
    assert.is_false(backend.resize('left', { amount = 2 }))
  end)

  it('returns false when rex fails', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', { code = 1 })
    assert.is_false(backend.resize('left', { amount = 2 }))
  end)

  it('does nothing outside Rex', function()
    local backend = require('smart-splits-backend-rex')
    h.leave_rex()
    assert.is_false(backend.resize('down', { amount = 2 }))
    assert.are.same({}, h.calls)
  end)
end)

-- Builds a layout node with rects computed from ratios, like `session.view` reports.
local function block(id)
  return function(rect)
    return { block_id = id, rect = rect }
  end
end

local function split(direction, ratio, before, after)
  return function(rect)
    local x, y, w, ht = unpack(rect)
    local a, b
    if direction == 'horizontal' then
      a, b = { x, y, w * ratio, ht }, { x + w * ratio, y, w * (1 - ratio), ht }
    else
      a, b = { x, y, w, ht * ratio }, { x, y + ht * ratio, w, ht * (1 - ratio) }
    end
    return { rect = rect, split = { direction = direction, ratio = ratio, before = before(a), after = after(b) } }
  end
end

---Runs the resize script against a fake `rex` and returns its result and the `resize_pane` calls.
---@param layout function built with `block` and `split`
---@param args table<string, string>
---@param opts? { zoomed?: string, size?: table }
local function run_script(layout, args, opts)
  opts = opts or {}
  local calls = {}
  local rex = {
    args = args,
    session = {
      view = function()
        return {
          revision = 1,
          windows = { { zoomed_block_id = opts.zoomed, layers = { { layout = layout({ 0, 0, 1, 1 }) } } } },
        }
      end,
      resize_pane = function(a)
        table.insert(calls, a)
        return { revision = 2 }
      end,
    },
    block = {
      call = function()
        return opts.size or { columns = 50, rows = 25 } -- a half pane of a 100x50 window
      end,
    },
  }
  local fn = assert(loadstring(require('smart-splits-backend-rex.rex').RESIZE_SCRIPT))
  setfenv(fn, setmetatable({ rex = rex }, { __index = getfenv(1) }))
  return fn(), calls
end

describe('resize script', function()
  local A_B = split('horizontal', 0.5, block('A'), block('B'))

  it('moves the right border of the left block to the right', function()
    local result, calls = run_script(A_B, { block = 'A', direction = 'right', amount = '10' })
    assert.is_true(result.handled)
    assert.are.equal(1, #calls)
    assert.are.same('horizontal', calls[1].direction)
    assert.are.same({ 'A', 'B' }, { calls[1].before_block_id, calls[1].after_block_id })
    assert.is_true(math.abs(calls[1].ratio - 0.6) < 1e-9)
  end)

  it('moves the left border of the right block to the left', function()
    local result, calls = run_script(A_B, { block = 'B', direction = 'left', amount = '10' })
    assert.is_true(result.handled)
    assert.are.same({ 'A', 'B' }, { calls[1].before_block_id, calls[1].after_block_id })
    assert.is_true(math.abs(calls[1].ratio - 0.4) < 1e-9)
  end)

  it('resizes stacked blocks with rows', function()
    local stacked = split('vertical', 0.5, block('A'), block('B'))
    local _, calls = run_script(stacked, { block = 'A', direction = 'down', amount = '5' })
    assert.are.same('vertical', calls[1].direction)
    assert.is_true(math.abs(calls[1].ratio - 0.6) < 1e-9)
  end)

  it('keeps the other panes size across nested splits', function()
    -- (A|B)|C: A, B and C are each a third. B's right border is the outer split.
    local layout = split('horizontal', 2 / 3, split('horizontal', 0.5, block('A'), block('B')), block('C'))
    local result, calls = run_script(layout, { block = 'B', direction = 'right', amount = '10' }, {
      size = { columns = 30, rows = 50 },
    })
    assert.is_true(result.handled)
    assert.are.equal(2, #calls)
    assert.are.same({ 'B', 'C' }, { calls[1].before_block_id, calls[1].after_block_id })
    assert.is_true(math.abs(calls[1].ratio - 7 / 9) < 1e-9)
    -- The inner split now spans 7/9 of the window; A keeps its 1/3.
    assert.are.same({ 'A', 'B' }, { calls[2].before_block_id, calls[2].after_block_id })
    assert.is_true(math.abs(calls[2].ratio * 7 / 9 - 1 / 3) < 1e-9)
  end)

  it('returns false without a split on the axis', function()
    local result, calls = run_script(A_B, { block = 'A', direction = 'up', amount = '1' })
    assert.is_false(result.handled)
    assert.are.same({}, calls)
  end)

  it('returns false once the border reaches the limit', function()
    local edge = split('horizontal', 0.99, block('A'), block('B'))
    local result, calls = run_script(edge, { block = 'A', direction = 'right', amount = '10' })
    assert.is_false(result.handled)
    assert.are.same({}, calls)
  end)

  it('clamps the ratio short of the limit', function()
    local _, calls = run_script(A_B, { block = 'A', direction = 'right', amount = '1000' })
    assert.are.equal(0.99, calls[1].ratio)
  end)

  it('returns false while the window is zoomed', function()
    local result, calls = run_script(A_B, { block = 'A', direction = 'right', amount = '1' }, { zoomed = 'A' })
    assert.is_false(result.handled)
    assert.are.same({}, calls)
  end)

  it('returns false when the terminal has no size', function()
    local result, calls = run_script(A_B, { block = 'A', direction = 'right', amount = '1' }, {
      size = { columns = 0, rows = 0 },
    })
    assert.is_false(result.handled)
    assert.are.same({}, calls)
  end)

  it('returns false for a block not in the view', function()
    local result = run_script(A_B, { block = 'Z', direction = 'right', amount = '1' })
    assert.is_false(result.handled)
  end)
end)
