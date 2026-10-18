# cmdline.nvim

基于 Neovim 0.12 原生 UI2 和 `vim.ui_attach()` 的轻量命令行界面。它将 `:`、`input()` 等命令行显示在浮动窗口中，使用独立窗口显示原生补全菜单，并将搜索相关消息交给 `vim.notify`。

[English](README.md)

## 安装

Canonical 仓库位于 Codeberg：<https://codeberg.org/aevre/cmdline.nvim>。

```lua
{
  "https://codeberg.org/aevre/cmdline.nvim",
  opts = {},
}
```

## 配置

```lua
require("cmdline").setup({
  position = { x = "50%", y = "50%" },
  width = { value = "60%", min = 40, max = 100 },
  border = "rounded",
  popupmenu = true,
  notify_search = true,
})
```

包括搜索在内的命令行都由插件渲染。搜索计数、搜索失败和搜索警告会通过 `vim.notify` 显示；其他消息继续由 Neovim UI2 负责。

## 要求和限制

- Neovim 0.12 或更新版本。
- UI2 仍是实验性功能，事件细节可能随 Neovim 版本变化。
- 本插件不会接管 `msg_show`、通知历史或 LSP progress。
- 补全提供者仍负责补全项目内容。如果已加载 `blink.cmp` 或 `nvim-cmp`，命令行菜单由补全插件负责，避免本插件再次绘制原生 popup；`cmdline.nvim` 仍提供补全插件所需的浮动命令行位置。

运行 `make check` 可执行格式检查、静态检查和 headless smoke test。
