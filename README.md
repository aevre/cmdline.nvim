# cmdline.nvim

A small Neovim 0.12+ command-line UI built on the native UI2 and `vim.ui_attach()`. It renders `:`, `input()`, and other command lines in a floating window, shows the native completion popup in a companion window, and forwards search-related messages to `vim.notify`.

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
  position = { x = "50%", y = "50%" },
  width = { value = "60%", min = 40, max = 100 },
  border = "rounded",
  popupmenu = true,
  notify_search = true,
})
```

Command lines, including search command lines, are rendered by the plugin. Search counts, failed searches, and search warnings are sent to `vim.notify`; all other messages remain owned by Neovim UI2.

## Requirements and limits

- Neovim 0.12 or newer.
- UI2 is experimental, so event details may change with Neovim.
- This plugin intentionally does not replace `msg_show`, notification history, or LSP progress.
- Completion providers remain responsible for their item data. If `blink.cmp` or `nvim-cmp` is loaded, its command-line menu owns the completion window and this plugin does not draw a second native popup; `cmdline.nvim` still supplies the floating command-line position used by the provider.

Run `make check` for formatting, linting, and the headless smoke test.
