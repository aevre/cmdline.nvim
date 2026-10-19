local M = {}
local ui = require("cmdline.ui")
local valid_win, close, chunks_text, set_lines = ui.valid_win, ui.close, ui.chunks_text, ui.set_lines
---@type cmdline.ResolvedConfig
local config
local extensions = require("cmdline.extensions")
local ns
local search_ns
local search_generation = 0
local search_abort_generation = 0
local search_aborted = false
local search_watch_pending = false
local search_chunks
local cmd_buf
local cmd_win
local cmp_patched = false
local mini_cmdheight = false
local original_cmdheight
---@type cmdline.CommandlineState
local current = { active = false, firstc = "", prompt = "", level = 0, pos = 0, chunks = {} }
local cmdline_generation = 0
local search_buf
local command_block = {}
local special_char
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
local function render_chunk_highlights(buf, namespace, chunks, start_row, start_col)
	local row, col = start_row, start_col
	for _, chunk in ipairs(chunks) do
		local text = chunk[2] or ""
		local parts = vim.split(text, "\n", { plain = true })
		local attrs, hl_id = chunk[1], chunk[3]
		local group
		if type(attrs) == "table" and next(attrs) then
			local resolved = vim.deepcopy(attrs)
			for _, key in ipairs({ "foreground", "background", "special" }) do
				if type(resolved[key]) == "number" then
					resolved[key] = string.format("#%06x", resolved[key])
				end
			end
			group = "CmdlineChunk" .. tostring(hl_id or vim.inspect(resolved):gsub("%W", ""))
			vim.api.nvim_set_hl(0, group, resolved)
		end
		for index, part in ipairs(parts) do
			if group and #part > 0 then
				vim.api.nvim_buf_set_extmark(buf, namespace, row, col, {
					end_col = col + #part,
					hl_group = group,
				})
			end
			col = col + #part
			if index < #parts then
				row, col = row + 1, 0
			end
		end
	end
end

local function redraw_cmdline()
	local win, buf, namespace = cmd_win, cmd_buf, ns
	if not win or not buf or not namespace or not valid_win(win) then
		return
	end
	local width, rows = dimensions()
	local input_lines = chunks_text(current.chunks)
	local block_lines = {}
	for _, block_line in ipairs(command_block) do
		vim.list_extend(block_lines, chunks_text(block_line))
	end
	local height = math.min(8, math.max(1, #input_lines + #block_lines))
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
	local input_row = #block_lines
	local lines
	local icon = current.prompt ~= "" and "" or (view.icon or format.icon or "")
	local prefix = current.prompt ~= "" and current.prompt or current.firstc
	local hidden = 0
	if context == "lua" then
		local original = input_lines[1]
		input_lines[1] = original:gsub("^%s*lua%s+", "")
		hidden = #original - #input_lines[1]
	elseif context == "help" then
		local original = input_lines[1]
		input_lines[1] = original:gsub("^%s*he?l?p?%s+", "")
		hidden = #original - #input_lines[1]
	end
	if context == "expression" and current.firstc == "=" then
		hidden = 1
		input_lines[1] = input_lines[1]:sub(2)
		prefix, icon = "", ""
	end
	lines = vim.list_extend(vim.deepcopy(block_lines), vim.deepcopy(input_lines))
	if icon ~= "" then
		prefix = icon .. " " .. (current.prompt ~= "" and current.prompt or "")
	end
	if prefix ~= "" then
		lines[input_row + 1] = prefix .. string.rep(" ", current.indent or 0) .. lines[input_row + 1]
	end
	set_lines(buf, lines)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	local input_prefix = prefix .. string.rep(" ", current.indent or 0)
	local block_row = 0
	for _, block_line in ipairs(command_block) do
		render_chunk_highlights(buf, namespace, block_line, block_row, 0)
		block_row = block_row + #chunks_text(block_line)
	end
	render_chunk_highlights(buf, namespace, current.chunks, input_row, #input_prefix)
	if special_char and special_char.level == current.level then
		local special_row, special_col = input_row, math.max(0, current.pos - hidden)
		for _, line in ipairs(input_lines) do
			if special_col <= #line then
				break
			end
			special_col = special_col - #line - 1
			special_row = special_row + 1
		end
		local special_column = #input_prefix + special_col
		vim.api.nvim_buf_set_extmark(buf, namespace, special_row, special_column, {
			virt_text = { { vim.fn.strtrans(special_char.char), "SpecialKey" } },
			virt_text_pos = special_char.shift and "inline" or "overlay",
		})
	end
	if icon ~= "" then
		vim.api.nvim_buf_set_extmark(buf, namespace, input_row, 0, {
			end_col = #icon,
			hl_group = format.icon_hl_group or view.icon_hl_group or config.cmdline.opts.icon_hl_group,
		})
	end
	local cursor_col = #prefix + (current.indent or 0) + math.max(0, current.pos - hidden)
	local cursor_row = input_row
	for i = input_row + 1, #lines do
		if cursor_col > #lines[i] then
			cursor_col = cursor_col - #lines[i] - 1
			cursor_row = cursor_row + 1
		else
			break
		end
	end
	vim.api.nvim_win_set_cursor(win, { math.min(cursor_row + 1, #lines), cursor_col })
	local start_col = #prefix + (current.indent or 0)
	vim.api.nvim__redraw({ flush = true })
	local screen = vim.fn.screenpos(win, input_row + 1, start_col + 1)
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
	local block_height = 0
	for _, line in ipairs(command_block) do
		block_height = block_height + #chunks_text(line)
	end
	local height = math.min(8, math.max(1, #chunks_text(current.chunks) + block_height))
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
		vim.o.cmdheight = original_cmdheight or 0
		original_cmdheight = nil
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

---@return nil
local function clear_search_count()
	search_chunks = nil
	search_generation = search_generation + 1
	local generation = search_generation
	vim.schedule(function()
		if generation == search_generation and search_buf and vim.api.nvim_buf_is_valid(search_buf) then
			vim.api.nvim_buf_clear_namespace(search_buf, search_ns, 0, -1)
			search_buf = nil
		end
	end)
end

---@return nil
local function watch_search_count()
	if search_watch_pending or not search_chunks then
		return
	end
	search_watch_pending = true
	vim.defer_fn(function()
		search_watch_pending = false
		if not vim.o.hlsearch then
			return
		end
		if vim.v.hlsearch == 0 then
			clear_search_count()
		end
		watch_search_count()
	end, 30)
end

---@param event string UI2 event name.
---@return boolean? handled Whether this module consumed the event.
function M.handle(event, ...)
	if event == "cmdline_show" then
		local args = { ... }
		if not config.cmdline.enabled then
			return
		end
		search_abort_generation = search_abort_generation + 1
		search_aborted = false
		if not current.active or current.firstc ~= args[3] or not args[3]:match("^[/?]$") then
			clear_search_count()
		end
		cmdline_generation = cmdline_generation + 1
		local chunks, firstc, prompt, level = args[1], args[3], args[4], args[6] or 0
		if
			special_char
			and (
				special_char.level ~= level
				or special_char.firstc ~= firstc
				or special_char.prompt ~= prompt
				or special_char.content ~= table.concat(chunks_text(chunks))
			)
		then
			special_char = nil
		end
		cmdline_generation = cmdline_generation + 1
		local generation = cmdline_generation
		current.active = true
		command_block = {}
		current.chunks, current.pos, current.firstc = chunks, args[2], firstc
		current.prompt, current.indent, current.level = prompt, args[5], level
		if active_view().position == "mini" and not mini_cmdheight then
			original_cmdheight = vim.o.cmdheight
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
		local args = { ... }
		cmdline_generation = cmdline_generation + 1
		if current.firstc:match("^[/?]$") and args[2] then
			search_abort_generation = search_abort_generation + 1
			local generation = search_abort_generation
			search_aborted = true
			vim.schedule(function()
				if generation == search_abort_generation then
					search_aborted = false
				end
			end)
		end
		current.active = false
		clear_search_count()
		restore_cmdheight()
		vim.schedule(close_cmdline)
		return true
	elseif event == "cmdline_pos" then
		if not config.cmdline.enabled then
			return
		end
		local args = { ... }
		current.pos = args[1] or current.pos
		special_char = nil
		vim.schedule(redraw_cmdline)
		return true
	elseif event == "cmdline_special_char" then
		if not config.cmdline.enabled then
			return
		end
		local char, shift, level = ...
		special_char = {
			char = char,
			shift = shift,
			level = level,
			firstc = current.firstc,
			prompt = current.prompt,
			content = table.concat(chunks_text(current.chunks)),
		}
		local generation = cmdline_generation
		vim.schedule(function()
			if current.active and generation == cmdline_generation then
				open_cmdline()
				redraw_cmdline()
			end
		end)
		return true
	elseif event == "cmdline_block_show" then
		if not config.cmdline.enabled then
			return
		end
		local lines = (...)
		command_block = lines or {}
		vim.schedule(function()
			open_cmdline()
			redraw_cmdline()
		end)
		return true
	elseif event == "cmdline_block_append" then
		if not config.cmdline.enabled then
			return
		end
		command_block[#command_block + 1] = (...)
		vim.schedule(function()
			open_cmdline()
			redraw_cmdline()
		end)
		return true
	elseif event == "cmdline_block_hide" then
		if not config.cmdline.enabled then
			return
		end
		command_block = {}
		cmdline_generation = cmdline_generation + 1
		current.active = false
		clear_search_count()
		vim.schedule(close_cmdline)
		return true
	elseif event == "msg_show" then
		local args = { ... }
		if args[1] == "search_count" then
			if search_aborted then
				return true
			end
			if config.messages.view_search then
				local chunks = args[2]
				local count = chunks[#chunks]
				local current_match, total
				if count then
					current_match, total = count[2]:match("W? %[(>?%d*%??)/>?(%d*%?*)%]")
				end
				if current_match and total then
					local opts = config.messages.search_count
					local formatted = opts.format
						:gsub("{current}", function()
							return current_match
						end)
						:gsub("{total}", function()
							return total
						end)
					local current_start, current_end = formatted:find(current_match, 1, true)
					search_chunks = {
						{ formatted:sub(1, current_start - 1), opts.hl_group },
						{ current_match, opts.current_hl_group },
						{ formatted:sub(current_end + 1), opts.hl_group },
					}
					M.refresh_search_count()
					watch_search_count()
				end
			end
			return true
		end
	end
end

---@return nil
function M.refresh_search_count()
	if not config.messages.view_search or not search_chunks then
		return
	end
	search_generation = search_generation + 1
	local generation = search_generation
	vim.schedule(function()
		if generation ~= search_generation or not search_chunks then
			return
		end
		if vim.o.hlsearch and vim.v.hlsearch == 0 then
			clear_search_count()
			return
		end
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local opts = config.messages.search_count
		local mark = { id = 1, virt_text = search_chunks }
		local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
		local start_col, end_col = cursor[2], cursor[2]
		local match_byte_start
		if search_buf and search_buf ~= buf and vim.api.nvim_buf_is_valid(search_buf) then
			vim.api.nvim_buf_clear_namespace(search_buf, search_ns, 0, -1)
		end
		local pattern = vim.fn.getreg("/")
		local ok, match_pos = pcall(vim.fn.searchpos, pattern, "bcnW", 0)
		if not ok or match_pos[1] ~= cursor[1] or match_pos[2] <= 0 then
			vim.api.nvim_buf_clear_namespace(buf, search_ns, 0, -1)
			search_buf = nil
			return
		end
		local match_data = vim.fn.matchstrpos(line, pattern, 0)
		match_byte_start, end_col = match_data[2], match_data[3]
		if match_byte_start < 0 then
			vim.api.nvim_buf_clear_namespace(buf, search_ns, 0, -1)
			search_buf = nil
			return
		end
		start_col = match_byte_start
		if end_col == start_col then
			if cursor[2] ~= start_col or match_byte_start ~= start_col then
				vim.api.nvim_buf_clear_namespace(buf, search_ns, 0, -1)
				search_buf = nil
				return
			end
		elseif cursor[2] < start_col or cursor[2] >= end_col then
			vim.api.nvim_buf_clear_namespace(buf, search_ns, 0, -1)
			search_buf = nil
			return
		end
		if opts.position == "line_end" then
			mark.virt_text_pos = "eol"
		else
			local count_width = 0
			for _, chunk in ipairs(search_chunks) do
				count_width = count_width + vim.fn.strdisplaywidth(chunk[1])
			end
			local match_end = vim.fn.screenpos(win, cursor[1], end_col + 1)
			local match_start = vim.fn.screenpos(win, cursor[1], start_col + 1)
			local win_col = vim.api.nvim_win_get_position(win)[2]
			local right_col = match_end.col + 3
			local right_edge = win_col + vim.api.nvim_win_get_width(win)
			if right_col + count_width - 1 <= right_edge then
				mark.virt_text_pos = "overlay"
				mark.virt_text_win_col = right_col - win_col - 1
			else
				mark.virt_text_pos = "overlay"
				mark.virt_text_win_col = math.max(0, match_start.col - win_col - count_width - 3)
			end
		end
		if search_buf and search_buf ~= buf and vim.api.nvim_buf_is_valid(search_buf) then
			vim.api.nvim_buf_clear_namespace(search_buf, search_ns, 0, -1)
		end
		search_buf = buf
		vim.api.nvim_buf_set_extmark(buf, search_ns, cursor[1] - 1, cursor[2], mark)
	end)
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
	search_ns = vim.api.nvim_create_namespace("cmdline.search_count")
end

function M.teardown()
	cmdline_generation = cmdline_generation + 1
	search_abort_generation = search_abort_generation + 1
	search_aborted = false
	search_watch_pending = false
	search_chunks = nil
	search_generation = search_generation + 1
	if search_buf and vim.api.nvim_buf_is_valid(search_buf) then
		vim.api.nvim_buf_clear_namespace(search_buf, search_ns, 0, -1)
	end
	search_buf = nil
	cmd_win, cmd_buf = close(cmd_win, cmd_buf)
	if mini_cmdheight then
		vim.o.cmdheight = original_cmdheight or 0
		mini_cmdheight = false
		original_cmdheight = nil
	end
	vim.g.ui_cmdline_pos = nil
	current = { active = false, firstc = "", prompt = "", level = 0, pos = 0, chunks = {} }
	command_block = {}
	special_char = nil
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
