# cmdline.nvim

基于 Neovim 0.12 原生 UI2 和 `vim.ui_attach()` 的轻量命令行界面。它将 `:`、`input()` 等命令行显示在浮动窗口中，使用独立窗口显示原生补全菜单，并将消息交给 `notify.nvim`。

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
    top = { position = "top", title = "过滤", icon = "!" },
    middle = { position = "middle", title = "命令", icon = ">" },
    lua = { position = "middle", title = "Lua", icon = "" },
    bottom = { position = "bottom", title = "搜索", icon = "/" },
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

`setup()` 会将用户配置与默认值进行深度合并。各配置项如下：

- `enabled`：设为 `false` 时，不接管原生命令行和补全菜单。
- `width`：命令行浮窗的默认宽度。`value` 可以是数字、百分比字符串（例如 `"60%"`）或数字字符串；`min` 和 `max` 会按屏幕列数限制最终宽度。预设中的 `width` 会覆盖全局值。
- `border`：默认浮窗边框，支持 `nvim_open_win()` 支持的所有边框格式，例如 `"rounded"`、`"single"`、`"none"` 或自定义边框表。预设中的 `border` 优先级更高。
- `popupmenu`：设为 `false` 时，禁用本插件绘制的备用原生补全窗口。Blink 和 nvim-cmp 仍然使用自己的补全窗口，不会受到重复绘制影响。
- `notify_search`：设为 `false` 时，不再通过 `vim.notify` 显示搜索计数、搜索失败和搜索警告。
- `views`：将识别出的命令行场景映射到预设名称。内置场景有 `cmdline`、`search`、`input`、`lua`、`filter`、`expression`、`substitute` 和 `debug`。没有映射时使用 `middle`；预设不存在时也回退到默认的 `middle` 预设。场景识别包括 `:lua`、`:lua =`、`:=`、`/`、`?`、`input()`、替换/过滤命令和调试命令。
- `prefixes`：按场景设置图标，例如 `{ search = { icon = "" } }`。图标后会自动添加一个空格。预设中的 `icon` 优先于场景图标；设为空字符串即可移除图标。
- `presets`：定义可复用的布局。每个预设支持以下字段：
  - `position`：`"top"`、`"middle"`、`"bottom"`、`"mini"` 或 `"custom"`。`mini` 使用原生命令行所在的全宽行；`custom` 使用 `x` 和 `y` 定位。
  - `x`、`y`：`custom` 布局使用的偏移量，可以是数字、百分比（例如 `"10%"`）或数字字符串。
  - `width`：预设级宽度表，字段与全局 `width` 的 `value`、`min`、`max` 相同。
  - `border`：预设级边框覆盖值。
  - `title`：显示在浮窗上边框中央的标题。
  - `icon`：显示在输入内容前的图标，图标后自动添加一个空格。

旧版顶层 `position = { x = ..., y = ... }` 仍然兼容：当没有显式配置 `middle` 预设时，它会应用到 `middle`。新配置建议使用命名的 `custom` 预设：

```lua
presets = {
  command = {
    position = "custom",
    x = "50%",
    y = "30%",
    width = { value = "70%", min = 50, max = 120 },
    title = "命令",
  },
},
views = { cmdline = "command" }
```

预设标题会居中显示在浮窗上边框。`views` 决定使用哪个预设，`prefixes` 决定场景图标；预设中的 `icon` 和其他字段优先于全局默认值。

包括搜索在内的命令行都由插件渲染。普通命令输出和 Lua 输出通过 `vim.notify` 显示；错误和警告保留对应级别，搜索消息使用独立的 `Search` 标题。`:messages` 和 `g<` 会打开可滚动的 `Messages` 浮动窗口，显示完整消息历史。

## 要求和限制

- Neovim 0.12 或更新版本。
- UI2 仍是实验性功能，事件细节可能随 Neovim 版本变化。
- 插件接管 UI2 的 `msg_show` 和消息历史事件，将输出路由到 `notify.nvim`。
- 通知历史和 LSP progress 仍由 `notify.nvim` 负责，插件不会替换这两个界面。
- 补全提供者仍负责补全项目内容。如果已加载 `blink.cmp` 或 `nvim-cmp`，命令行菜单由补全插件负责，避免本插件再次绘制原生 popup；`cmdline.nvim` 仍提供补全插件所需的浮动命令行位置。

运行 `make check` 可执行格式检查、静态检查和 headless smoke test。
