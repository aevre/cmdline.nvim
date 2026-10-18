---@class cmdline.View
---@field position? "top"|"middle"|"bottom"|"mini"|"custom"
---@field x? number|string
---@field y? number|string
---@field width? { value?: number|string, min?: integer, max?: integer }
---@field border? string|string[]
---@field title? string
---@field icon? string

---@class cmdline.Config
---@field enabled? boolean
---@field position? { x?: number|string, y?: number|string } Legacy middle-view position
---@field presets? table<string, cmdline.View>
---@field views? table<string, string>
---@field prefixes? table<string, { icon?: string }>
---@field border? string|string[]
---@field popupmenu? boolean
---@field notify_search? boolean

---@class cmdline.Module
---@field setup fun(opts?: cmdline.Config): cmdline.Module

local M = {}

local defaults = {
	enabled = true,
	presets = {
		top = { position = "top", title = "Filter" },
		middle = { position = "middle", title = "Command" },
		lua = { position = "middle", title = "Lua", icon = "" },
		bottom = { position = "bottom", title = "Search" },
		mini = { position = "mini", border = "none" },
	},
	views = {
		cmdline = "middle",
		search = "bottom",
		input = "middle",
		lua = "lua",
		filter = "top",
		substitute = "top",
	},
	prefixes = {
		cmdline = { icon = ">" },
		search = { icon = "/" },
		input = { icon = "?" },
		lua = { icon = "" },
		filter = { icon = "!" },
		substitute = { icon = "s" },
	},
	width = { value = "60%", min = 40, max = 100 },
	border = "rounded",
	popupmenu = true,
	notify_search = true,
}

local config = vim.deepcopy(defaults)
local ns = vim.api.nvim_create_namespace("cmdline.nvim")
local cmd_buf
local cmd_win
local pum_buf
local pum_win
local history_buf
local history_win
local history_prev_win
local attached = false
local cmp_patched = false
local current = { active = false, firstc = "", prompt = "", level = 0, pos = 0, chunks = {} }
local cmdline_generation = 0

local pum_items = {}
local pum_selected = -1

local view_name
local active_view

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function close(win, buf)
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	return nil, nil
end

local function dimension(value, total)
	if type(value) == "number" then
		return value
	end
	local percent = tonumber(value:match("^(%d+)%%$"))
	if percent then
		return math.floor(total * percent / 100 + 0.5)
	end
	return tonumber(value) or 0
end

local function dimensions()
	local view = active_view()
	local width = view.width or config.width
	local cols = vim.o.columns
	if view.position == "mini" then
		return cols, 1
	end
	local value_width = dimension(width.value, cols)
	return math.max(width.min or 1, math.min(width.max or cols, value_width)), vim.o.lines
end

local function position(width, height, rows)
	local view = active_view()
	if view.position == "mini" then
		return 0, math.max(0, rows - height)
	end
	local available_x = math.max(0, vim.o.columns - width)
	local available_y = math.max(0, rows - height)
	local x = view.position == "custom" and dimension(view.x, available_x) or math.floor(available_x / 2)
	local y = view.position == "custom" and dimension(view.y, available_y)
		or view.position == "top" and 1
		or view.position == "bottom" and available_y
		or math.floor(available_y / 2)
	return math.max(0, math.min(available_x, x)), math.max(0, math.min(available_y, y))
end

local function chunks_text(chunks)
	local lines = { "" }
	for _, chunk in ipairs(chunks or {}) do
		local text = chunk[2] or ""
		local parts = vim.split(text, "\n", { plain = true })
		lines[#lines] = lines[#lines] .. parts[1]
		for i = 2, #parts do
			table.insert(lines, parts[i])
		end
	end
	return lines
end

view_name = function()
	local firstc = current.firstc
	if firstc == "/" or firstc == "?" then
		return "search"
	elseif current.prompt ~= "" then
		return "input"
	elseif firstc == "=" then
		return "expression"
	elseif firstc == ">" then
		return "debug"
	end
	local command = table.concat(chunks_text(current.chunks), " "):gsub("^%s*:", "")
	if command:match("^lua%f[%W]") or command:match("^lua%s*=") then
		return "lua"
	elseif command:match("^s/") or command:match("^substitute%f[%W]") then
		return "substitute"
	elseif command:match("^filter%f[%W]") or command:match("^!") then
		return "filter"
	end
	return "cmdline"
end

active_view = function()
	local name = config.views[view_name()] or "middle"
	return config.presets[name] or config.presets.middle
end

local function set_lines(buf, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "" })
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

local function redraw_cmdline()
	if not valid_win(cmd_win) then
		return
	end
	local width, rows = dimensions()
	local height = math.min(8, math.max(1, #chunks_text(current.chunks)))
	local col, win_row = position(width, height, rows)
	local view = active_view()
	local ok = pcall(vim.api.nvim_win_set_config, cmd_win, {
		relative = "editor",
		row = win_row,
		col = col,
		width = width,
		height = height,
		border = view.border or config.border,
		title = view.title,
		title_pos = "center",
	})
	if not ok then
		return
	end
	local lines = chunks_text(current.chunks)
	local context = view_name()
	local prefix_config = config.prefixes[context] or {}
	local icon = view.icon or prefix_config.icon or ""
	local prefix = current.prompt ~= "" and current.prompt or current.firstc
	if context == "expression" and current.firstc == "=" then
		lines[1] = lines[1]:sub(2)
		prefix, icon = "", ""
	end
	if icon ~= "" then
		prefix = icon .. " " .. (current.prompt ~= "" and current.prompt or "")
	end
	if prefix ~= "" then
		lines[1] = prefix .. string.rep(" ", current.indent or 0) .. lines[1]
	end
	set_lines(cmd_buf, lines)
	local cursor_col = #prefix + (current.indent or 0) + current.pos
	local row = 0
	for i = 1, #lines do
		if cursor_col > #lines[i] then
			cursor_col = cursor_col - #lines[i] - 1
			row = row + 1
		else
			break
		end
	end
	vim.api.nvim_win_set_cursor(cmd_win, { math.min(row + 1, #lines), cursor_col })
	local start_col = #prefix + (current.indent or 0)
	vim.api.nvim__redraw({ flush = true })
	local screen = vim.fn.screenpos(cmd_win, 1, start_col + 1)
	vim.g.ui_cmdline_pos = {
		screen.row,
		screen.col - 1,
	}
	vim.api.nvim__redraw({ flush = true, cursor = true, win = cmd_win })
end

local function open_cmdline()
	if valid_win(cmd_win) then
		return
	end
	cmd_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(cmd_buf, "cmdline://input")
	vim.api.nvim_buf_set_option(cmd_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(cmd_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(cmd_buf, "swapfile", false)
	vim.api.nvim_buf_set_option(cmd_buf, "modifiable", false)
	local width, rows = dimensions()
	local view = active_view()
	local height = math.min(8, math.max(1, #chunks_text(current.chunks)))
	local col, row = position(width, height, rows)
	cmd_win = vim.api.nvim_open_win(cmd_buf, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = view.border or config.border,
		title = view.title,
		title_pos = "center",
		focusable = false,
		zindex = 200,
	})
	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:CmdlineNormal,FloatBorder:CmdlineBorder,FloatTitle:CmdlineTitle",
		{ win = cmd_win }
	)
	redraw_cmdline()
end

local function close_cmdline()
	cmd_win, cmd_buf = close(cmd_win, cmd_buf)
	vim.g.ui_cmdline_pos = nil
	current = { active = false, firstc = "", prompt = "", level = 0, pos = 0, chunks = {} }
end

local function redraw_pum()
	if not valid_win(pum_win) then
		return
	end
	local lines = {}
	for i, item in ipairs(pum_items) do
		local label = item.word or item[1] or ""
		lines[i] = (i == pum_selected + 1 and "> " or "  ") .. label
	end
	set_lines(pum_buf, lines)
end

local function close_pum()
	pum_win, pum_buf = close(pum_win, pum_buf)
	pum_items, pum_selected = {}, -1
end

local function external_completion_menu()
	return vim.api.nvim_get_mode().mode == "c" and (package.loaded["blink.cmp"] ~= nil or package.loaded["cmp"] ~= nil)
end

local function open_pum(items, selected, row, col, grid)
	close_pum()
	if not config.popupmenu or external_completion_menu() or #items == 0 then
		return
	end
	pum_items, pum_selected = items, selected
	pum_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(pum_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(pum_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(pum_buf, "modifiable", false)
	local height = math.min(#items, 12)
	local width = 1
	for _, item in ipairs(items) do
		width = math.max(width, vim.fn.strdisplaywidth(item.word or item[1] or "") + 2)
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
	if (current.active or grid == -1) and valid_win(cmd_win) then
		redraw_cmdline()
		local cursor = vim.api.nvim_win_get_cursor(cmd_win)
		local line = vim.api.nvim_buf_get_lines(cmd_buf, cursor[1] - 1, cursor[1], false)[1] or ""
		local popup_col = 1 + vim.fn.strdisplaywidth(line:sub(1, cursor[2]))
		opts.relative = "win"
		opts.win = cmd_win
		opts.row = cursor[1]
		opts.col = popup_col
		opts.width = math.max(1, math.min(width, vim.o.columns - popup_col))
	end
	pum_win = vim.api.nvim_open_win(pum_buf, false, opts)
	vim.api.nvim_set_option_value("winhighlight", "Normal:CmdlinePum,FloatBorder:CmdlineBorder", { win = pum_win })
	redraw_pum()
end

local function notify_message(chunks, level, title)
	local text = table.concat(chunks_text(chunks), "\n")
	if text ~= "" then
		vim.notify(text, level, { title = title or "Messages" })
	end
end

local function message_level(kind)
	if kind == "emsg" or kind == "echoerr" or kind == "lua_error" or kind == "rpc_error" then
		return vim.log.levels.ERROR
	end
	if kind == "wmsg" then
		return vim.log.levels.WARN
	end
	return vim.log.levels.INFO
end

local function should_notify_message(kind)
	return vim.tbl_contains({
		"",
		"echo",
		"echomsg",
		"lua_print",
		"list_cmd",
		"shell_out",
		"shell_err",
		"shell_ret",
		"emsg",
		"echoerr",
		"lua_error",
		"rpc_error",
		"wmsg",
	}, kind)
end

local function close_history()
	local previous = history_prev_win
	history_win, history_buf = close(history_win, history_buf)
	history_prev_win = nil
	if valid_win(previous) then
		pcall(vim.api.nvim_set_current_win, previous)
	end
end

local function show_history(entries)
	close_history()
	local lines = {}
	for index, entry in ipairs(entries) do
		local entry_lines = chunks_text(entry[2] or {})
		if index > 1 and not entry[3] then
			lines[#lines + 1] = ""
		end
		vim.list_extend(lines, entry_lines)
	end
	if #lines == 0 then
		return
	end

	history_prev_win = vim.api.nvim_get_current_win()
	history_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(history_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(history_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(history_buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(history_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(history_buf, "modifiable", false)
	vim.api.nvim_buf_set_keymap(
		history_buf,
		"n",
		"q",
		"<Cmd>lua require('cmdline').close_history()<CR>",
		{ silent = true, nowait = true }
	)
	vim.api.nvim_buf_set_keymap(
		history_buf,
		"n",
		"<Esc>",
		"<Cmd>lua require('cmdline').close_history()<CR>",
		{ silent = true, nowait = true }
	)

	local width = math.max(40, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.8)))
	local height = math.max(1, math.min(#lines, vim.o.lines - 4))
	history_win = vim.api.nvim_open_win(history_buf, true, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
		border = config.border,
		title = "Messages",
		title_pos = "center",
		zindex = 210,
	})
	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:CmdlineNormal,FloatBorder:CmdlineBorder,FloatTitle:CmdlineTitle",
		{ win = history_win }
	)
	vim.api.nvim_set_option_value("wrap", true, { win = history_win })
	vim.api.nvim_win_set_cursor(history_win, { 1, 0 })
end

M.close_history = close_history

local function is_search_message(kind, chunks)
	if kind == "search_count" then
		return true
	end
	if kind ~= "wmsg" and kind ~= "emsg" then
		return false
	end
	local text = table.concat(chunks_text(chunks), "\n")
	return text:match("E486") ~= nil
		or text:lower():match("search hit") ~= nil
		or text:lower():match("pattern not found") ~= nil
end

local function handle(event, ...)
	local args = { ... }
	if event == "cmdline_show" then
		cmdline_generation = cmdline_generation + 1
		local generation = cmdline_generation
		current.active = true
		current.chunks, current.pos, current.firstc = args[1], args[2], args[3]
		current.prompt, current.indent, current.level = args[4], args[5], args[6] or 0
		vim.schedule(function()
			if current.active and generation == cmdline_generation then
				open_cmdline()
				redraw_cmdline()
			end
		end)
		return true
	elseif event == "cmdline_hide" then
		cmdline_generation = cmdline_generation + 1
		current.active = false
		vim.schedule(close_cmdline)
		vim.schedule(close_pum)
		return true
	elseif event == "cmdline_pos" then
		current.pos = args[1] or current.pos
		vim.schedule(redraw_cmdline)
		return true
	elseif event == "cmdline_special_char" then
		-- UI2 includes this only for pending keys; the native cmdline remains authoritative.
		return true
	elseif event == "popupmenu_show" then
		vim.schedule(function()
			open_pum(args[1] or {}, args[2] or -1, args[3] or 0, args[4] or 0, args[5])
		end)
		return true
	elseif event == "popupmenu_select" then
		pum_selected = args[1] or -1
		vim.schedule(redraw_pum)
		return true
	elseif event == "popupmenu_hide" then
		vim.schedule(close_pum)
		return true
	elseif event == "msg_show" then
		local kind, chunks = args[1], args[2]
		if config.notify_search and is_search_message(kind, chunks) then
			vim.schedule(function()
				notify_message(chunks, kind == "emsg" and vim.log.levels.ERROR or vim.log.levels.WARN, "Search")
			end)
		elseif should_notify_message(kind) then
			vim.schedule(function()
				notify_message(chunks, message_level(kind), kind == "lua_print" and "Lua" or nil)
			end)
		end
		return true
	elseif event == "msg_history_show" then
		vim.schedule(function()
			show_history(args[1] or {})
		end)
		return true
	elseif event == "msg_clear" or event == "msg_history_clear" then
		if event == "msg_history_clear" then
			vim.schedule(close_history)
		end
		return true
	end
end

local function patch_cmp()
	if cmp_patched then
		return
	end
	local ok, api = pcall(require, "cmp.utils.api")
	if not ok then
		return
	end
	local get_cursor = api.get_cursor
	local get_screen_cursor = api.get_screen_cursor
	api.get_cursor = function()
		if api.is_cmdline_mode() and valid_win(cmd_win) then
			return { vim.api.nvim_win_get_cursor(cmd_win)[1], vim.fn.getcmdpos() - 1 }
		end
		return get_cursor()
	end
	api.get_screen_cursor = function()
		if api.is_cmdline_mode() and valid_win(cmd_win) and vim.g.ui_cmdline_pos then
			local pos = vim.g.ui_cmdline_pos
			local before = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
			return { pos[1], pos[2] + vim.fn.strdisplaywidth(before) }
		end
		return get_screen_cursor()
	end
	cmp_patched = true
end

local function highlights()
	vim.api.nvim_set_hl(0, "CmdlineNormal", { link = "NormalFloat", default = true })
	vim.api.nvim_set_hl(0, "CmdlineBorder", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "CmdlineTitle", { link = "FloatTitle", default = true })
	vim.api.nvim_set_hl(0, "CmdlinePum", { link = "Pmenu", default = true })
end

---@param opts? cmdline.Config
function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	if opts and opts.position and not (opts.presets and opts.presets.middle) then
		config.presets.middle.position = "custom"
		config.presets.middle.x = opts.position.x
		config.presets.middle.y = opts.position.y
	end
	if not config.enabled then
		return M
	end
	highlights()
	if vim.fn.has("nvim-0.12") == 0 then
		vim.notify("cmdline.nvim requires Neovim 0.12", vim.log.levels.WARN)
		return M
	end
	if not attached then
		vim.ui_attach(ns, {
			ext_cmdline = true,
			ext_popupmenu = true,
			ext_messages = true,
			set_cmdheight = false,
		}, handle)
		vim.o.cmdheight = 0
		attached = true
	end
	local group = vim.api.nvim_create_augroup("cmdline.nvim", { clear = true })
	vim.api.nvim_create_autocmd({ "CmdlineEnter", "CmdlineChanged" }, {
		group = group,
		callback = function()
			vim.schedule(patch_cmp)
		end,
	})
	vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
		group = group,
		callback = function()
			if valid_win(cmd_win) then
				local width, rows = dimensions()
				local height = vim.api.nvim_win_get_height(cmd_win)
				local col, row = position(width, height, rows)
				vim.api.nvim_win_set_config(cmd_win, { width = width, row = row, col = col })
			end
		end,
	})
	return M
end

return M
