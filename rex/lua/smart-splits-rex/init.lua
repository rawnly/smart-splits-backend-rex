-- Rex actions for smart-splits-backend-rex. Key bindings are configured by the user.

---@class SmartSplitsRexOptions
---@field resize_amount? number Default resize amount passed to Rex. Defaults to 3.

local M = { version = '0.1.0', author = 'rawnly' }

local function is_vim(ctx)
  if not ctx.block_id then
    return nil
  end
  local proc = rex.block.call('com.superlogical.terminal', 'process', { block_id = ctx.block_id })
  if not proc then
    return nil
  end
  local fg = proc.foreground
  if not fg then
    return false
  end
  for _, name in ipairs({ fg.name or '', (fg.argv0 or ''):match('[^/]*$') }) do
    if name:match('^n?vim') then
      return true
    end
  end
  return false
end

local function forward_if_vim(ctx, args)
  local vim = is_vim(ctx)
  if vim == nil then
    error('smart-splits: cannot determine foreground process', 0)
  end
  if not vim then
    return false
  end
  if not args.key or args.key == '' then
    error('smart-splits: key is required to forward to Neovim', 0)
  end
  rex.client.queue('pane.send_key', { key = args.key })
  return true
end

---@param opts? SmartSplitsRexOptions
function M.setup(opts)
  opts = opts or {}
  rex.action({
    name = 'smart_splits_focus',
    title = 'Smart Splits: Focus Pane',
    args = {
      type = 'object',
      required = { 'direction' },
      properties = {
        direction = { type = 'string', enum = { 'left', 'right', 'up', 'down' } },
        key = { type = 'string' },
      },
    },
    run = function(ctx, args)
      if forward_if_vim(ctx, args) then
        return
      end
      local _, err = rex.session.focus_direction({ direction = args.direction })
      if err then
        error('smart-splits: ' .. err, 0)
      end
    end,
  })
  rex.action({
    name = 'smart_splits_resize',
    title = 'Smart Splits: Resize Pane',
    args = {
      type = 'object',
      required = { 'direction' },
      properties = {
        direction = { type = 'string', enum = { 'left', 'right', 'up', 'down' } },
        key = { type = 'string' },
        amount = { type = 'integer', minimum = 1 },
      },
    },
    run = function(ctx, args)
      if forward_if_vim(ctx, args) then
        return
      end
      rex.client.queue('pane.resize', { direction = args.direction, amount = args.amount or opts.resize_amount or 3 })
    end,
  })
end

return M
