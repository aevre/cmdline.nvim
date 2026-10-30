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
local confirmation_buf, confirmation_win
local confirmation_chunks, confirmation_prompt
local notification_timer
local notification_ns = vim.api.nvim_create_namespace("cmdline.messages")
local visible_messages = {}
local persistent_notification = false
local generation = 0
local forwarded_messages = {}
local pending_messages = {}
local flush_scheduled = false
local next_notification_id = 0

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

local function close_confirmation()
	confirmation_win, confirmation_buf = close(confirmation_win, confirmation_buf)
end

local function clear_confirmation()
	confirmation_chunks, confirmation_prompt = nil, nil
	close_confirmation()
end

local function render_confirmation()
	confirmation_win, confirmation_buf = close(confirmation_win, confirmation_buf)
	local lines = chunks_text(confirmation_chunks)
	if confirmation_prompt and confirmation_prompt ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = confirmation_prompt
	end
	local width = math.max(1, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.8)))
	local height = 0
	for _, line in ipairs(lines) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
	end
	height = math.max(1, math.min(height, vim.o.lines - 4))
	confirmation_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(confirmation_buf, 0, -1, false, lines)
	vim.bo[confirmation_buf].modifiable = false
	vim.bo[confirmation_buf].bufhidden = "wipe"
	confirmation_win = vim.api.nvim_open_win(confirmation_buf, false, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
		border = config.cmdline.opts.border,
		title = " Confirm ",
		title_pos = "center",
		focusable = false,
		zindex = 190,
	})
	vim.wo[confirmation_win].wrap = true
	vim.wo[confirmation_win].winhighlight = "Normal:CmdlineNormal,FloatBorder:CmdlineBorder,FloatTitle:CmdlineTitle"
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

local function merge_message(messages, chunks, replace_last, append, id)
	local index
	if id ~= nil then
		for i, message in ipairs(messages) do
			if message.id == id then
				index = i
				break
			end
		end
	end
	local matching_id = index ~= nil
	if not index and (append or replace_last) and #messages > 0 then
		index = #messages
	end
	local message = index and messages[index]
	if not message then
		next_notification_id = next_notification_id + 1
		message = { notification_id = "cmdline.nvim:message:" .. next_notification_id }
		messages[#messages + 1] = message
	end
	if append and not matching_id and message.chunks then
		vim.list_extend(message.chunks, vim.deepcopy(chunks))
	else
		message.chunks = vim.deepcopy(chunks)
	end
	if not append or matching_id then
		message.id = id
	end
	return message
end

local function update_notification(chunks, replace_last, append, id, persistent)
	persistent_notification = persistent or false
	merge_message(visible_messages, chunks, replace_last, append, id)
	render_notifications()
end

local function notify_message(message)
	local text = table.concat(chunks_text(message.chunks), "\n")
	if text ~= "" then
		forwarding_message = true
		local ok, err = pcall(vim.notify, text, message.level, {
			title = message.title or "Messages",
			id = message.notification_id,
		})
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
---@return boolean?, boolean? Whether the event was handled and whether the next prompt should be hidden.
function M.handle(event, ...)
	local args = { ... }
	if event == "cmdline_show" and confirmation_chunks then
		local prompt = args[4]
		if not confirmation_prompt and prompt and prompt ~= "" then
			confirmation_prompt = prompt
			return false, true
		end
	elseif event == "msg_show" then
		if not config.messages.enabled then
			return
		end
		local kind, chunks = args[1], args[2]
		local replace_last, append, id = args[3], args[5], args[6]
		if kind == "search_cmd" then
			return
		end
		if kind == "shell_cmd" then
			local previous = forwarded_messages[#forwarded_messages]
			forwarded_messages = previous and { { notification_id = previous.notification_id } } or {}
			return
		end
		if kind ~= "search_count" and kind ~= "confirm" and not should_notify_message(kind) then
			kind = ""
		end
		if kind == "search_count" then
			return
		end
		if not append and not replace_last and table.concat(chunks_text(chunks), "\n"):match("%S") == nil then
			return true
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
			pending_messages = {}
			confirmation_chunks, confirmation_prompt = chunks, nil
			local scheduled_generation = generation
			vim.schedule(function()
				if scheduled_generation == generation and config.messages.enabled and confirmation_chunks then
					clear_notification()
					render_confirmation()
				end
			end)
			return true
		end
		if
			(config.messages.view_search and config.cmdline.enabled and is_search_message(kind, chunks))
			or kind == ""
			or should_notify_message(kind)
		then
			pending_messages[#pending_messages + 1] = { kind, chunks, replace_last, append, id }
			if not flush_scheduled then
				flush_scheduled = true
				local scheduled_generation = generation
				vim.schedule(function()
					if scheduled_generation ~= generation or not config.messages.enabled then
						return
					end
					local pending = pending_messages
					pending_messages, flush_scheduled = {}, false
					local source = type(vim.notify) == "function" and debug.getinfo(vim.notify, "S").source or ""
					local native = source == "vim/_core/editor" or source == "@vim/_editor.lua"
					local dirty = {}
					for _, item in ipairs(pending) do
						if native then
							update_notification(item[2], item[3], item[4], item[5])
						else
							local message = merge_message(forwarded_messages, item[2], item[3], item[4], item[5])
							message.level = message_level(item[1])
							message.title = item[1] == "lua_print" and "Lua" or nil
							dirty[message] = true
						end
					end
					for _, message in ipairs(forwarded_messages) do
						if dirty[message] then
							notify_message(message)
						end
					end
				end)
			end
			return true
		end
	elseif event == "cmdline_hide" and confirmation_chunks then
		generation = generation + 1
		confirmation_chunks, confirmation_prompt = nil, nil
		vim.schedule(close_confirmation)
		return true
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
			generation = generation + 1
			pending_messages, forwarded_messages, flush_scheduled = {}, {}, false
			vim.schedule(function()
				clear_notification()
				clear_confirmation()
			end)
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
	pending_messages, forwarded_messages, flush_scheduled = {}, {}, false
	close_history()
	clear_notification()
	clear_confirmation()
end

M.close_history = close_history
return M
