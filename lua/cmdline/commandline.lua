local M = {}
local ui = require("cmdline.ui")
local valid_win, close, chunks_text, set_lines = ui.valid_win, ui.close, ui.chunks_text, ui.set_lines
---@type cmdline.ResolvedConfig
local config
local extensions = require("cmdline.extensions")
local ns
local cmd_buf
local cmd_win
local cmp_patched = false
local mini_cmdheight = false
---@type cmdline.CommandlineState
local current = { active = false, firstc = "", prompt = "", level = 0, pos = 0, chunks = {} }
local cmdline_generation = 0
---@type fun(): string Resolved context for the current command line.
local view_name
---@type fun(): cmdline.View Active preset for the current context.
local active_view

---@param value number|string|nil Dimension in cells, percentage, or nil for zero offset.
---@param total integer Available cells.
---@return integer cells
local function dimension(value, total)
	if type(value) == "number" then
		return value
	end
	if type(value) == "string" then
		local percent = tonumber(value:match("^(%d+)%%$"))
		if percent then
			return math.floor(total * percent / 100 + 0.5)
		end
	end
	return tonumber(value) or 0
end

---@return integer width Available width in columns.
---@return integer rows Available editor rows.
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

---@param width integer
---@param height integer
---@param rows integer
---@return integer col
---@return integer row
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

view_name = function()
	return extensions.resolve(config, current, chunks_text(current.chunks))
end

---@param context string Resolved context name.
---@return cmdline.Format format Format selected for the context or command pattern.
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
				local patterns = candidate.pattern
				if type(patterns) == "string" then
					patterns = { patterns }
				end
				for _, pattern in ipairs(patterns or {}) do
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

---@return nil
local function redraw_cmdline()
	local win, buf, namespace = cmd_win, cmd_buf, ns
	if not win or not buf or not namespace or not valid_win(win) then
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
	local ok = pcall(vim.api.nvim_win_set_config, win, win_config)
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
	set_lines(buf, lines)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	if icon ~= "" then
		vim.api.nvim_buf_set_extmark(buf, namespace, 0, 0, {
			end_col = #icon,
			hl_group = format.icon_hl_group or view.icon_hl_group or config.cmdline.opts.icon_hl_group,
		})
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
	vim.api.nvim_win_set_cursor(win, { math.min(row + 1, #lines), cursor_col })
	local start_col = #prefix + (current.indent or 0)
	vim.api.nvim__redraw({ flush = true })
	local screen = vim.fn.screenpos(win, 1, start_col + 1)
	vim.g.ui_cmdline_pos = { screen.row, screen.col - 1 }
	vim.api.nvim__redraw({ flush = true, cursor = true, win = win })
end

---@return nil
local function open_cmdline()
	if valid_win(cmd_win) then
		return
	end
	if cmd_buf and vim.api.nvim_buf_is_valid(cmd_buf) then
		cmd_buf = close(nil, cmd_buf)
	end
	local buf = vim.api.nvim_create_buf(false, true)
	cmd_buf = buf
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
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
	local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_opts)
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

---@return nil
local function restore_cmdheight()
	if mini_cmdheight then
		vim.o.cmdheight = 0
		mini_cmdheight = false
	end
end

---@return nil
local function close_cmdline()
	cmd_win, cmd_buf = close(cmd_win, cmd_buf)
	restore_cmdheight()
	vim.g.ui_cmdline_pos = nil
	current = { active = false, firstc = "", prompt = "", level = 0, pos = 0, chunks = {} }
end

---@param event string UI2 event name.
---@return boolean? handled Whether this module consumed the event.
function M.handle(event, ...)
	if event == "cmdline_show" then
		local args = { ... }
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
		return true
	elseif event == "cmdline_pos" then
		if not config.cmdline.enabled then
			return
		end
		local args = { ... }
		current.pos = args[1] or current.pos
		vim.schedule(redraw_cmdline)
		return true
	elseif event == "cmdline_special_char" then
		if not config.cmdline.enabled then
			return
		end
		-- UI2 includes this only for pending keys; the native cmdline remains authoritative.
		return true
	end
end

---@return nil
function M.patch_cmp()
	if cmp_patched then
		return
	end
	local ok, api = pcall(require, "cmp.utils.api")
	if not ok then
		return
	end
	---@cast api cmdline.CmpApi
	local get_cursor = api.get_cursor
	local get_screen_cursor = api.get_screen_cursor
	api.get_cursor = function()
		local win = cmd_win
		if win and api.is_cmdline_mode() and valid_win(win) then
			return { vim.api.nvim_win_get_cursor(win)[1], math.max(0, vim.fn.getcmdpos() - 1) }
		end
		return get_cursor()
	end
	api.get_screen_cursor = function()
		local win = cmd_win
		if win and api.is_cmdline_mode() and valid_win(win) and vim.g.ui_cmdline_pos then
			local pos = vim.g.ui_cmdline_pos
			local before = vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1)
			return { pos[1], pos[2] + vim.fn.strdisplaywidth(before) }
		end
		return get_screen_cursor()
	end
	cmp_patched = true
end

---@param opts cmdline.ResolvedConfig Complete merged plugin configuration.
---@param namespace integer Namespace used for command-line highlights.
---@return nil
function M.configure(opts, namespace)
	config, ns = opts, namespace
end

---@return nil
function M.resize()
	local win = cmd_win
	if win and valid_win(win) then
		local width, rows = dimensions()
		local height = vim.api.nvim_win_get_height(win)
		local col, row = position(width, height, rows)
		vim.api.nvim_win_set_config(win, { width = width, row = row, col = col })
	end
end

---@param grid integer? UI grid anchoring the popup; `-1` means external command-line.
---@return integer? win Command-line window id, or nil when the popup uses grid coordinates.
---@return integer? row Cursor row inside the command-line window.
---@return integer? col Display column of the completion anchor.
function M.popup_anchor(grid)
	local win, buf = cmd_win, cmd_buf
	if (current.active or grid == -1) and win and buf and valid_win(win) then
		redraw_cmdline()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
		return win, cursor[1], 1 + vim.fn.strdisplaywidth(line:sub(1, cursor[2]))
	end
end

return M
