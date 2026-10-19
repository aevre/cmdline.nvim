local M = {}

---@param win integer? Window handle to validate.
---@return boolean Whether the handle refers to a valid window.
function M.valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---@param win integer? Window to close when valid.
---@param buf integer? Buffer to delete when valid.
---@return integer? win Always nil after cleanup.
---@return integer? buf Always nil after cleanup.
function M.close(win, buf)
	if M.valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	return nil, nil
end

---@param chunks cmdline.Content? UI2 chunks to concatenate, if present.
---@return string[] lines Text split at embedded line breaks.
function M.chunks_text(chunks)
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

---@param buf integer Buffer whose contents will be replaced.
---@param lines string[] Lines to write; an empty list produces one empty line.
---@return nil
function M.set_lines(buf, lines)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "" })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

return M
