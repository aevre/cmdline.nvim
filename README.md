# cmdline.nvim

A small Neovim 0.12+ command-line UI built on native UI2 and `vim.ui_attach()`.

`cmdline.nvim` renders command-line input in a floating window, displays the popupmenu when no external completion backend owns it, and routes ordinary messages through `vim.notify()`.

[简体中文](README.zh-CN.md)

## Features

- Floating rendering for `:`, `/`, `?`, `input()`, expression input, debug input, and command-specific prompts.
- Separate layouts for command lines, searches, file prompts, rename prompts, and user-defined contexts.
- Native UI2 popupmenu support with Blink and nvim-cmp coexistence.
- Message routing through `vim.notify()`, with a built-in fallback when no notification plugin is installed.
- Scrollable `:messages` and `g<` history window.
- Configurable borders, titles, icons, positions, and highlight groups.
- Extension points for classifying new command lines and prompts without changing plugin code.

## Requirements

- Neovim 0.12 or newer.
- A UI that supports floating windows. UI2 is experimental, so event details may change with Neovim.

## Installation

The canonical repository is hosted on Codeberg: <https://codeberg.org/aevre/cmdline.nvim>.

```lua
{
  "https://codeberg.org/aevre/cmdline.nvim",
  opts = {},
}
```

## Configuration

The configuration is grouped into three independent sections: `cmdline`, `messages`, and `popupmenu`.

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
        cmdline_popup = { position = "top", title = "Command", icon = "󰘳" },
        mini = { position = "mini", border = "none" },
        lua = { position = "top", title = "Lua", icon = "" },
        filter = { position = "top", title = "Filter", icon = "󰈲" },
        help = { position = "top", title = "Help", icon = "󰋖" },
        input = { position = "top", title = "Input", icon = "󰌌" },
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

- `enabled`: enable command-line rendering.
- `view`: fallback preset used when no format selects another view.
- `extensions`: extensions that classify command lines before the built-in extensions run.
- `opts.width`: a number, percentage string, or numeric string. `min` and `max` clamp the resulting width.
- `opts.border`: any border accepted by `nvim_open_win()`.
- `opts.highlights`: links for the normal area, border, title, icon, and popupmenu.
- `opts.icon_hl_group`: default highlight group for icons.
- `opts.presets`: reusable layout definitions.
- `format`: maps a context or command pattern to a preset and presentation values.

The command-line window uses a local `virtualedit=onemore` setting so the cursor can appear after the rendered icon and spacing without changing your normal editing windows. Cursor shape remains controlled by Neovim's `guicursor` setting; use the `c:` mode entry for command-line input, for example:

```lua
vim.opt.guicursor = {
  "n-v-sm:block-Cursor",
  "i-ci-ve:ver25-Cursor",
  "c:ver25-Cursor",
  "r-cr-o:hor20-Cursor",
}
```

### `messages`

- `enabled`: enable UI2 message handling.
- `view_search`: set to `false` to disable search-result routing.

Ordinary messages are sent through `vim.notify()` with error and warning levels preserved. UI2 updates received before the scheduled flush are merged by message ID, `replace_last`, and `append`, so a file write sends only its final message. Notifications include a stable, namespaced `opts.id` for providers that support updates; providers that ignore it may show later updates as separate notifications. `:messages` and `g<` use the built-in scrollable history window. These destinations are fixed; there are no `view`, `view_error`, `view_warn`, or `view_history` options.

Errors and warnings retain their log levels. Search counts are virtual text, not notifications. Configure their format, placement, and highlights with `messages.search_count`:

```lua
messages = {
  search_count = {
    format = "[{current}/{total}]",
    position = "word", -- or "line_end"
    hl_group = "CmdlineSearchCount",
    current_hl_group = "CmdlineSearchCountCurrent",
  },
}
```

The default count uses Neovim's compact `[current/total]` style, as in Noice. The configured format is displayed as written, with no extra prefix. The default places it three spaces to the right of the match, or to its left when it would cross the editor window's right edge. Built-in highlight groups use foreground colors and bold only. Cancelling a search with Esc or Ctrl-C clears its count; `:nohlsearch` also clears it when `hlsearch` is enabled. The plugin does not bind Esc. External notification providers retain their own history.

### `popupmenu`

- `enabled`: enable popupmenu handling.
- `backend`: use `"nui"` for the built-in fallback window or `"cmp"` when an external completion backend should own the menu.
- `border`: popup window border; defaults to `"rounded"` and accepts the standard Neovim floating-window border formats.
- `kind_icons`: defaults to built-in completion-kind icons, including Neovim's single-letter kinds. Items without a mapped kind use the built-in generic icon. Provide a complete replacement map to customize it, use an empty table to hide icons, or set it to `false` to disable them.

When Blink or nvim-cmp is loaded in command-line mode, `cmdline.nvim` does not draw a duplicate popupmenu. The completion plugin owns its menu while `cmdline.nvim` supplies the floating command-line position.

## Extensions

Extensions classify the current UI2 command-line event. The returned name is used to look up `cmdline.format[name]` and, through its `view` field, `cmdline.opts.presets[name]`.

The resolution order is:

1. User extensions.
2. Built-in extensions.
3. The generic `cmdline` context.

Add extensions in the plugin's normal `setup()` options. For example, this `lazy.nvim` spec recognizes `:Git ...` and assigns it a dedicated layout:

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

Use `state.firstc` and `state.lines` to classify command lines, or `state.prompt` to classify `input()` prompts. The returned name must match both a `format` entry and a preset referenced by that format's `view`.

### Function extensions

A function receives a state table:

```lua
{
  firstc = ":",       -- command-line prefix, such as :, /, or ?
  prompt = "",        -- input() prompt, when present
  chunks = {},         -- original UI2 chunks
  lines = {},          -- plain text lines made from chunks
  pos = 0,             -- cursor position from UI2
  indent = 0,
  level = 0,
}
```

Return a context name or `{ name = "context" }`:

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

Add the matching format and preset:

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

### Declarative prompt extensions

Prompt extensions are useful for file, buffer, rename, and other `input()` questions. `prompt` accepts one Lua pattern or a list of Lua patterns. Matching is case-insensitive.

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

A prompt that does not match a custom extension uses the built-in `input` context. The built-in `rename` context is itself a prompt extension matching `rename` and `new name`.

### Built-in contexts

- `cmdline`: fallback for ordinary `:` commands.
- `search`: `/` and `?`; the default formats use the bottom `mini` layout.
- `input`: an unmatched `input()` prompt.
- `rename`: prompts containing `rename` or `new name`.
- `expression`: `=` expression input.
- `debug`: `>` debug input.
- `lua`: `:lua`, `:lua =`, and `:=`.
- `filter`: `:!` and `:filter` commands.
- `help`: `:h`, `:he`, `:hel`, and `:help` followed by a space.
- `substitute`: `:s/` and `:substitute` commands.

The Lua and help views conceal their command prefixes and compensate the cursor position. A format can be disabled by setting it to `false`.

## Layout and highlighting

`position` accepts `"top"`, `"middle"`, `"bottom"`, `"mini"`, or `"custom"`.

- `top`, `middle`, and `bottom` use a centered floating window with the corresponding vertical placement.
- `mini` uses a full-width, one-line window at the bottom of the editor. It temporarily sets `cmdheight` to `1` while active and restores it to `0` when hidden.
- `custom` uses the preset's `x` and `y` values.

Most built-in contexts use `top`; searches use `mini`. Preset titles are centered in the top border and padded with one space on each side. A preset icon overrides the format icon.

The plugin defines these internal highlight links:

- `CmdlineNormal`
- `CmdlineBorder`
- `CmdlineTitle`
- `CmdlineIcon`
- `CmdlinePum`

Configure the links with `cmdline.opts.highlights`. Icon priority is format `icon_hl_group`, then preset `icon_hl_group`, then `cmdline.opts.icon_hl_group`.

## Messages and history

Ordinary UI2 output, Lua output, shell output, errors, and warnings are routed through public `vim.notify()` when a custom provider is installed. With Neovim's default provider, messages appear for four seconds in a borderless, full-width window at the bottom left, using Neovim's `MsgArea` highlight and preserving message highlights, avoiding a loop through `nvim_echo()`. The latest message replaces the previous one; long messages are capped at half the screen height. Messages recorded by Neovim remain available in `:messages`.

Search-count virtual text is anchored beside the selected match in the current buffer. The routing guard handles providers that synchronously echo a notification back through UI2. A provider that writes it back asynchronously with `nvim_echo()` cannot be reliably distinguished from a new message and may cause duplicate routing; providers that render their own notifications without writing back are unaffected.

`:messages` and `g<` open a dedicated scrollable `Messages` floating window. Messages appear newest first, without blank separator lines; multiline messages and `echon` continuations retain their content. Press `q` or `<Esc>` to close it and restore the previous window. The public API is:

```lua
require("cmdline").close_history()
```

Call `require("cmdline").disable()` to detach UI2 and restore resources and `cmdheight` captured before setup. Passing both `cmdline.enabled = false` and `messages.enabled = false` to `setup()` does the same.

Interactive confirmation prompts and return prompts remain native and are not routed through notifications.

## UI2 ownership

`cmdline.nvim` enables its required UI2 surfaces internally with `vim.ui_attach()`:

```lua
ext_cmdline = true
ext_popupmenu = true
ext_messages = true
set_cmdheight = false
```

Do not also call `require("vim._core.ui2").enable({})`; attaching both implementations can duplicate or compete for command-line, popupmenu, and message events.

If the plugin is disabled, Neovim's default UI2 implementation may be enabled separately:

```lua
require("vim._core.ui2").enable({ enable = true })
```

## Development

Run the complete local check from the repository root:

```sh
make check
```

This runs Stylua formatting checks (including tests), Selene, and headless smoke and lifecycle tests. The lifecycle test captures UI dispatch to check repeated setup, scheduled rendering, popup placement, and resource cleanup; it does not replace terminal testing.

The public entry is `require("cmdline")`, exposing `setup(opts)`, `disable()`, and `close_history()`. Other modules are internal:

- `init.lua`: configuration assembly, UI attachment, event dispatch, and autocmd registration.
- `commandline.lua`: command-line state, layouts, cursor rendering, resize handling, and cmp coordinate integration.
- `popupmenu.lua`: native completion menu state and rendering; obtains its anchor from `commandline.lua`.
- `messages.lua`: message routing, native notification fallback, history windows, and timer cleanup.
- `ui.lua`: shared window cleanup, buffer writes, and chunk-to-text conversion.
- `config.lua`: configuration types, defaults, and merging.
- `extensions.lua`: command and prompt context resolution.
- `highlights.lua`: internal highlight links.

Feature modules own their resources and receive configuration from `setup()`. They depend on `ui.lua`; command-line rendering also uses `extensions.lua`. No feature module requires the public entry. Requiring the plugin does not attach UI surfaces or create windows; repeated `setup()` reuses the attachment and replaces the autocmd group.
