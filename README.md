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
      'rawnly/smart-splits-nvim--backend-rex',
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

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests stub the `rex` CLI, so they run without Rex installed.

## License

MIT
