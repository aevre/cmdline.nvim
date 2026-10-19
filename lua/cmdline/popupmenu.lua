local M = {}
local ui = require("cmdline.ui")
local valid_win, close, set_lines = ui.valid_win, ui.close, ui.set_lines
local config
local commandline = require("cmdline.commandline")
local pum_buf, pum_win
local pum_items = {}
local pum_selected = -1
local pum_first = 1
local pum_height = 0
local pum_icon_width = 0
local pum_show_icons = false

local function redraw_pum()
	if not valid_win(pum_win) then
		return
	end
	if pum_selected >= 0 then
		pum_first = math.max(1, math.min(pum_selected + 1, #pum_items - pum_height + 1))
	end
	local lines = {}
	local icons = config.popupmenu.kind_icons
	for i = pum_first, math.min(#pum_items, pum_first + pum_height - 1) do
		local item = pum_items[i]
		local label = item.word or item[1] or ""
		local icon = type(icons) == "table" and icons[item.kind or item[2]] or nil
		local prefix = i == pum_selected + 1 and "> " or "  "
		if pum_show_icons then
			prefix = prefix .. (icon or "") .. string.rep(" ", pum_icon_width - vim.fn.strdisplaywidth(icon or "") + 1)
		end
		lines[#lines + 1] = prefix .. label
	end
	set_lines(pum_buf, lines)
end

local function close_pum()
	pum_win, pum_buf = close(pum_win, pum_buf)
	pum_items, pum_selected, pum_first, pum_height, pum_icon_width, pum_show_icons = {}, -1, 1, 0, 0, false
end

local function external_completion_menu()
	return vim.api.nvim_get_mode().mode == "c" and (package.loaded["blink.cmp"] ~= nil or package.loaded["cmp"] ~= nil)
end

---@param items cmdline.PopupItem[] Completion items from the UI2 event.
---@param selected integer Selected item index, or -1 when no item is selected.
---@param row integer Popup anchor row.
---@param col integer Popup anchor column.
---@param grid integer? UI grid that emitted the popup event.
local function open_pum(items, selected, row, col, grid)
	close_pum()
	if
		not config.popupmenu.enabled
		or config.popupmenu.backend ~= "nui"
		or external_completion_menu()
		or #items == 0
	then
		return
	end
	pum_items, pum_selected = items, selected
	pum_icon_width = 0
	pum_show_icons = type(config.popupmenu.kind_icons) == "table" and next(config.popupmenu.kind_icons) ~= nil
	if pum_show_icons then
		for _, icon in pairs(config.popupmenu.kind_icons) do
			pum_icon_width = math.max(pum_icon_width, vim.fn.strdisplaywidth(icon))
		end
	end
	pum_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = pum_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = pum_buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = pum_buf })
	local height = math.min(#items, 12)
	pum_height = height
	local width = 1
	for _, item in ipairs(items) do
		width = math.max(
			width,
			vim.fn.strdisplaywidth(item.word or item[1] or "") + 2 + (pum_show_icons and pum_icon_width + 1 or 0)
		)
	end
	local opts = {
		relative = "editor",
		row = math.max(0, row),
		col = math.max(0, col),
		width = math.min(width, vim.o.columns - math.max(0, col)),
		height = height,
		style = "minimal",
		border = "single",
		focusable = false,
		zindex = 201,
	}
	local cmd_win, cursor_row, popup_col = commandline.popup_anchor(grid)
	if cmd_win and cursor_row and popup_col then
		opts.relative = "win"
		opts.win = cmd_win
		opts.row = cursor_row
		opts.col = popup_col
		opts.width = math.max(1, math.min(width, vim.o.columns - popup_col))
	end
	pum_win = vim.api.nvim_open_win(pum_buf, false, opts)
	vim.api.nvim_set_option_value("winhighlight", "Normal:CmdlinePum,FloatBorder:CmdlineBorder", { win = pum_win })
	redraw_pum()
end

---@param event string UI2 event name.
---@param ... any Event payload for the selected popup event.
---@return boolean? Whether this module handled the event.
function M.handle(event, ...)
	local args = { ... }
	if event == "popupmenu_show" then
		if not config.popupmenu.enabled then
			return
		end
		vim.schedule(function()
			open_pum(args[1] or {}, args[2] or -1, args[3] or 0, args[4] or 0, args[5])
		end)
		return true
	elseif event == "popupmenu_select" then
		if not config.popupmenu.enabled then
			return
		end
		pum_selected = args[1] or -1
		vim.schedule(redraw_pum)
		return true
	elseif event == "popupmenu_hide" then
		if not config.popupmenu.enabled then
			return
		end
		vim.schedule(close_pum)
		return true
	end
end

---@param opts cmdline.ResolvedConfig Complete merged plugin configuration.
function M.configure(opts)
	config = opts
end

M.close = close_pum
return M
