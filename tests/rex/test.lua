-- Run with luajit tests/rex/test.lua from the repository root.
local bindings, actions, calls, foreground, process_available, focus_error

local function reset()
  bindings, actions, calls = {}, {}, {}
  foreground, process_available, focus_error = nil, true, nil
  rex = {
    bind = function(key)
      bindings[#bindings + 1] = key
    end,
    action = function(action)
      actions[action.name] = action
    end,
    block = {
      call = function()
        if not process_available then
          return nil
        end
        return { foreground = foreground }
      end,
    },
    session = {
      focus_direction = function(args)
        calls[#calls + 1] = { name = 'focus', args = args }
        return nil, focus_error
      end,
    },
    client = {
      queue = function(name, args)
        calls[#calls + 1] = { name = name, args = args }
      end,
    },
  }
end

local plugin = dofile('rex/lua/smart-splits-rex/init.lua')
local ctx = { block_id = 'block:1' }

reset()
plugin.setup({})
assert(#bindings == 0 and actions.smart_splits_focus and actions.smart_splits_resize)
local focus = actions.smart_splits_focus.run
local resize = actions.smart_splits_resize.run
foreground = { name = 'nvim' }
focus(ctx, { direction = 'left', key = 'ctrl+h' })
assert(calls[1].name == 'pane.send_key' and calls[1].args.key == 'ctrl+h')
foreground = { name = 'shell', argv0 = '/usr/local/bin/vim' }
resize(ctx, { direction = 'down', key = 'alt+j' })
assert(calls[2].name == 'pane.send_key' and calls[2].args.key == 'alt+j')
assert(not pcall(focus, ctx, { direction = 'left' }))
foreground = { name = 'zsh' }
focus(ctx, { direction = 'left' })
assert(calls[3].name == 'focus' and calls[3].args.direction == 'left')
resize(ctx, { direction = 'down' })
assert(calls[4].name == 'pane.resize' and calls[4].args.amount == 3)
resize(ctx, { direction = 'up', amount = 9 })
assert(calls[5].args.direction == 'up' and calls[5].args.amount == 9)
focus_error = 'failed'
assert(not pcall(focus, ctx, { direction = 'left' }))
process_available = false
assert(not pcall(focus, ctx, { direction = 'left', key = 'ctrl+h' }))
assert(not pcall(resize, ctx, { direction = 'left', key = 'alt+h' }))
assert(not pcall(focus, {}, { direction = 'left', key = 'ctrl+h' }))

reset()
plugin.setup({ resize_amount = 7 })
assert(#bindings == 0 and actions.smart_splits_focus and actions.smart_splits_resize)
foreground = { name = 'zsh' }
actions.smart_splits_resize.run(ctx, { direction = 'right' })
assert(calls[1].args.direction == 'right' and calls[1].args.amount == 7)
reset()
plugin.setup()
assert(#bindings == 0 and actions.smart_splits_focus and actions.smart_splits_resize)

print('Rex module tests passed')
