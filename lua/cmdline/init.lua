---@class cmdline.View
---@field position? "top"|"middle"|"bottom"|"mini"|"custom"
---@field x? number|string
---@field y? number|string
---@field width? { value?: number|string, min?: integer, max?: integer }
---@field border? string|string[]
---@field title? string
---@field icon? string
---@field icon_hl_group? string

---@class cmdline.Highlights
---@field normal? string
---@field border? string
---@field title? string
---@field icon? string
---@field pum? string

---@class cmdline.Format
---@field pattern? string|string[]
---@field kind? string
---@field view? string
---@field icon? string
---@field title? string
---@field icon_hl_group? string

---@class cmdline.Config
---@field cmdline? { enabled?: boolean, view?: string, extensions?: function[]|table[], opts?: table, format?: table<string, cmdline.Format|false> }
---@field messages? { enabled?: boolean, view?: string, view_error?: string, view_warn?: string, view_history?: string, view_search?: string|false }
---@field popupmenu? { enabled?: boolean, backend?: "nui"|"cmp", kind_icons?: table|string|false }

---@class cmdline.Module
---@field setup fun(opts?: cmdline.Config): cmdline.Module

local M = {}
local config_module = require("cmdline.config")
local highlights = require("cmdline.highlights")
local messages = require("cmdline.messages")
local extensions = require("cmdline.extensions")

local config = vim.deepcopy(config_module.defaults)
local ns = vim.api.nvim_create_namespace("cmdline.nvim")
local cmd_buf
local cmd_win
local pum_buf
local pum_win
local attached = false
local cmp_patched = false
local mini_cmdheight = false
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
	local opts = config.cmdline.opts
	local width = view.width or opts.width
	local cols = vim.o.columns
	if view.position == "mini" then
		return cols, vim.o.lines
	end
	local value_width = dimension(width.value, cols)
	return math.max(width.min or 1, math.min(width.max or cols, value_width)), vim.o.lines
end

local function position(width, height, rows)
	local view = active_view()
	local editor_rows = math.max(1, rows - vim.o.cmdheight)
	if view.position == "mini" then
		return 0, math.max(0, rows - height)
	end
	local available_x = math.max(0, vim.o.columns - width)
	local available_y = math.max(0, editor_rows - height)
	local x = view.position == "custom" and dimension(view.x, available_x) or math.floor(available_x / 2)
	local y = view.position == "custom" and dimension(view.y, available_y)
		or view.position == "top" and 4
		or view.position == "bottom" and math.max(0, available_y - 3)
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
	return extensions.resolve(config, current, chunks_text(current.chunks))
end

local function format_for(context)
	local format = config.cmdline.format[context]
	if context == "search" then
		format = config.cmdline.format[current.firstc == "/" and "search_down" or "search_up"]
	end
	if format == false then
		return {}
	end
	if format and context ~= "cmdline" then
		return format
	end

	local text = current.firstc .. table.concat(chunks_text(current.chunks), "\n")
	local names = vim.tbl_keys(config.cmdline.format)
	table.sort(names)
	for _, name in ipairs(names) do
		if name ~= "cmdline" and name ~= context then
			local candidate = config.cmdline.format[name]
			if candidate and candidate.pattern then
				local patterns = type(candidate.pattern) == "table" and candidate.pattern or { candidate.pattern }
				for _, pattern in ipairs(patterns) do
					if text:match(pattern) then
						return candidate
					end
				end
			end
		end
	end
	return format or {}
end

active_view = function()
	local context = view_name()
	local format = format_for(context)
	local name = format.view or config.cmdline.view
	return config.cmdline.opts.presets[name] or config.cmdline.opts.presets.cmdline_popup
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
	local context = view_name()
	local format = format_for(context)
	local win_config = {
		relative = "editor",
		row = win_row,
		col = col,
		width = width,
		height = height,
		border = view.border or config.cmdline.opts.border,
	}
	local title = format.title or view.title
	if title then
		win_config.title = " " .. title .. " "
		win_config.title_pos = "center"
	end
	local ok = pcall(vim.api.nvim_win_set_config, cmd_win, win_config)
	if not ok then
		return
	end
	local lines = chunks_text(current.chunks)
	local icon = view.icon or format.icon or ""
	local prefix = current.prompt ~= "" and current.prompt or current.firstc
	local hidden = 0
	if context == "lua" then
		local original = lines[1]
		lines[1] = original:gsub("^%s*lua%s+", "")
		hidden = #original - #lines[1]
	elseif context == "help" then
		local original = lines[1]
		lines[1] = original:gsub("^%s*he?l?p?%s+", "")
		hidden = #original - #lines[1]
	end
	if context == "expression" and current.firstc == "=" then
		hidden = 1
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
	vim.api.nvim_buf_clear_namespace(cmd_buf, ns, 0, -1)
	if icon ~= "" then
		vim.api.nvim_buf_add_highlight(
			cmd_buf,
			ns,
			format.icon_hl_group or view.icon_hl_group or config.cmdline.opts.icon_hl_group,
			0,
			0,
			#icon
		)
	end
	local cursor_col = #prefix + (current.indent or 0) + math.max(0, current.pos - hidden)
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
	if cmd_buf and vim.api.nvim_buf_is_valid(cmd_buf) then
		cmd_buf = close(nil, cmd_buf)
	end
	cmd_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(cmd_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(cmd_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(cmd_buf, "swapfile", false)
	vim.api.nvim_buf_set_option(cmd_buf, "modifiable", false)
	local width, rows = dimensions()
	local view = active_view()
	local format = format_for(view_name())
	local height = math.min(8, math.max(1, #chunks_text(current.chunks)))
	local col, row = position(width, height, rows)
	local win_opts = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = view.border or config.cmdline.opts.border,
		focusable = false,
		zindex = 200,
	}
	local title = format.title or view.title
	if title then
		win_opts.title = " " .. title .. " "
		win_opts.title_pos = "center"
	end
	local ok, win = pcall(vim.api.nvim_open_win, cmd_buf, false, win_opts)
	if not ok then
		cmd_win, cmd_buf = close(nil, cmd_buf)
		return
	end
	cmd_win = win
	vim.api.nvim_set_option_value("virtualedit", "onemore", { win = cmd_win })
	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:CmdlineNormal,FloatBorder:CmdlineBorder,FloatTitle:CmdlineTitle",
		{ win = cmd_win }
	)
	redraw_cmdline()
end

local function restore_cmdheight()
	if mini_cmdheight then
		vim.o.cmdheight = 0
		mini_cmdheight = false
	end
end

local function close_cmdline()
	cmd_win, cmd_buf = close(cmd_win, cmd_buf)
	restore_cmdheight()
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
	if
		not config.popupmenu.enabled
		or config.popupmenu.backend ~= "nui"
		or external_completion_menu()
		or #items == 0
	then
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

local close_history, show_history = messages.new(chunks_text, close)
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
		if not config.cmdline.enabled then
			return
		end
		cmdline_generation = cmdline_generation + 1
		local generation = cmdline_generation
		current.active = true
		current.chunks, current.pos, current.firstc = args[1], args[2], args[3]
		current.prompt, current.indent, current.level = args[4], args[5], args[6] or 0
		if active_view().position == "mini" and not mini_cmdheight then
			vim.o.cmdheight = 1
			mini_cmdheight = true
		end
		vim.schedule(function()
			if current.active and generation == cmdline_generation then
				open_cmdline()
				redraw_cmdline()
			end
		end)
		return true
	elseif event == "cmdline_hide" then
		if not config.cmdline.enabled then
			return
		end
		cmdline_generation = cmdline_generation + 1
		current.active = false
		restore_cmdheight()
		vim.schedule(close_cmdline)
		vim.schedule(close_pum)
		return true
	elseif event == "cmdline_pos" then
		if not config.cmdline.enabled then
			return
		end
		current.pos = args[1] or current.pos
		vim.schedule(redraw_cmdline)
		return true
	elseif event == "cmdline_special_char" then
		if not config.cmdline.enabled then
			return
		end
		-- UI2 includes this only for pending keys; the native cmdline remains authoritative.
		return true
	elseif event == "popupmenu_show" then
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
	elseif event == "msg_show" then
		if not config.messages.enabled then
			return
		end
		local kind, chunks = args[1], args[2]
		if config.messages.view_search and config.cmdline.enabled and is_search_message(kind, chunks) then
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
		if not config.messages.enabled then
			return
		end
		vim.schedule(function()
			show_history(args[1] or {})
		end)
		return true
	elseif event == "msg_clear" or event == "msg_history_clear" then
		if not config.messages.enabled then
			return
		end
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

---@param opts? cmdline.Config
function M.setup(opts)
	config = config_module.merge(opts)
	if not config.cmdline.enabled and not config.messages.enabled then
		return M
	end
	highlights.setup(config)
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
