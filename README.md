# cmdline.nvim

A small Neovim 0.12+ command-line UI built on the native UI2 and `vim.ui_attach()`. It renders `:`, `input()`, and other command lines in a floating window, shows the native completion popup in a companion window, and routes messages through `notify.nvim`.

[简体中文](README.zh-CN.md)

## Installation

The canonical repository is hosted on Codeberg: <https://codeberg.org/aevre/cmdline.nvim>.

```lua
{
  "https://codeberg.org/aevre/cmdline.nvim",
  opts = {},
}
```

## Configuration

```lua
require("cmdline").setup({
  enabled = true,
  views = {
    cmdline = "middle",
    search = "bottom",
    input = "middle",
    lua = "lua",
    filter = "top",
    expression = "middle",
    substitute = "top",
  },
  presets = {
    top = { position = "top", title = "Filter", icon = "!" },
    middle = { position = "middle", title = "Command", icon = ">" },
    lua = { position = "middle", title = "Lua", icon = "" },
    bottom = { position = "bottom", title = "Search", icon = "/" },
    mini = { position = "mini", border = "none" },
  },
  prefixes = {
    search = { icon = "" },
  },
  width = { value = "60%", min = 40, max = 100 },
  border = "rounded",
  popupmenu = true,
  notify_search = true,
})
```

`setup()` deep-merges the supplied options with the defaults. The options are:

- `enabled`: set to `false` to leave the native command line and popup menu untouched.
- `width`: the default width of command-line floats. `value` accepts a number, a percentage string such as `"60%"`, or a numeric string. `min` and `max` clamp the resulting width in screen columns. A preset's `width` overrides this global value.
- `border`: the default floating-window border. It accepts any border value supported by `nvim_open_win()`, including `"rounded"`, `"single"`, `"none"`, or a custom border table. A preset's `border` overrides it.
- `popupmenu`: set to `false` to disable the fallback native completion window drawn by this plugin. Blink and nvim-cmp still own their own completion windows and are not duplicated.
- `notify_search`: set to `false` to stop routing search counts, failed searches, and search warnings to `vim.notify`.
- `views`: maps a detected command-line context to a preset name. Built-in contexts are `cmdline`, `search`, `input`, `lua`, `filter`, `expression`, `substitute`, and `debug`. A missing mapping falls back to `middle`; a missing preset also falls back to the default `middle` preset. Context detection covers `:lua`, `:lua =`, `:=`, `/`, `?`, `input()`, substitute/filter commands, and debug commands.
- `prefixes`: sets an icon per context, for example `{ search = { icon = "" } }`. The icon is followed by one space. A preset's `icon` takes precedence over the context prefix. Set the icon to an empty string to remove it.
- `presets`: defines reusable layouts. Each preset supports the fields below:
  - `position`: `"top"`, `"middle"`, `"bottom"`, `"mini"`, or `"custom"`. `mini` uses the full-width native command-line row. `custom` uses `x` and `y`.
  - `x`, `y`: offsets used by `custom`. They may be numbers, percentages such as `"10%"`, or numeric strings.
  - `width`: a per-preset width table with the same `value`, `min`, and `max` fields as the global option.
  - `border`: a per-preset border override.
  - `title`: text centered in the top border.
  - `icon`: icon displayed before the input text, followed by one space.

The legacy top-level `position = { x = ..., y = ... }` option is still accepted and applies to the `middle` preset when that preset is not explicitly configured. New configurations should use a named custom preset instead:

```lua
presets = {
  command = {
    position = "custom",
    x = "50%",
    y = "30%",
    width = { value = "70%", min = 50, max = 120 },
    title = "Command",
  },
},
views = { cmdline = "command" }
```

Preset titles are centered in the float's top border. `views` controls which preset is selected; `prefixes` controls context icons; a preset's `icon` and other fields take precedence over global defaults.

Command lines, including search command lines, are rendered by the plugin. Ordinary command output and Lua output are sent to `vim.notify`; errors and warnings retain their log levels, and search messages use a dedicated `Search` title. `:messages` and `g<` open a scrollable `Messages` floating window containing the complete history.

## Requirements and limits

- Neovim 0.12 or newer.
- UI2 is experimental, so event details may change with Neovim.
- The plugin owns UI2 `msg_show` and message-history events so output can be routed to `notify.nvim`.
- Notification history and LSP progress remain owned by `notify.nvim`; the plugin does not replace either surface.
- Completion providers remain responsible for their item data. If `blink.cmp` or `nvim-cmp` is loaded, its command-line menu owns the completion window and this plugin does not draw a second native popup; `cmdline.nvim` still supplies the floating command-line position used by the provider.

Run `make check` for formatting, linting, and the headless smoke test.
