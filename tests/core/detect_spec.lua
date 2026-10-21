local h = require('tests.helpers')

describe('detect()', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  it('returns true inside a Rex terminal', function()
    local backend = require('smart-splits-backend-rex')
    assert.is_true(backend.detect())
  end)

  it('returns false outside Rex', function()
    local backend = require('smart-splits-backend-rex')
    h.leave_rex()
    assert.is_false(backend.detect())
  end)

  it('returns false when the rex CLI is missing', function()
    local backend = require('smart-splits-backend-rex')
    h.remove_cli()
    assert.is_false(backend.detect())
  end)

  it('returns false when disabled', function()
    local backend = require('smart-splits-backend-rex')
    backend.setup({ enable = false })
    assert.is_false(backend.detect())
  end)
end)
