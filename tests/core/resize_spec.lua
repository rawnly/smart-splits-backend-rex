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
