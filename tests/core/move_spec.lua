local h = require('tests.helpers')

describe('move()', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  for _, direction in ipairs({ 'left', 'right', 'up', 'down' }) do
    it('focuses ' .. direction, function()
      local backend = require('smart-splits-backend-rex')
      assert.is_true(backend.move(direction))
      assert.are.same({ { 'focus', direction } }, h.calls)
    end)
  end

  it('returns false at the edge with at_edge=stop', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('focus', { code = 1 })
    assert.is_false(backend.move('left', { at_edge = 'stop' }))
    assert.are.same({ { 'focus', 'left' } }, h.calls)
  end)

  it('returns false at the edge with at_edge=wrap', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('focus', { code = 1 })
    assert.is_false(backend.move('left', { at_edge = 'wrap' }))
  end)

  it('splits at the edge with at_edge=split', function()
    local backend = require('smart-splits-backend-rex')
    h.respond('focus', { code = 1 })
    assert.is_true(backend.move('up', { at_edge = 'split' }))
    assert.are.same({ { 'focus', 'up' }, { 'split', '--split=above' } }, h.calls)
  end)

  it('does not split when a neighbor exists', function()
    local backend = require('smart-splits-backend-rex')
    assert.is_true(backend.move('right', { at_edge = 'split' }))
    assert.are.equal(1, #h.calls)
  end)

  it('does nothing outside Rex', function()
    local backend = require('smart-splits-backend-rex')
    h.leave_rex()
    assert.is_false(backend.move('right'))
    assert.are.same({}, h.calls)
  end)
end)
