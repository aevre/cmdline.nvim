---@alias cmdline.Position "top"|"middle"|"bottom"|"mini"|"custom" Preset vertical placement.
---@alias cmdline.PopupBackend "nui"|"cmp" Completion popup owner.
---@alias cmdline.Pattern string|string[] One Lua pattern or a list of patterns.
---@alias cmdline.Border string|string[]|table[] Border format accepted by `nvim_open_win()`.
---@alias cmdline.UIAttributes vim.api.keyset.highlight Highlight attributes on command-line chunks.
---@alias cmdline.CmdlineChunk [cmdline.UIAttributes, string, integer] Command-line UI2 content tuple.
---@alias cmdline.MessageChunk [integer, string, integer] Message UI2 content tuple.
---@alias cmdline.Chunk cmdline.CmdlineChunk|cmdline.MessageChunk Text chunk used by UI2 content.
---@alias cmdline.Content cmdline.Chunk[] Ordered UI2 text chunks.
---@alias cmdline.HistoryEntry [string, cmdline.Content, boolean] History kind, content, and append flag.

---@class cmdline.Width Width value and optional layout bounds.
---@field value? number|string Width in columns, as a percentage, or numeric string.
---@field min? integer Lower bound for the rendered width.
---@field max? integer Upper bound for the rendered width.

---@class cmdline.View Placement and appearance overrides for one named layout.
---@field position? cmdline.Position Vertical placement or full-width mini layout.
---@field x? number|string Horizontal offset used by the custom position.
---@field y? number|string Vertical offset used by the custom position.
---@field width? cmdline.Width Width override for this preset.
---@field border? cmdline.Border Floating-window border override.
---@field title? string Floating-window title.
---@field icon? string Prefix icon shown for this preset.
---@field icon_hl_group? string Highlight group used for this preset's icon.

---@class cmdline.Highlights Highlight links used by the command-line UI.
---@field normal? string Highlight linked to the command-line window body.
---@field border? string Highlight linked to floating-window borders.
---@field title? string Highlight linked to floating-window titles.
---@field icon? string Highlight linked to command-line icons.
---@field pum? string Highlight linked to the completion popup.

---@class cmdline.Format Context matching and presentation overrides.
---@field pattern? cmdline.Pattern Lua pattern(s) used to select this format.
---@field kind? string Context kind used by extension resolution.
---@field view? string Preset name selected for the matching context.
---@field icon? string Prefix icon displayed for the format.
---@field title? string Floating-window title override.
---@field icon_hl_group? string Highlight group used for the format icon.

---@class cmdline.ExtensionState State passed to user-provided context resolvers.
---@field firstc string Built-in command-line prefix such as `:`, `/`, or `?`.
---@field prompt string Prompt text supplied by `input()`.
---@field chunks cmdline.Content Original UI2 command-line content.
---@field lines string[] Plain-text command-line lines derived from `chunks`.
---@field pos integer Cursor byte position reported by UI2.
---@field indent integer Number of leading indentation spaces.
---@field level integer Nested command-line level reported by UI2.

---@alias cmdline.ExtensionResult string|{ name: string }|nil Context name or descriptor returned by an extension.
---@alias cmdline.ExtensionCallback fun(state: cmdline.ExtensionState): cmdline.ExtensionResult User context resolver.

---@class cmdline.PromptExtension Declarative resolver for prompts matched by Lua patterns.
---@field name string Context name returned when the prompt matches.
---@field prompt? cmdline.Pattern Lua pattern(s) matched against the prompt text.
---@field resolve? cmdline.ExtensionCallback Fallback resolver called when the prompt does not match.

---@alias cmdline.Extension cmdline.ExtensionCallback|cmdline.PromptExtension Callback or declarative prompt matcher.

---@class cmdline.CmdlineOptions Shared command-line layout and highlight defaults.
---@field width? cmdline.Width Default width and clamp values.
---@field border? cmdline.Border Default floating-window border.
---@field highlights? cmdline.Highlights Highlight links used by command-line windows.
---@field icon_hl_group? string Fallback highlight group for context icons.
---@field presets? table<string, cmdline.View> Named reusable layouts.

---@class cmdline.CmdlineConfig Command-line rendering and context configuration.
---@field enabled? boolean Whether command-line rendering is active.
---@field view? string Fallback preset name.
---@field extensions? cmdline.Extension[] Ordered user context resolvers.
---@field opts? cmdline.CmdlineOptions Shared layout and highlight options.
---@field format? table<string, cmdline.Format|false> Per-context formats; `false` disables one.

---@class cmdline.SearchCount Search-count text and placement.
---@field format? string Format string with `{current}` and `{total}` placeholders.
---@field position? "word"|"line_end" Place the count beside the match or at the line end.
---@field hl_group? string Foreground highlight group for separators and total count.
---@field current_hl_group? string Foreground highlight group for the current-match number.

---@class cmdline.SearchCountResolved Resolved search-count text settings.
---@field format string Format string with `{current}` and `{total}` placeholders.
---@field position "word"|"line_end" Placement beside the match or at line end.
---@field hl_group string Highlight group for separators and total count.
---@field current_hl_group string Highlight group for the current-match number.

---@class cmdline.MessagesConfig Message routing and history configuration.
---@field enabled? boolean Whether message routing and history are active.
---@field view_search? string|false Enable or disable search-result routing.
---@field search_count? cmdline.SearchCount Search-count formatting, placement, and highlight.

---@class cmdline.PopupItem Completion item in UI2 tuple or dictionary form.
---@field [1]? string Completion word in the UI2 tuple form.
---@field [2]? string Completion kind in the UI2 tuple form.
---@field [3]? string Completion menu text in the UI2 tuple form.
---@field [4]? string Completion info text in the UI2 tuple form.
---@field word? string Completion label used by dictionary-shaped providers.

---@class cmdline.PopupmenuConfig Configuration for the completion popup renderer.
---@field enabled? boolean Whether popupmenu rendering is active.
---@field backend? cmdline.PopupBackend Renderer that owns command-line completions.
---@field border? cmdline.Border Popup window border style.
---@field kind_icons? table<string, string>|false Icons keyed by completion kind, or `false` to disable icons.

---@class cmdline.Config User-facing grouped plugin configuration.
---@field cmdline? cmdline.CmdlineConfig Command-line rendering and context configuration.
---@field messages? cmdline.MessagesConfig Message routing and history configuration.
---@field popupmenu? cmdline.PopupmenuConfig Completion popup configuration.

---@class cmdline.ResolvedWidth Width configuration after merging defaults.
---@field value number|string Merged width value used by layout calculations.
---@field min integer Minimum rendered width.
---@field max integer Maximum rendered width.

---@class cmdline.ResolvedCmdlineOptions Complete command-line options after merging defaults.
---@field width cmdline.ResolvedWidth Complete width settings after merging defaults.
---@field border cmdline.Border Default floating-window border.
---@field highlights cmdline.Highlights Highlight links used by command-line windows.
---@field icon_hl_group string Fallback highlight group for context icons.
---@field presets table<string, cmdline.View> Named reusable layouts.

---@class cmdline.ResolvedCmdlineConfig Complete command-line settings after merging defaults.
---@field enabled boolean Whether command-line rendering is active.
---@field view string Fallback preset name.
---@field extensions cmdline.Extension[] Ordered user context resolvers.
---@field opts cmdline.ResolvedCmdlineOptions Complete command-line layout options.
---@field format table<string, cmdline.Format|false> Per-context formats; `false` disables one.

---@class cmdline.ResolvedMessagesConfig Complete message settings after merging defaults.
---@field enabled boolean Whether message routing and history are active.
---@field view_search string|false Enable or disable search-result routing.
---@field search_count cmdline.SearchCountResolved Resolved search-count display settings.

---@class cmdline.ResolvedPopupmenuConfig Complete popupmenu settings after merging defaults.
---@field enabled boolean Whether popupmenu rendering is active.
---@field backend cmdline.PopupBackend Renderer that owns command-line completions.
---@field border cmdline.Border Popup window border style.
---@field kind_icons table<string, string>|false Icons keyed by completion kind, or `false` to disable icons.

---@class cmdline.ResolvedConfig Complete plugin configuration after merging defaults.
---@field cmdline cmdline.ResolvedCmdlineConfig Complete merged command-line settings.
---@field messages cmdline.ResolvedMessagesConfig Complete merged message settings.
---@field popupmenu cmdline.ResolvedPopupmenuConfig Complete merged popupmenu settings.

---@class cmdline.CommandlineState Current state shared with internal modules.
---@field active boolean Whether a command-line is currently displayed.
---@field firstc string Built-in command-line prefix such as `:`, `/`, or `?`.
---@field prompt string Prompt text supplied by `input()`.
---@field level integer Nested command-line level reported by UI2.
---@field pos integer Cursor byte position reported by UI2.
---@field indent? integer Number of leading indentation spaces.
---@field chunks cmdline.Content Original UI2 command-line content.

---@class cmdline.Module Public interface returned by `require("cmdline")`.
---@field setup fun(opts?: cmdline.Config): cmdline.Module Configure and attach the UI renderer.
---@field disable fun(): cmdline.Module Detach UI2, clean up resources, and restore cmdheight.
---@field close_history fun() Close history and restore the previous window.

---@class cmdline.CmpApi nvim-cmp methods patched for the floating command line.
---@field get_cursor fun(): integer[] Return the completion cursor position.
---@field get_screen_cursor fun(): integer[] Return the completion cursor screen position.
---@field is_cmdline_mode fun(): boolean Whether nvim-cmp handles the command line.

local M = {}

---@type cmdline.ResolvedConfig
M.defaults = {
	cmdline = {
		enabled = true,
		view = "cmdline_popup",
		extensions = {},
		opts = {
			highlights = {
				normal = "NormalFloat",
				border = "FloatBorder",
				title = "FloatTitle",
				icon = "Special",
				pum = "Pmenu",
			},
			icon_hl_group = "CmdlineIcon",
			presets = {
				cmdline_popup = { position = "top", title = "Command", icon = "󰘳" },
				search = { position = "top", title = "Search", icon = "" },
				lua = { position = "top", title = "Lua", icon = "" },
				filter = { position = "top", title = "Filter", icon = "󰈲" },
				help = { position = "top", title = "Help", icon = "󰋖" },
				input = { position = "top", title = "Input", icon = "󰌌" },
				rename = { position = "top", title = "Rename", icon = "󰏫" },
				mini = { position = "mini", border = "none" },
			},
			width = { value = "60%", min = 40, max = 100 },
			border = "rounded",
		},
		format = {
			cmdline = { pattern = "^:", view = "cmdline_popup", icon = "󰘳" },
			search_down = { kind = "search", pattern = "^/", view = "mini", icon = "" },
			search_up = { kind = "search", pattern = "^%?", view = "mini", icon = "" },
			filter = { pattern = "^:%s*!", view = "filter", icon = "󰈲" },
			help = { pattern = "^:%s*he?l?p?%s+", view = "help", icon = "󰋖" },
			lua = { pattern = { "^:%s*lua%s+", "^:%s*lua%s*=" }, view = "lua", icon = "" },
			expression = { pattern = "^=", view = "cmdline_popup", icon = "", title = "Expression" },
			input = { view = "input", icon = "󰌌" },
			rename = { view = "rename", icon = "󰏫" },
		},
	},
	messages = {
		enabled = true,
		view_search = "notify",
		search_count = {
			format = "[{current}/{total}]",
			position = "word",
			hl_group = "CmdlineSearchCount",
			current_hl_group = "CmdlineSearchCountCurrent",
		},
	},
	popupmenu = {
		enabled = true,
		backend = "nui",
		border = "rounded",
		kind_icons = {
			default = "󰘦",
			Class = "󰠱",
			d = "󰊕",
			f = "ƒ",
			m = "󰜢",
			t = "󰕳",
			v = "󰀫",
			Color = "󰏘",
			Constant = "󰏿",
			Constructor = "",
			Enum = "",
			EnumMember = "",
			Field = "󰜢",
			File = "󰈙",
			Folder = "󰉋",
			Function = "ƒ",
			Interface = "",
			Keyword = "󰌋",
			Method = "󰆧",
			Module = "󰏗",
			Property = "󰜢",
			Snippet = "󰩫",
			Struct = "󰙅",
			Text = "󰉿",
			Unit = "󰑭",
			Value = "󰎠",
			Variable = "󰀫",
		},
	},
}

---@param opts? cmdline.Config Partial user configuration to merge with defaults.
---@return cmdline.ResolvedConfig config Complete configuration with every default populated.
function M.merge(opts)
	return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
