vim.opt.runtimepath:prepend(vim.fn.getcwd())

local original_attach, original_detach = vim.ui_attach, vim.ui_detach
local attach_count, detach_count, dispatch = 0, 0
vim.ui_attach = function(_, _, callback)
	attach_count = attach_count + 1
	dispatch = callback
end
vim.ui_detach = function()
	detach_count = detach_count + 1
end
vim.o.cmdheight = 2
local baseline = #vim.api.nvim_list_wins()
local cmdline = require("cmdline")
assert(attach_count == 0 and #vim.api.nvim_list_wins() == baseline)
cmdline.close_history()
assert(cmdline.setup() == cmdline)
cmdline.setup()
assert(attach_count == 1)
assert(#vim.api.nvim_get_autocmds({ group = "cmdline.nvim" }) >= 3)

local function drain()
	local done = false
	vim.schedule(function()
		done = true
	end)
	assert(vim.wait(500, function()
		return done
	end))
end

assert(dispatch("cmdline_show", { { 0, "stale" } }, 5, ":", "", 0, 1))
assert(dispatch("cmdline_hide"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)

assert(dispatch("cmdline_show", { { 0, "search" } }, 6, "/", "", 0, 1))
drain()
assert(vim.o.cmdheight == 1)
assert(#vim.api.nvim_list_wins() == baseline + 1)
local cmd_buf
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		cmd_win = win
		cmd_buf = vim.api.nvim_win_get_buf(win)
	end
end
assert(dispatch("cmdline_show", { { { foreground = 0xff0000 }, "abc", 77 } }, 1, "", ">", 0, 1))
assert(dispatch("cmdline_special_char", string.char(22), true, 1))
assert(dispatch("cmdline_show", { { { foreground = 0xff0000 }, "abc", 77 } }, 1, "", ">", 0, 1))
assert(dispatch("cmdline_block_show", { { { { bold = true }, "function Foo()", 78 } } }))
assert(dispatch("cmdline_block_append", { { { italic = true }, "  echo 'foo'", 79 } }))
drain()
local rendered = vim.api.nvim_buf_get_lines(cmd_buf, 0, -1, false)
assert(rendered[1] == "function Foo()" and rendered[2] == "  echo 'foo'")
assert(rendered[3] == ">abc")
local cmd_marks =
	vim.api.nvim_buf_get_extmarks(cmd_buf, vim.api.nvim_get_namespaces()["cmdline.nvim"], 0, -1, { details = true })
local has_special, has_chunk_hl = false, false
for _, mark in ipairs(cmd_marks) do
	local details = mark[4]
	has_special = has_special or details.virt_text ~= nil
	has_chunk_hl = has_chunk_hl or details.hl_group ~= nil
end
assert(has_special and has_chunk_hl)
local special_text
for _, mark in ipairs(cmd_marks) do
	if mark[4].virt_text then
		special_text = mark[4].virt_text[1][1]
	end
end
assert(special_text == "^V")
assert(dispatch("cmdline_show", { { 0, "abcd" } }, 4, "", ">", 0, 1))
drain()
cmd_marks =
	vim.api.nvim_buf_get_extmarks(cmd_buf, vim.api.nvim_get_namespaces()["cmdline.nvim"], 0, -1, { details = true })
for _, mark in ipairs(cmd_marks) do
	assert(mark[4].virt_text == nil)
end
assert(dispatch("cmdline_block_hide"))
drain()
assert(not vim.api.nvim_win_is_valid(cmd_win))
assert(dispatch("cmdline_show", { { 0, "search" } }, 6, "/", "", 0, 1))
drain()
local source_buf = vim.api.nvim_get_current_buf()
vim.o.hlsearch = true
vim.fn.setreg("/", "foo")
vim.v.hlsearch = 1
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "foo bar foo", "another foo" })
vim.api.nvim_win_set_cursor(0, { 2, 8 })
-- UI callbacks may run directly from a fast event.
local fast_result
local timer = vim.uv.new_timer()
timer:start(0, 0, function()
	fast_result = {
		pcall(function()
			assert(vim.in_fast_event())
			assert(dispatch("msg_show", "search_count", { { 0, " /foo" }, { 0, " [3/10]  " } }, false))
		end),
	}
	timer:close()
end)
assert(vim.wait(500, function()
	return fast_result ~= nil
end))
assert(fast_result[1], fast_result[2])
drain()
local marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
local found_search_count = false
for _, mark in ipairs(marks) do
	local details = mark[4]
	if
		details.virt_text
		and table.concat({ details.virt_text[1][1], details.virt_text[2][1], details.virt_text[3][1] }) == "[3/10]"
	then
		found_search_count = true
	end
end
assert(found_search_count and marks[1][2] == 1 and marks[1][4].virt_text_pos == "win_col")
local virtual_text = marks[1][4].virt_text
assert(table.concat({ virtual_text[1][1], virtual_text[2][1], virtual_text[3][1] }) == "[3/10]")
assert(virtual_text[1][2] == "CmdlineSearchCount" and virtual_text[2][2] == "CmdlineSearchCountCurrent")
local count_hl = vim.api.nvim_get_hl(0, { name = "CmdlineSearchCount" })
local current_hl = vim.api.nvim_get_hl(0, { name = "CmdlineSearchCountCurrent" })
assert(count_hl.fg and not count_hl.bg and not count_hl.italic and count_hl.bold)
assert(current_hl.fg and not current_hl.bg and not current_hl.italic and current_hl.bold)
assert(dispatch("cmdline_hide", 1, true))
-- A final search count can arrive after the aborted command line was hidden.
assert(dispatch("msg_show", "search_count", { { 0, " [3/10]  " } }, false))
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 0
)
assert(vim.o.cmdheight == 0 and vim.g.ui_cmdline_pos == nil)
vim.fn.setreg("/", "foo")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
assert(dispatch("msg_show", "search_count", { { 0, " W [1/10]  " } }, false, false, false, 0, "search"))
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(
	#marks == 1
		and marks[1][2] == 0
		and table.concat({ marks[1][4].virt_text[1][1], marks[1][4].virt_text[2][1], marks[1][4].virt_text[3][1] }) == "[1/10]"
		and marks[1][4].virt_text_pos == "win_col"
		and marks[1][4].virt_text_win_col == 6
)
vim.api.nvim_win_set_cursor(0, { 1, 4 })
require("cmdline.commandline").refresh_search_count()
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 0
)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
require("cmdline.commandline").refresh_search_count()
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 1
)
local edge_col = vim.api.nvim_win_get_width(0) - 4
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { string.rep("x", edge_col) .. "foo" })
vim.fn.setreg("/", "foo")
vim.api.nvim_win_set_cursor(0, { 1, edge_col })
assert(dispatch("msg_show", "search_count", { { 0, " [1/10]  " } }, false, false, false, 0, "search"))
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(#marks == 1 and marks[1][4].virt_text_win_col < edge_col)
assert(dispatch("cmdline_show", { { 0, "command" } }, 4, ":", "", 0, 1))
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 0
)
assert(dispatch("cmdline_hide"))
drain()

assert(dispatch("cmdline_show", { { 0, "lua print('中文')" } }, 19, ":", "", 0, 1))
drain()
local cmd_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		cmd_win = win
	end
end
assert(cmd_win and vim.wo[cmd_win].virtualedit == "onemore")
local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(cmd_win), 0, -1, false)
assert(lines[1]:find("print('中文')", 1, true) and not lines[1]:find("lua", 1, true))
assert(dispatch("popupmenu_show", { { "one" }, { "two" } }, 0, 0, 0, -1))
drain()
assert(#vim.api.nvim_list_wins() == baseline + 2)
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" then
		assert(opts.win == cmd_win)
	end
end
assert(dispatch("popupmenu_select", 1))
drain()
local completion_items = {}
for i = 1, 13 do
	completion_items[i] = { "item" .. i }
end
assert(dispatch("popupmenu_show", completion_items, 0, 0, 0, -1))
drain()
assert(dispatch("popupmenu_select", 12))
drain()
local popup_lines
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
		assert(opts.height == 12)
	end
end
assert(popup_lines and #popup_lines == 12 and popup_lines[1] == "  item2" and popup_lines[12] == "> item13")
assert(dispatch("cmdline_hide"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)

local error_hl = vim.api.nvim_get_hl_id_by_name("ErrorMsg")
assert(dispatch("msg_show", "emsg", { { 0, "first\nsecond", error_hl } }))
drain()
assert(#vim.api.nvim_list_wins() == baseline + 1)
local notification_buf
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local buf = vim.api.nvim_win_get_buf(win)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if table.concat(lines, "\n") == "first\nsecond" then
		notification_buf = buf
	end
end
assert(notification_buf)
local notification_marks = vim.api.nvim_buf_get_extmarks(
	notification_buf,
	vim.api.nvim_get_namespaces()["cmdline.messages"],
	0,
	-1,
	{ details = true }
)
assert(#notification_marks == 2 and notification_marks[1][4].hl_group == "ErrorMsg")
assert(dispatch("msg_clear"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)
local previous = vim.api.nvim_get_current_win()
assert(dispatch("msg_history_show", { { "echo", { { 0, "history" } } } }))
drain()
local history_buf = vim.api.nvim_get_current_buf()
local keys = vim.api.nvim_buf_get_keymap(history_buf, "n")
local close
for _, key in ipairs(keys) do
	if key.lhs == "q" then
		close = key.callback
	end
end
assert(type(close) == "function")
close()
assert(vim.api.nvim_get_current_win() == previous)
assert(not vim.api.nvim_buf_is_valid(history_buf))
cmdline.setup({ messages = { search_count = { position = "line_end" } } })
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "foo" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
assert(dispatch("msg_show", "search_count", { { 0, " [1/10]  " } }, false, false, false, 0, "search"))
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(#marks == 1 and marks[1][4].virt_text_pos == "eol")
-- Clearing highlights must remove the count without moving the cursor.
vim.cmd.nohlsearch()
assert(vim.wait(500, function()
	return #vim.api.nvim_buf_get_extmarks(
			source_buf,
			vim.api.nvim_get_namespaces()["cmdline.search_count"],
			0,
			-1,
			{}
		) == 0
end))
require("cmdline.commandline").refresh_search_count()
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 0
)
-- A subsequent accepted search can display a new count.
vim.v.hlsearch = 1
assert(dispatch("cmdline_show", { { 0, "foo" } }, 3, "?", "", 0, 1))
assert(dispatch("cmdline_hide", 1, false))
assert(dispatch("msg_show", "search_count", { { 0, " [1/10]  " } }, false))
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 1
)
assert(dispatch("cmdline_show", { { 0, "search" } }, 6, "/", "", 0, 1))
assert(dispatch("popupmenu_show", { { "one" }, { "two" } }, 0, 0, 0, -1))
drain()
assert(#vim.api.nvim_list_wins() == baseline + 2)
assert(cmdline.setup({ cmdline = { enabled = false }, messages = { enabled = false } }) == cmdline)
drain()
assert(detach_count == 1 and vim.o.cmdheight == 2)
assert(not pcall(vim.api.nvim_get_autocmds, { group = "cmdline.nvim" }))
assert(#vim.api.nvim_list_wins() == baseline and vim.g.ui_cmdline_pos == nil)
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 0
)
cmdline.setup()
assert(attach_count == 2)
cmdline.disable()
assert(detach_count == 2 and vim.o.cmdheight == 2)
vim.ui_attach, vim.ui_detach = original_attach, original_detach
print("cmdline.nvim lifecycle: ok")
