local M = {}

function M.setup(config)
	local groups = config.cmdline.opts.highlights
	local function link(name, group, fallback)
		if not group or vim.fn.hlexists(group) == 0 then
			group = fallback
		end
		vim.api.nvim_set_hl(0, name, { link = group, default = true })
	end
	link("CmdlineNormal", groups.normal, "NormalFloat")
	link("CmdlineIcon", groups.icon, "Special")
	link("CmdlineBorder", groups.border, "FloatBorder")
	link("CmdlineTitle", groups.title, "FloatTitle")
	link("CmdlinePum", groups.pum, "Pmenu")
	vim.api.nvim_set_hl(0, "CmdlineSearchCount", { fg = "#ff9e64", bold = true, default = true })
	vim.api.nvim_set_hl(0, "CmdlineSearchCountCurrent", { fg = "#a9b1d6", bold = true, default = true })
end

return M
