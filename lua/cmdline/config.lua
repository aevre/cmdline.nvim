local M = {}

M.defaults = {
	cmdline = {
		enabled = true,
		view = "cmdline_popup",
		extensions = {},
		opts = {
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
			lua = { pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" }, view = "lua", icon = "" },
			input = { view = "input", icon = "󰌌" },
			rename = { view = "rename", icon = "󰏫" },
		},
	},
	messages = {
		enabled = true,
		view = "notify",
		view_error = "notify",
		view_warn = "notify",
		view_history = "messages",
		view_search = "notify",
	},
	popupmenu = {
		enabled = true,
		backend = "nui",
		kind_icons = {},
	},
}

function M.merge(opts)
	return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
