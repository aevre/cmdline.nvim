local M = {}
local ui = require("cmdline.ui")
local valid_win, close, chunks_text = ui.valid_win, ui.close, ui.chunks_text
local config
local history_buf
local history_win
local history_prev_win

---@return nil Close history and restore the previously active window.
local function close_history()
	local previous = history_prev_win
	history_win, history_buf = close(history_win, history_buf)
	history_prev_win = nil
	if valid_win(previous) then
		pcall(vim.api.nvim_set_current_win, previous)
	end
end

---@param entries cmdline.HistoryEntry[] UI2 message history entries.
local function show_history(entries)
	close_history()
	local messages = {}
	for _, entry in ipairs(entries) do
		local entry_lines = chunks_text(entry[2] or {})
		if entry[3] and #messages > 0 then
			local previous = messages[#messages]
			previous[#previous] = previous[#previous] .. entry_lines[1]
			for index = 2, #entry_lines do
				previous[#previous + 1] = entry_lines[index]
			end
		elseif #entry_lines > 1 or entry_lines[1] ~= "" then
			messages[#messages + 1] = entry_lines
		end
	end
	local lines = {}
	for index = #messages, 1, -1 do
		vim.list_extend(lines, messages[index])
	end
	if #lines == 0 then
		return
	end

	history_prev_win = vim.api.nvim_get_current_win()
	history_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = history_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = history_buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = history_buf })
	vim.api.nvim_buf_set_lines(history_buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = history_buf })
	vim.keymap.set("n", "q", close_history, { buffer = history_buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Esc>", close_history, { buffer = history_buf, silent = true, nowait = true })

	local width = math.max(40, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.8)))
	local height = math.max(1, math.min(#lines, vim.o.lines - 4))
	history_win = vim.api.nvim_open_win(history_buf, true, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
		border = config.cmdline.opts.border,
		title = " Messages ",
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

local notification_buf, notification_win
local notification_timer
local notification_ns = vim.api.nvim_create_namespace("cmdline.messages")
local visible_messages = {}
local persistent_notification = false
local generation = 0

local function clear_notification()
	if notification_timer then
		notification_timer:stop()
		notification_timer:close()
		notification_timer = nil
	end
	notification_win, notification_buf = close(notification_win, notification_buf)
	visible_messages = {}
	persistent_notification = false
end

local function render_notifications()
	if notification_timer then
		notification_timer:stop()
		notification_timer:close()
		notification_timer = nil
	end
	notification_win, notification_buf = close(notification_win, notification_buf)
	local chunks = {}
	for index, message in ipairs(visible_messages) do
		if index > 1 then
			chunks[#chunks + 1] = { 0, "\n" }
		end
		vim.list_extend(chunks, message.chunks)
	end
	if #chunks == 0 then
		return
	end
	local lines = chunks_text(chunks)
	local width = vim.o.columns
	local height = 0
	for _, line in ipairs(lines) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
	end
	height = math.min(height, math.max(1, math.floor(vim.o.lines / 2)))
	notification_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(notification_buf, 0, -1, false, lines)
	vim.bo[notification_buf].modifiable = false
	vim.bo[notification_buf].bufhidden = "wipe"
	notification_win = vim.api.nvim_open_win(notification_buf, false, {
		relative = "editor",
		row = math.max(0, vim.o.lines - vim.o.cmdheight - height),
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 200,
	})
	vim.wo[notification_win].wrap = true
	vim.wo[notification_win].winhighlight = "Normal:MsgArea,EndOfBuffer:MsgArea"
	vim.wo[notification_win].winblend = 0
	local row, col = 0, 0
	for _, chunk in ipairs(chunks) do
		local parts = vim.split(chunk[2], "\n", { plain = true })
		for i, part in ipairs(parts) do
			if i > 1 then
				row, col = row + 1, 0
			end
			if chunk[3] and chunk[3] > 0 and #part > 0 then
				vim.api.nvim_buf_set_extmark(notification_buf, notification_ns, row, col, {
					end_col = col + #part,
					hl_group = chunk[3],
				})
			end
			col = col + #part
		end
	end
	if not persistent_notification then
		notification_timer = vim.defer_fn(function()
			notification_timer = nil
			clear_notification()
		end, 4000)
	end
end

local forwarding_message = false

---@param chunks cmdline.Content Message chunks to route.
---@param replace_last boolean? Replace the most recent visible message.
---@param append boolean? Append chunks to the most recent visible message.
---@param id integer|string|nil Replace a visible message with this id.
local function update_notification(chunks, replace_last, append, id, persistent)
	persistent_notification = persistent or false
	local index
	if id ~= nil then
		for i, message in ipairs(visible_messages) do
			if message.id == id then
				index = i
				break
			end
		end
	end
	if index then
		visible_messages[index] = { chunks = chunks, id = id, append = visible_messages[index].append }
	elseif append and #visible_messages > 0 then
		vim.list_extend(visible_messages[#visible_messages].chunks, chunks)
	elseif replace_last and #visible_messages > 0 then
		visible_messages[#visible_messages] = { chunks = chunks, id = id }
	else
		visible_messages[#visible_messages + 1] = { chunks = chunks, id = id, append = append }
	end
	render_notifications()
end

---@param chunks cmdline.Content Message chunks to route.
---@param level integer Notification severity.
---@param title string? Optional notification title.
---@param replace_last boolean? Replace the most recent visible message.
---@param append boolean? Append chunks to the most recent visible message.
---@param id integer|string|nil Replace a visible message with this id.
local function notify_message(chunks, level, title, replace_last, append, id)
	local text = table.concat(chunks_text(chunks), "\n")
	if text ~= "" then
		local source = type(vim.notify) == "function" and debug.getinfo(vim.notify, "S").source or ""
		if source == "vim/_core/editor" or source == "@vim/_editor.lua" then
			update_notification(chunks, replace_last, append, id)
			return
		end
		forwarding_message = true
		local ok, err = pcall(vim.notify, text, level, { title = title or "Messages" })
		forwarding_message = false
		if not ok then
			error(err)
		end
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
		"progress",
		"list_cmd",
		"shell_out",
		"shell_err",
		"shell_ret",
		"emsg",
		"echoerr",
		"lua_error",
		"rpc_error",
		"wmsg",
		"completion",
		"quickfix",
		"search_cmd",
		"shell_cmd",
		"undo",
		"verbose",
		"wildlist",
	}, kind)
end

local function is_search_message(kind, chunks)
	if kind ~= "wmsg" and kind ~= "emsg" then
		return false
	end
	local text = table.concat(chunks_text(chunks), "\n")
	return text:match("E486") ~= nil
		or text:lower():match("search hit") ~= nil
		or text:lower():match("pattern not found") ~= nil
end

---@param event string UI2 event name.
---@param ... any Event payload for the selected message event.
---@return boolean? Whether this module handled the event.
function M.handle(event, ...)
	local args = { ... }
	if event == "msg_show" then
		if not config.messages.enabled then
			return
		end
		local kind, chunks = args[1], args[2]
		local replace_last, append, id = args[3], args[5], args[6]
		if kind == "shell_cmd" then
			return
		end
		if kind ~= "search_count" and kind ~= "confirm" and not should_notify_message(kind) then
			kind = ""
		end
		if kind == "search_count" then
			return
		end
		-- shortcut: guards synchronous echo fallbacks; deferred echo providers need explicit routing.
		if forwarding_message then
			local scheduled_generation = generation
			vim.schedule(function()
				if scheduled_generation == generation and config.messages.enabled then
					update_notification(chunks, replace_last, append, id)
				end
			end)
			return true
		end
		if kind == "confirm" then
			local scheduled_generation = generation
			vim.schedule(function()
				if scheduled_generation == generation and config.messages.enabled then
					update_notification(chunks, replace_last, append, id, true)
				end
			end)
			return true
		end
		if
			(config.messages.view_search and config.cmdline.enabled and is_search_message(kind, chunks))
			or kind == ""
			or should_notify_message(kind)
		then
			local scheduled_generation = generation
			vim.schedule(function()
				if scheduled_generation == generation and config.messages.enabled then
					notify_message(
						chunks,
						message_level(kind),
						kind == "lua_print" and "Lua" or nil,
						replace_last,
						append,
						id
					)
				end
			end)
			return true
		end
	elseif event == "msg_history_show" then
		if not config.messages.enabled then
			return
		end
		local scheduled_generation = generation
		vim.schedule(function()
			if scheduled_generation == generation and config.messages.enabled then
				show_history(args[1] or {})
			end
		end)
		return true
	elseif event == "msg_clear" or event == "msg_history_clear" then
		if not config.messages.enabled then
			return
		end
		if event == "msg_history_clear" then
			vim.schedule(close_history)
		else
			vim.schedule(clear_notification)
		end
		return true
	end
end

---@param opts cmdline.ResolvedConfig Complete merged plugin configuration.
function M.configure(opts)
	config = opts
end

function M.close()
	generation = generation + 1
	close_history()
	clear_notification()
end

M.close_history = close_history
return M
