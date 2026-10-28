# smart-splits-backend-rex

[smart-splits.nvim](https://github.com/smart-splits-nvim/smart-splits.nvim) v3 backend for
[Rex](https://www.superlogical.com/rex/docs/installation), the multiplexer for all work.

With this backend, smart-splits moves between Neovim windows and Rex panes as if they were one
grid, and resizes Rex panes when the Neovim window is at an edge.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'smart-splits-nvim/smart-splits.nvim',
  version = '^3.0.0',
  dependencies = {
    {
      'rawnly/smart-splits-backend-rex',
      opts = {
        -- bin = 'rex',     -- name or path of the rex executable
        -- timeout = 2000,  -- ms to wait for a rex command
      },
    },
  },
  opts = {
    mux = {
      backend = 'smart-splits-backend-rex',
    },
  },
  keys = function()
    local ss = require('smart-splits')
    return {
      { '<C-h>', ss.move_cursor_left },
      { '<C-j>', ss.move_cursor_down },
      { '<C-k>', ss.move_cursor_up },
      { '<C-l>', ss.move_cursor_right },
      { '<A-h>', ss.resize_left },
      { '<A-j>', ss.resize_down },
      { '<A-k>', ss.resize_up },
      { '<A-l>', ss.resize_right },
    }
  end,
}
```

Run `:checkhealth smart-splits` to verify the backend can reach the Rex server.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `true` | Set to `false` to never detect the backend |
| `bin` | `'rex'` | Name or path of the `rex` executable |
| `timeout` | `2000` | Milliseconds to wait for a `rex` command |

## Rex key bindings

The optional Rex-side module in `rex/lua/smart-splits-rex/init.lua` registers actions for focusing and resizing panes. It does **not** register any key bindings; choose your own. The Neovim plugin installation above is still required.

### With Rex Plugin Manager

After installing [Rex Plugin Manager](https://github.com/rawnly/rpm) on the Rex server, add this to your Rex config:

```lua
local rpm = dofile(os.getenv('HOME') .. '/.local/share/rex/rpm/rex_plugin_manager.lua')

rpm.setup({
  plugins = {
    {
      'rawnly/smart-splits-backend-rex',
      main = 'smart-splits-rex',
      ---@type SmartSplitsRexOptions
      opts = { resize_amount = 3 },
    },
  },
})
```

The repository must contain the Rex module on the Git ref being installed; if it has not been published yet, use a local checkout as described below. RPM does not install plugins during configuration loads or checks. Install explicitly, then reload:

```sh
rex config check
rex config reload
rex do rpm_install plugin=rawnly/smart-splits-backend-rex
rex config reload
```

RPM records the installed commit in its lockfile. Use `rex do rpm_update plugin=rawnly/smart-splits-backend-rex` to update it, or `rex do rpm_restore plugin=rawnly/smart-splits-backend-rex` to restore the locked commit; reload after either action. Restore refuses dirty checkouts.

For development, add `path = '/absolute/path/to/smart-splits-backend-rex'` to the plugin spec. The path must be on the Rex server; RPM loads it but does not install, update, or lock it. Add this checkout to your Lua Language Server workspace library for the `SmartSplitsRexOptions` annotation to provide completion.

Without a manager, call `dofile('/absolute/path/to/smart-splits-backend-rex/rex/lua/smart-splits-rex/init.lua').setup({})` in Rex's config.

### Bind the actions

`smart_splits_focus` and `smart_splits_resize` take a `direction` (`left`, `right`, `up`, or `down`) and an optional `key`. When Neovim is foreground, the action forwards `key` to it; supply the key matching your binding. Without a key, the action reports an error rather than swallowing a Neovim input. In other panes, focus moves to the neighboring pane and resize uses the optional `amount`, the `resize_amount` setup option, or 3, in that order. The resize and key-forwarding actions use the Rex client, so an app client must be available.

For example, to opt into Ctrl+h/j/k/l navigation and Alt+h/j/k/l resizing, add this **separately** to your Rex config:

```lua
for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
  rex.bind('ctrl+' .. key, 'smart_splits_focus', { direction = direction, key = 'ctrl+' .. key })
  rex.bind('alt+' .. key, 'smart_splits_resize', { direction = direction, key = 'alt+' .. key })
end
```

These bindings intercept the selected keys in all panes; only choose keys you want to reserve. Reload the config after adding them.

### Without the Rex module

The following manual configuration is an alternative to the Rex module above. Don't register both sets of bindings.

Rex key bindings run before the terminal sees the key, so binding `ctrl+h/j/k/l` straight to
`pane.focus.*` in Rex means Neovim never receives them. Bind them to a function instead, one that
returns `false` when Neovim is the foreground process so the key falls through to it. Neovim then
moves between its own windows and hands off to Rex through this backend at the edge. In any other
pane the keys move between Rex panes.

In your Rex `init.lua`:

```lua
local function is_vim(ctx)
  local proc = rex.block.call('com.superlogical.terminal', 'process', { block_id = ctx.block_id })
  local fg = proc and proc.foreground
  if not fg then
    return false
  end
  -- `name` is not always the executable's name, so check `argv0` too
  for _, s in ipairs({ fg.name or '', (fg.argv0 or ''):match('[^/]*$') }) do
    if s:match('^n?vim') then
      return true
    end
  end
  return false
end

for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
  rex.bind('ctrl+' .. key, function(ctx)
    if is_vim(ctx) then
      return false
    end
    rex.session.focus_direction({ direction = direction })
    return true
  end)
end
```

Run `rex config reload` to apply it.

### Resizing

`alt+h/j/k/l` need no Rex binding for Neovim: Rex passes unbound keys through, so smart-splits
receives them and resizes Rex panes through this backend when the Neovim window fills the axis.

On macOS, Option must be sent as Alt, otherwise Option+h types `˙` and `<A-h>` never fires in
Neovim. Check with `:lua print(vim.fn.getcharstr())` and press Option+h; it should print `<M-h>`.

To also resize Rex panes from panes that aren't running Neovim, bind the keys to an action.
`rex.client.queue` only works inside actions, not in functions bound with `rex.bind`, so the
action forwards the key to Neovim itself instead of falling through:

```lua
rex.action({
  name = 'smart_splits_resize',
  title = 'Smart Splits: Resize Pane',
  run = function(ctx, args)
    if is_vim(ctx) then
      rex.client.queue('pane.send_key', { key = args.key })
    else
      rex.client.queue('pane.resize', { direction = args.direction, amount = 3 })
    end
  end,
})

for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
  rex.bind('alt+' .. key, 'smart_splits_resize', { key = 'alt+' .. key, direction = direction })
end
```

Binding them in Rex means shells and other programs no longer receive `alt+h/j/k/l`.

## How it works

The backend is a thin wrapper around the [`rex` CLI](https://www.superlogical.com/rex/docs/automate/cli).
Every terminal Rex opens has `rex` on its `PATH` and sets `REX_SESSION` and `REX_BLOCK`, so the CLI
already acts on the pane Neovim is running in. Nothing needs to be defined in your Rex `init.lua`
besides the key bindings above.

| smart-splits | Rex |
| --- | --- |
| `detect()` | `REX_SESSION`/`REX_BLOCK` are set and `rex` is executable |
| `move(direction)` | `rex do -e <script>`, which calls `rex.session.focus_direction` |
| `move(direction, { at_edge = 'wrap' })` | the same script with `wrap = true` |
| `move(direction, { at_edge = 'split' })` | `rex split --split=<right\|left\|above\|below>` when there is no neighbor |
| `resize(direction, { amount })` | `rex do pane.resize direction=<direction> amount=<amount>` |

Notes:

- `rex focus` exits 0 even at the edge of the layout, so moving runs a small Lua script through
  `rex do` instead. It compares the session's structural revision before and after focusing, which
  changes only when focus moved, and returns `false` at the edge so smart-splits core can handle it.
- Resizing runs the app's `pane.resize` action, so the Rex app must be running with Remote Control
  turned on in its settings.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests stub Rex APIs and the `rex` CLI, so they run without Rex installed. Run `luajit tests/rex/test.lua` for the Rex-side module tests.

## License

MIT
