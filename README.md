# smart-splits-backend-rex

[smart-splits.nvim](https://github.com/smart-splits-nvim/smart-splits.nvim) v3 backend for
[Rex](https://www.superlogical.com/rex/docs/installation), the multiplexer for all work.

With this backend, smart-splits moves between Neovim windows and Rex panes as if they were one
grid, and resizes Rex panes when the Neovim window is at an edge.

## How it works

The backend is a thin wrapper around the [`rex` CLI](https://www.superlogical.com/rex/docs/automate/cli).
Every terminal Rex opens has `rex` on its `PATH` and sets `REX_SESSION` and `REX_BLOCK`, so the CLI
already acts on the pane Neovim is running in.

| smart-splits | Rex |
| --- | --- |
| `detect()` | `REX_SESSION`/`REX_BLOCK` are set and `rex` is executable |
| `move(direction)` | `rex focus <direction>` |
| `move(direction, { at_edge = 'split' })` | `rex split --split=<right\|left\|above\|below>` when there is no neighbor |
| `resize(direction, { amount })` | `rex do pane.resize direction=<direction> amount=<amount>` |

Notes:

- `at_edge = 'wrap'` is not supported by Rex, so the backend returns `false` and smart-splits core
  handles the edge.
- Resizing runs the app's `pane.resize` action, so the Rex app must be running with Remote Control
  turned on in its settings.
- Moving relies on `rex focus` exiting non-zero when there is no pane in that direction.

## Installation

```lua
{
  'smart-splits-nvim/smart-splits.nvim',
  branch = 'v3',
  opts = {
    mux = {
      backend = 'smart-splits-backend-rex',
    },
  },
  dependencies = {
    {
      'rawnly/smart-splits-nvim--backend-rex',
      opts = {
        -- bin = 'rex',     -- name or path of the rex executable
        -- timeout = 2000,  -- ms to wait for a rex command
      },
    },
  },
}
```

Run `:checkhealth smart-splits` to verify the backend can reach the Rex server.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests stub the `rex` CLI, so they run without Rex installed.

## License

MIT
