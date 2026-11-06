local h = require('tests.helpers')

local HANDLED = { code = 0, stdout = '{"handled":true}\n' }
local AT_EDGE = { code = 0, stdout = '{"handled":false}\n' }

---@param call string[]
---@return string[] `rex do` arguments after the script
local function script_args(call)
  assert.are.same({ 'do', '-e' }, { call[1], call[2] })
  return vim.list_slice(call, 4)
end

local function run_script(layout, direction, amount, size, zoomed_block_id)
  require('smart-splits-backend-rex').resize(direction, { amount = amount })
  local request
  local env = setmetatable({
    rex = {
      args = { block_id = vim.env.REX_BLOCK, direction = direction, amount = amount },
      session = {
        view = function()
          return { windows = { { zoomed_block_id = zoomed_block_id, layers = { { layout = layout } } } } }
        end,
        resize_pane = function(args)
          request = args
          return { revision = 1 }
        end,
      },
      block = {
        call = function()
          return size
        end,
      },
    },
  }, { __index = getfenv(1) })
  local chunk = assert(loadstring(h.calls[#h.calls][3]))
  setfenv(chunk, env)
  local result = chunk()
  return result, request
end

describe('resize()', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  it('runs the server-side resize script in the current block', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', HANDLED)
    assert.is_true(backend.resize('right', { amount = 5 }))
    assert.are.same({ 'block_id=block:test', 'direction=right', 'amount=5' }, script_args(h.calls[1]))
  end)

  it('defaults the amount to 1', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', HANDLED)
    assert.is_true(backend.resize('up', {}))
    assert.are.same({ 'block_id=block:test', 'direction=up', 'amount=1' }, script_args(h.calls[1]))
  end)

  it('grows a nested pane by the requested columns using either border', function()
    local a = { block_id = 'block:a', rect = { 0, 0, 0.25, 1 } }
    local b = { block_id = 'block:test', rect = { 0.25, 0, 0.25, 1 } }
    local c = { block_id = 'block:c', rect = { 0.5, 0, 0.5, 1 } }
    local inner = {
      rect = { 0, 0, 0.5, 1 },
      split = { direction = 'horizontal', ratio = 0.5, before = a, after = b },
    }
    local layout = {
      rect = { 0, 0, 1, 1 },
      split = { direction = 'horizontal', ratio = 0.5, before = inner, after = c },
    }
    local result, request = run_script(layout, 'right', 5, { columns = 50, rows = 24 })
    assert.is_true(result.handled)
    assert.are.equal('horizontal', request.direction)
    assert.are.equal('block:a', request.before_block_id)
    assert.are.equal('block:c', request.after_block_id)
    -- A 200-column layout gives B half of the outer split's before branch.
    assert.is_true(math.abs(200 * request.ratio * inner.split.ratio - 55) < 1e-9)

    result, request = run_script(layout, 'left', 5, { columns = 50, rows = 24 })
    assert.is_true(result.handled)
    assert.are.equal('block:a', request.before_block_id)
    assert.are.equal('block:test', request.after_block_id)
    assert.is_true(math.abs(200 * layout.split.ratio * (1 - request.ratio) - 55) < 1e-9)
  end)

  it('grows a nested pane by the requested rows using either border', function()
    local inner = {
      rect = { 0, 0.5, 1, 0.5 },
      split = {
        direction = 'vertical',
        ratio = 0.5,
        before = { block_id = 'block:test', rect = { 0, 0.5, 1, 0.25 } },
        after = { block_id = 'block:c', rect = { 0, 0.75, 1, 0.25 } },
      },
    }
    local layout = {
      rect = { 0, 0, 1, 1 },
      split = {
        direction = 'vertical',
        ratio = 0.5,
        before = { block_id = 'block:a', rect = { 0, 0, 1, 0.5 } },
        after = inner,
      },
    }
    local result, request = run_script(layout, 'up', 5, { columns = 80, rows = 25 })
    assert.is_true(result.handled)
    assert.are.equal('vertical', request.direction)
    assert.are.equal('block:a', request.before_block_id)
    assert.are.equal('block:test', request.after_block_id)
    assert.is_true(math.abs(100 * (1 - request.ratio) * inner.split.ratio - 30) < 1e-9)

    result, request = run_script(layout, 'down', 5, { columns = 80, rows = 25 })
    assert.is_true(result.handled)
    assert.are.equal('block:test', request.before_block_id)
    assert.are.equal('block:c', request.after_block_id)
    assert.is_true(math.abs(100 * (1 - layout.split.ratio) * request.ratio - 30) < 1e-9)
  end)

  it('does not resize the hidden layout while the window is zoomed', function()
    local layout = {
      rect = { 0, 0, 1, 1 },
      split = {
        direction = 'horizontal',
        ratio = 0.5,
        before = { block_id = 'block:test', rect = { 0, 0, 0.5, 1 } },
        after = { block_id = 'block:other', rect = { 0.5, 0, 0.5, 1 } },
      },
    }
    local result, request = run_script(layout, 'right', 5, { columns = 200, rows = 24 }, 'block:test')
    assert.is_false(result.handled)
    assert.is_nil(request)
  end)

  for _, case in ipairs({
    { ratio = 0.995, direction = 'right', before = true },
    { ratio = 0.005, direction = 'left', before = false },
    { ratio = 0.995, direction = 'left', before = true, expected = 0.99 },
    { ratio = 0.005, direction = 'right', before = false, expected = 0.01 },
  }) do
    it('keeps resizing ' .. case.direction .. ' monotonic from ratio ' .. case.ratio, function()
      local layout = {
        rect = { 0, 0, 1, 1 },
        split = {
          direction = 'horizontal',
          ratio = case.ratio,
          before = {
            block_id = case.before and 'block:test' or 'block:other',
            rect = { 0, 0, case.ratio, 1 },
          },
          after = {
            block_id = case.before and 'block:other' or 'block:test',
            rect = { case.ratio, 0, 1 - case.ratio, 1 },
          },
        },
      }
      local result, request = run_script(layout, case.direction, 1, { columns = 199, rows = 24 })
      if case.expected then
        assert.is_true(result.handled)
        assert.is_true(math.abs(request.ratio - case.expected) < 1e-9)
      else
        assert.is_false(result.handled)
        assert.is_nil(request)
      end
    end)
  end

  it('does not call the resize API when there is no border', function()
    local result, request = run_script({ block_id = 'block:test', rect = { 0, 0, 1, 1 } }, 'left', 2)
    assert.is_false(result.handled)
    assert.is_nil(request)
  end)

  it('returns false when the script reports no resize', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', AT_EDGE)
    assert.is_false(backend.resize('left', { amount = 2 }))
  end)

  it('returns false when the script fails', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', { code = 1 })
    assert.is_false(backend.resize('left', { amount = 2 }))
  end)

  it('returns false on unexpected output', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('do -e', { code = 0, stdout = 'nope' })
    assert.is_false(backend.resize('left', { amount = 2 }))
  end)

  it('does nothing outside Rex', function()
    local backend = require('smart-splits-backend-rex')
    h.leave_rex()
    assert.is_false(backend.resize('down', { amount = 2 }))
    assert.are.same({}, h.calls)
  end)
end)
