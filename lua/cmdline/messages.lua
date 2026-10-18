local M = {}

function M.new(chunks_text, close)
	local history_buf
	local history_win
	local history_prev_win

	local function valid_win(win)
		return win and vim.api.nvim_win_is_valid(win)
	end

	local function close_history()
		local previous = history_prev_win
		history_win, history_buf = close(history_win, history_buf)
		history_prev_win = nil
		if valid_win(previous) then
			pcall(vim.api.nvim_set_current_win, previous)
		end
	end

	local function show_history(entries, config)
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

	return close_history, show_history
end

return M
