# cmdline.nvim

基于 Neovim 0.12+ 原生 UI2 和 `vim.ui_attach()` 的轻量命令行界面。

`cmdline.nvim` 将命令行输入渲染到浮动窗口中；没有外部补全后端接管时，显示 popupmenu；普通消息则通过 `vim.notify()` 路由。

[English](README.md)

## 功能

- 为 `:`、`/`、`?`、`input()`、表达式、debug 和命令专用提示提供浮动渲染。
- 为命令行、搜索、文件提示、重命名提示和用户自定义 context 提供独立布局。
- 支持原生 UI2 popupmenu，并与 Blink、nvim-cmp 共存。
- 通过 `vim.notify()` 路由消息，未安装通知插件时使用内置浮窗。
- 提供可滚动的 `:messages` 和 `g<` 历史窗口。
- 可配置边框、标题、图标、位置和高亮组。
- 支持扩展命令行和 prompt 分类，无需修改插件代码。

## 要求

- Neovim 0.12 或更新版本。
- 支持浮动窗口的 UI。UI2 仍是实验性功能，事件细节可能随 Neovim 版本变化。

## 安装

Canonical 仓库位于 Codeberg：<https://codeberg.org/aevre/cmdline.nvim>。

```lua
{
  "https://codeberg.org/aevre/cmdline.nvim",
  opts = {},
}
```

## 配置

配置分为三个相互独立的部分：`cmdline`、`messages` 和 `popupmenu`。

```lua
require("cmdline").setup({
  cmdline = {
    enabled = true,
    view = "cmdline_popup",
    extensions = {},
    opts = {
      width = { value = "60%", min = 40, max = 100 },
      border = "rounded",
      highlights = {
        normal = "FzfLuaNormal",
        border = "FzfLuaBorder",
        title = "FzfLuaTitle",
        icon = "Special",
        pum = "Pmenu",
      },
      icon_hl_group = "CmdlineIcon",
      presets = {
        cmdline_popup = { position = "top", title = "命令", icon = "󰘳" },
        mini = { position = "mini", border = "none" },
        lua = { position = "top", title = "Lua", icon = "" },
        filter = { position = "top", title = "过滤", icon = "󰈲" },
        help = { position = "top", title = "帮助", icon = "󰋖" },
        input = { position = "top", title = "输入", icon = "󰌌" },
        rename = { position = "top", title = "Rename", icon = "󰏫" },
      },
    },
    format = {
      cmdline = { pattern = "^:", icon = "󰘳", view = "cmdline_popup" },
      search_down = { kind = "search", pattern = "^/", icon = "", view = "mini" },
      search_up = { kind = "search", pattern = "^%?", icon = "", view = "mini" },
      filter = { pattern = "^:%s*!", icon = "󰈲", view = "filter" },
      help = { pattern = "^:%s*he?l?p?%s+", icon = "󰋖", view = "help" },
      lua = {
        pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" },
        icon = "",
        view = "lua",
      },
      input = { view = "input", icon = "󰌌" },
      rename = { view = "rename", icon = "󰏫" },
    },
  },
  messages = {
    enabled = true,
    view_search = "notify",
  },
  popupmenu = {
    enabled = true,
    backend = "nui",
  },
})
```

### `cmdline`

- `enabled`：启用命令行渲染。
- `view`：没有格式选择其他视图时使用的默认预设。
- `extensions`：在内置扩展之前分类命令行的扩展。
- `opts.width`：支持数字、百分比字符串或数字字符串；`min` 和 `max` 限制最终宽度。
- `opts.border`：支持 `nvim_open_win()` 接受的所有边框格式。
- `opts.highlights`：配置普通区域、边框、标题、图标和 popupmenu 的高亮链接。
- `opts.icon_hl_group`：图标的默认高亮组。
- `opts.presets`：可复用的布局定义。
- `format`：将 context 或命令模式映射到预设和显示属性。

命令行浮动窗口会在窗口局部使用 `virtualedit=onemore`，使光标可以显示在渲染图标和空格之后，同时不会改变普通编辑窗口的设置。光标形状仍由 Neovim 的 `guicursor` 控制；可以通过 `c:` 模式项配置命令行输入时的光标，例如：

```lua
vim.opt.guicursor = {
  "n-v-sm:block-Cursor",
  "i-ci-ve:ver25-Cursor",
  "c:ver25-Cursor",
  "r-cr-o:hor20-Cursor",
}
```

### `messages`

- `enabled`：启用 UI2 消息处理。
- `view_search`：设为 `false` 可关闭搜索结果路由。

普通消息通过 `vim.notify()` 发送，并保留错误和警告级别。在调度的 flush 执行前收到的 UI2 更新会按消息 ID、`replace_last` 和 `append` 合并，因此文件保存只转发最终消息。通知携带稳定且带命名空间的 `opts.id`，供支持更新的 provider 使用；忽略该字段的 provider 可能将后续更新显示为独立通知。`:messages` 和 `g<` 固定使用内置可滚动历史窗口。目标目前固定，没有 `view`、`view_error`、`view_warn` 或 `view_history` 配置项。

错误和警告保留对应日志级别。搜索数量以虚拟文字显示，不作为通知发送。可通过 `messages.search_count` 配置格式、位置和高亮：

```lua
messages = {
  search_count = {
    format = "[{current}/{total}]",
    position = "word", -- 或 "line_end"
    hl_group = "CmdlineSearchCount",
    current_hl_group = "CmdlineSearchCountCurrent",
  },
}
```

默认使用与 Noice 相同的紧凑格式 `[当前/总数]`，严格按配置格式显示，不额外添加前缀。默认在匹配词右侧间隔 3 格；只有超过编辑器窗口右边界时才改放在词左侧。内置高亮组只设置前景色和粗体。光标离开当前匹配或按 Esc / Ctrl-C 取消搜索后，计数会隐藏；启用 `hlsearch` 时，执行 `:nohlsearch` 也会清除计数。插件不绑定 Esc。外部通知 provider 继续管理自己的通知历史。

### `popupmenu`

- `enabled`：启用 popupmenu 处理。
- `backend`：使用 `"nui"` 启用内置备用窗口，使用 `"cmp"` 时交给外部补全后端。
- `border`：补全面板边框，默认 `"rounded"`，支持 Neovim 标准浮窗边框格式。
- `kind_icons`：默认使用内置补全类型图标，包含 Neovim 的单字母类型；没有映射的类型使用通用图标。自定义时需提供完整映射表；空表隐藏图标，设为 `false` 可显式禁用。

当 Blink 或 nvim-cmp 在命令行模式中加载时，`cmdline.nvim` 不会绘制重复的 popupmenu。补全插件负责菜单，`cmdline.nvim` 提供浮动命令行位置。

## 扩展机制

扩展负责识别当前 UI2 命令行。扩展返回的名称会用于查找 `cmdline.format[name]`，并通过其中的 `view` 字段查找 `cmdline.opts.presets[name]`。

解析顺序如下：

1. 用户扩展。
2. 内置扩展。
3. 通用的 `cmdline` context。

在插件常规的 `setup()` 配置中添加扩展即可。下面的 `lazy.nvim` 插件 spec 会识别 `:Git ...`，并为它指定独立布局：

```lua
{
  "https://codeberg.org/aevre/cmdline.nvim",
  opts = {
    cmdline = {
      extensions = {
        function(state)
          if state.firstc == ":" and state.lines[1]:match("^Git%s") then
            return "git"
          end
        end,
      },
      opts = {
        presets = {
          git = { position = "top", title = "Git", icon = "󰊢" },
        },
      },
      format = {
        git = { view = "git", icon = "󰊢" },
      },
    },
  },
}
```

可以用 `state.firstc` 和 `state.lines` 分类命令行，或用 `state.prompt` 分类 `input()` 提示。返回的名称必须对应一个 `format` 项，且该项 `view` 指向已配置的 preset。

### 函数扩展

函数接收一个状态表：

```lua
{
  firstc = ":",       -- 命令行前缀，例如 :、/ 或 ?
  prompt = "",        -- input() prompt，没有时为空
  chunks = {},         -- 原始 UI2 chunks
  lines = {},          -- 从 chunks 转换得到的纯文本行
  pos = 0,             -- UI2 提供的光标位置
  indent = 0,
  level = 0,
}
```

返回 context 名称或 `{ name = "context" }`：

```lua
cmdline = {
  extensions = {
    function(state)
      if state.firstc == ":" and state.lines[1]:match("^Git%s") then
        return "git"
      end
    end,
  },
}
```

再添加对应的 format 和 preset：

```lua
cmdline = {
  opts = {
    presets = {
      git = { position = "top", title = "Git", icon = "󰊢" },
    },
  },
  format = {
    git = { view = "git", icon = "󰊢" },
  },
}
```

### 声明式 prompt 扩展

prompt 扩展适合文件、buffer、重命名和其他 `input()` 问题。`prompt` 可以是一个 Lua 模式，也可以是 Lua 模式列表。匹配不区分大小写。

```lua
cmdline = {
  extensions = {
    {
      name = "file",
      prompt = { "already%s+open", "filename" },
    },
  },
  opts = {
    presets = {
      file = { position = "top", title = "File", icon = "󰈔" },
    },
  },
  format = {
    file = { view = "file", icon = "󰈔" },
  },
}
```

没有匹配自定义扩展的 prompt 会使用内置 `input` context。内置的 `rename` context 本身也是一个 prompt 扩展，匹配 `rename` 和 `new name`。

### 内置 context

- `cmdline`：普通 `:` 命令的回退 context。
- `search`：`/` 和 `?`；默认格式使用底部的 `mini` 布局。
- `input`：没有被其他扩展匹配的 `input()` prompt。
- `rename`：包含 `rename` 或 `new name` 的 prompt。
- `expression`：以 `=` 开头的表达式输入。
- `debug`：以 `>` 开头的 debug 输入。
- `lua`：`:lua`、`:lua =` 和 `:=`。
- `filter`：`:!` 和 `:filter` 命令。
- `help`：后面带空格的 `:h`、`:he`、`:hel` 和 `:help`。
- `substitute`：`:s/` 和 `:substitute` 命令。

Lua 和 help 视图会隐藏命令前缀，并补偿光标位置。将某个 format 设为 `false` 可以禁用它。

## 布局和高亮

`position` 支持 `"top"`、`"middle"`、`"bottom"`、`"mini"` 和 `"custom"`。

- `top`、`middle` 和 `bottom` 使用居中的浮动窗口，并放置在对应的垂直位置。
- `mini` 使用编辑器底部全宽的单行窗口。激活时临时将 `cmdheight` 设为 `1`，隐藏后恢复为 `0`。
- `custom` 使用预设中的 `x` 和 `y`。

大多数内置 context 使用 `top`，搜索使用 `mini`。预设标题居中显示在浮窗上边框，并在两侧各保留一个空格。预设图标会覆盖格式图标。

插件定义以下内部高亮链接：

- `CmdlineNormal`
- `CmdlineBorder`
- `CmdlineTitle`
- `CmdlineIcon`
- `CmdlinePum`

使用 `cmdline.opts.highlights` 配置这些链接。图标高亮优先级为：格式的 `icon_hl_group`、预设的 `icon_hl_group`、`cmdline.opts.icon_hl_group`。

## 消息和历史

安装自定义通知 provider 时，普通 UI2 输出、Lua 输出、shell 输出、错误和警告通过公开的 `vim.notify()` 路由。使用 Neovim 默认 provider 时，消息在左下角的无边框、全宽临时窗口中显示四秒，使用 Neovim 的 `MsgArea` 高亮并保留消息自身的高亮，避免通过 `nvim_echo()` 形成回路。新消息替换上一条消息；长消息最多占半屏高度。Neovim 已记录的消息仍可通过 `:messages` 查看。

搜索数量以虚拟文字显示在当前缓冲区的选中结果旁。路由保护可处理同步通过 UI2 回写通知的 provider。若 provider 稍后通过 `nvim_echo()` 回写，插件无法可靠判断这是原通知的回声还是新消息，可能导致重复路由；只显示自身通知、不回写消息的 provider 不受此限制。

`:messages` 和 `g<` 会打开独立的可滚动 `Messages` 浮动窗口。消息按时间倒序显示，最新消息在顶部，消息之间不插入空行；多行内容和 `echon` 连续输出会保留。按 `q` 或 `<Esc>` 关闭，并恢复之前的窗口。公开 API 是：

```lua
require("cmdline").close_history()
```

调用 `require("cmdline").disable()` 会解除 UI2 挂载、清理资源，并恢复 setup 前保存的 `cmdheight`。在 `setup()` 中同时设置 `cmdline.enabled = false` 和 `messages.enabled = false` 也会执行相同清理。

交互式确认 prompt 和 return prompt 保持原生行为，不会被路由到通知。

## UI2 所有权

`cmdline.nvim` 会通过 `vim.ui_attach()` 在内部启用所需 UI2 surface：

```lua
ext_cmdline = true
ext_popupmenu = true
ext_messages = true
set_cmdheight = false
```

不要再调用 `require("vim._core.ui2").enable({})`；同时挂载两套实现会导致命令行、popupmenu 和消息事件重复处理或窗口竞争。

如果禁用本插件，可以单独启用 Neovim 默认 UI2 实现：

```lua
require("vim._core.ui2").enable({ enable = true })
```

## 开发

在仓库根目录运行完整检查：

```sh
make check
```

该命令会执行 Stylua 格式检查（包含测试文件）、Selene 静态检查及 headless smoke 和生命周期测试。生命周期测试捕获 UI 事件分发，验证重复 setup、延迟渲染、菜单定位和资源清理；它不能替代终端测试。

公共入口为 `require("cmdline")`，导出 `setup(opts)`、`disable()` 和 `close_history()`。其余模块属于内部实现：

- `init.lua`：配置装配、UI 挂载、事件分发和 autocmd 注册。
- `commandline.lua`：命令行状态、布局、光标渲染、尺寸调整及 cmp 坐标适配。
- `popupmenu.lua`：原生补全菜单状态和渲染；通过 `commandline.lua` 获取定位锚点。
- `messages.lua`：消息路由、原生通知回退、历史窗口和定时器清理。
- `ui.lua`：共享的窗口清理、buffer 写入和消息块文本转换。
- `config.lua`：配置类型、默认值和合并。
- `extensions.lua`：命令和 prompt 的 context 解析。
- `highlights.lua`：内部高亮链接。

功能模块管理各自的资源，由 `setup()` 传入配置；它们依赖 `ui.lua`，命令行渲染另依赖 `extensions.lua`。功能模块不反向 require 公共入口。require 插件不会挂载 UI 或创建窗口；重复 `setup()` 复用已有挂载并替换 autocmd group。
