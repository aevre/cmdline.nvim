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
assert(dispatch("cmdline_hide", 1, false))
drain()
assert(#vim.api.nvim_list_wins() == baseline)

assert(dispatch("cmdline_show", { { 0, "echo input(" } }, 11, ":", "", 0, 1))
drain()
local nested_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		nested_win = win
	end
end
assert(nested_win)
local function has_title(win, title)
	return vim.inspect(vim.api.nvim_win_get_config(win).title):find(title, 1, true) ~= nil
end
assert(has_title(nested_win, "Command"))
assert(dispatch("cmdline_show", { { 0, "1 + 2" } }, 5, "=", "", 0, 2))
drain()
assert(vim.api.nvim_win_is_valid(nested_win))
assert(has_title(nested_win, "Expression"))
local inner_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nested_win), 0, -1, false)[1]
assert(inner_line:find("", 1, true) and inner_line:find("1 + 2", 1, true), vim.inspect(inner_line))
assert(dispatch("cmdline_pos", 2, 2))
drain()
assert(dispatch("cmdline_hide", 2, false))
drain()
assert(vim.api.nvim_win_is_valid(nested_win))
assert(has_title(nested_win, "Command"))
local parent_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nested_win), 0, -1, false)[1]
assert(parent_line:find("echo input(", 1, true), vim.inspect(parent_line))
assert(dispatch("cmdline_hide", 1, false))
drain()
assert(not vim.api.nvim_win_is_valid(nested_win))

assert(dispatch("cmdline_show", { { 0, "= print(1 + 2)" } }, 15, ":", "", 0, 1))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		nested_win = win
	end
end
assert(has_title(nested_win, "Lua"))
local lua_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nested_win), 0, -1, false)[1]
assert(lua_line:find("", 1, true) and lua_line:find("print(1 + 2)", 1, true), vim.inspect(lua_line))
local lua_buf = vim.api.nvim_win_get_buf(nested_win)
local lua_marks =
	vim.api.nvim_buf_get_extmarks(lua_buf, vim.api.nvim_get_namespaces()["cmdline.nvim"], 0, -1, { details = true })
local highlighted_print, highlighted_number = false, false
for _, mark in ipairs(lua_marks) do
	local text = lua_line:sub(mark[3] + 1, mark[4].end_col)
	highlighted_print = highlighted_print or (text == "print" and mark[4].hl_group == "@function.builtin.lua")
	highlighted_number = highlighted_number or (text == "1" and mark[4].hl_group == "@number.lua")
end
assert(highlighted_print and highlighted_number)
assert(has_title(nested_win, "Lua"))
assert(not lua_line:find(":=", 1, true), vim.inspect(lua_line))
assert(dispatch("cmdline_show", { { 0, "lua print(1 + 2)" } }, 16, ":", "", 0, 1))
drain()
local lua_command_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nested_win), 0, -1, false)[1]
assert(lua_command_line:find("print(1 + 2)", 1, true), vim.inspect(lua_command_line))
lua_buf = vim.api.nvim_win_get_buf(nested_win)
lua_marks =
	vim.api.nvim_buf_get_extmarks(lua_buf, vim.api.nvim_get_namespaces()["cmdline.nvim"], 0, -1, { details = true })
highlighted_print = false
for _, mark in ipairs(lua_marks) do
	local text = lua_command_line:sub(mark[3] + 1, mark[4].end_col)
	highlighted_print = highlighted_print or (text == "print" and mark[4].hl_group == "@function.builtin.lua")
end
assert(highlighted_print)
for _, partial in ipairs({ 'lua print("', 'lua print("hello', 'lua print("hello")' }) do
	assert(dispatch("cmdline_show", { { 0, partial } }, #partial, ":", "", 0, 1))
	drain()
	local partial_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nested_win), 0, -1, false)[1]
	local partial_marks = vim.api.nvim_buf_get_extmarks(
		vim.api.nvim_win_get_buf(nested_win),
		vim.api.nvim_get_namespaces()["cmdline.nvim"],
		0,
		-1,
		{ details = true }
	)
	local function_hl = false
	for _, mark in ipairs(partial_marks) do
		if partial_line:sub(mark[3] + 1, mark[4].end_col) == "print" then
			function_hl = function_hl
				or mark[4].hl_group == "@function.call.lua"
				or mark[4].hl_group == "@function.builtin.lua"
		end
	end
	assert(function_hl, partial)
end
assert(dispatch("cmdline_hide", 1, false))
drain()

local config = require("cmdline.config")
local mini_parent = config.merge()
mini_parent.cmdline.format.cmdline.view = "mini"
require("cmdline.commandline").configure(mini_parent, vim.api.nvim_create_namespace("cmdline.test"))
assert(dispatch("cmdline_show", { { 0, "echo input(" } }, 11, ":", "", 0, 1))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		nested_win = win
	end
end
assert(dispatch("cmdline_show", { { 0, "1 + 2" } }, 5, "=", "", 0, 2))
drain()
local mini_config = vim.api.nvim_win_get_config(nested_win)
assert(mini_config.col == 0 and mini_config.width == vim.o.columns)
assert(mini_config.border == nil or mini_config.border == "none")
local mini_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(nested_win), 0, -1, false)[1]
assert(mini_line:find("", 1, true) and mini_line:find("1 + 2", 1, true), vim.inspect(mini_line))
assert(dispatch("cmdline_hide", 2, false))
drain()
assert(vim.api.nvim_win_get_config(nested_win).width == vim.o.columns)
assert(dispatch("cmdline_hide", 1, false))
drain()
local resolved_config = require("cmdline.config").merge()
require("cmdline.commandline").configure(resolved_config, vim.api.nvim_create_namespace("cmdline.nvim"))

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
local chunk_group
for _, mark in ipairs(cmd_marks) do
	if mark[4].hl_group then
		chunk_group = mark[4].hl_group
	end
end
assert(chunk_group and vim.api.nvim_get_hl(0, { name = chunk_group }).fg == 0xff0000)
local special_text
for _, mark in ipairs(cmd_marks) do
	if mark[4].virt_text then
		special_text = mark[4].virt_text[1][1]
	end
end
assert(special_text == "^V")
assert(dispatch("cmdline_show", { { 0, 'echo "hi"' } }, 8, ":", "", 0, 1))
drain()
local vim_buf = vim.api.nvim_win_get_buf(cmd_win)
local vim_line = vim.api.nvim_buf_get_lines(vim_buf, 0, -1, false)[1]
local vim_marks =
	vim.api.nvim_buf_get_extmarks(vim_buf, vim.api.nvim_get_namespaces()["cmdline.nvim"], 0, -1, { details = true })
local highlighted_echo, highlighted_string = false, false
for _, mark in ipairs(vim_marks) do
	local text = vim_line:sub(mark[3] + 1, mark[4].end_col)
	highlighted_echo = highlighted_echo or (text == "echo" and mark[4].hl_group == "@keyword.vim")
	highlighted_string = highlighted_string or (text == '"hi"' and mark[4].hl_group == "@string.vim")
end
assert(highlighted_echo and highlighted_string)
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
vim.api.nvim_win_set_cursor(0, { 1, 8 })
require("cmdline.commandline").refresh_search_count()
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(#marks == 1 and marks[1][2] == 0, vim.inspect(marks))
vim.api.nvim_win_set_cursor(0, { 1, 12 })
require("cmdline.commandline").refresh_search_count()
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(#marks == 1 and marks[1][2] == 0)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
require("cmdline.commandline").refresh_search_count()
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 1
)
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "foo bar foo baz foo" })
vim.fn.setreg("/", "foo")
for _, col in ipairs({ 8, 16 }) do
	vim.api.nvim_win_set_cursor(0, { 1, col })
	require("cmdline.commandline").refresh_search_count()
	drain()
	marks = vim.api.nvim_buf_get_extmarks(
		source_buf,
		vim.api.nvim_get_namespaces()["cmdline.search_count"],
		0,
		-1,
		{ details = true }
	)
	assert(#marks == 1 and marks[1][2] == 0)
end
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
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "中foo foo" })
vim.fn.setreg("/", "foo\\zs")
vim.v.hlsearch = 1
vim.api.nvim_win_set_cursor(0, { 1, 6 })
assert(dispatch("msg_show", "search_count", { { 0, " [1/2]  " } }, false, false, false, 0, "search"))
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(#marks == 1 and marks[1][3] == 6)
vim.api.nvim_win_set_cursor(0, { 1, 5 })
require("cmdline.commandline").refresh_search_count()
drain()
assert(
	#vim.api.nvim_buf_get_extmarks(source_buf, vim.api.nvim_get_namespaces()["cmdline.search_count"], 0, -1, {}) == 0
)
vim.fn.setreg("/", "foo")
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "中foo foo" })
vim.api.nvim_win_set_cursor(0, { 1, 3 })
assert(dispatch("msg_show", "search_count", { { 0, " [1/2]  " } }, false, false, false, 0, "search"))
drain()
marks = vim.api.nvim_buf_get_extmarks(
	source_buf,
	vim.api.nvim_get_namespaces()["cmdline.search_count"],
	0,
	-1,
	{ details = true }
)
assert(#marks == 1 and marks[1][3] == 3)
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
local popup_config = require("cmdline.config").merge()
require("cmdline.popupmenu").configure(popup_config)
local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(cmd_win), 0, -1, false)
assert(lines[1]:find("print('中文')", 1, true) and not lines[1]:find("lua", 1, true))
assert(dispatch("popupmenu_show", { { "one", "f" }, { "two", "Unknown" }, { "three", "" } }, 0, 0, 0, -1))
drain()
assert(#vim.api.nvim_list_wins() == baseline + 2)
local kind_icon_lines, kind_icon_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).zindex == 201 then
		kind_icon_win = win
		kind_icon_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	end
end
assert(
	kind_icon_lines
		and kind_icon_lines[1] == "ƒ one"
		and kind_icon_lines[2] == "󰘦 two"
		and kind_icon_lines[3] == "󰘦 three"
)
assert(popup_config.popupmenu.kind_icons.f == "ƒ")
assert(vim.api.nvim_win_get_config(kind_icon_win).border[1] == "╭")
assert(vim.api.nvim_win_get_width(kind_icon_win) >= vim.fn.strdisplaywidth("ƒ one"))
local selected_marks = vim.api.nvim_buf_get_extmarks(
	vim.api.nvim_win_get_buf(kind_icon_win),
	vim.api.nvim_get_namespaces()["cmdline.popupmenu"],
	0,
	-1,
	{ details = true }
)
assert(#selected_marks == 1 and selected_marks[1][4].hl_group == "PmenuSel")
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" then
		assert(opts.win == cmd_win)
	end
end
assert(dispatch("popupmenu_select", 1))
drain()
local popup_without_icons = require("cmdline.config").merge({
	popupmenu = { kind_icons = false, border = "single" },
})
require("cmdline.popupmenu").configure(popup_without_icons)
local completion_items = {}
for i = 1, 20 do
	completion_items[i] = { "item" .. i }
end
assert(dispatch("popupmenu_show", completion_items, 0, 0, 0, -1))
drain()
local popup_lines
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	end
end
assert(popup_lines and popup_lines[1] == "item1" and popup_lines[12] == "item12")
assert(dispatch("popupmenu_select", 7))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	end
end
assert(popup_lines and popup_lines[1] == "item1")
assert(dispatch("popupmenu_select", 11))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
		assert(opts.height == 12)
	end
end
assert(popup_lines and #popup_lines == 12 and popup_lines[1] == "item3" and popup_lines[10] == "item12")
assert(dispatch("popupmenu_select", 4))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	end
end
assert(popup_lines and popup_lines[1] == "item3")
assert(dispatch("popupmenu_select", 3))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	end
end
assert(popup_lines and popup_lines[1] == "item2")
assert(dispatch("popupmenu_select", 2))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "win" and opts.zindex == 201 then
		popup_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
		assert(opts.border[1] == "┌")
	end
end
assert(popup_lines and popup_lines[1] == "item1")
assert(dispatch("cmdline_hide"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)
cmdline.setup()

local error_hl = vim.api.nvim_get_hl_id_by_name("ErrorMsg")
assert(dispatch("msg_show", "emsg", { { 0, "first\nsecond", error_hl } }, false, true, false, 7))
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
assert(dispatch("msg_show", "echo", { { 0, "second" } }, false, true, false, 10))
assert(dispatch("msg_show", "echo", { { 0, " tail" } }, false, true, true, 8))
assert(dispatch("msg_show", "echo", { { 0, "replacement" } }, true, true, false, 9))
assert(dispatch("msg_show", "progress", { { 0, "updated first" } }, false, false, false, 7))
drain()
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		notification_buf = vim.api.nvim_win_get_buf(win)
	end
end
local updated_lines = vim.api.nvim_buf_get_lines(notification_buf, 0, -1, false)
assert(table.concat(updated_lines, "\n") == "updated first\nreplacement", vim.inspect(updated_lines))
assert(dispatch("msg_clear"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)
assert(dispatch("msg_show", "shell_err", { { 0, "shell stderr" } }, false, false, false, 14))
assert(dispatch("msg_show", "shell_out", { { 0, "shell stdout" } }, false, false, false, 15))
assert(dispatch("msg_show", "shell_ret", { { 0, "shell status" } }, false, false, false, 16))
assert(dispatch("msg_show", "shell_cmd", { { 0, "shell command" } }, false, false, false, 17) == nil)
drain()
local shell_error_visible, shell_stdout_visible, shell_status_visible = false, false, false
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	local text = table.concat(lines, "\n")
	shell_error_visible = shell_error_visible or text:find("shell stderr", 1, true) ~= nil
	shell_stdout_visible = shell_stdout_visible or text:find("shell stdout", 1, true) ~= nil
	shell_status_visible = shell_status_visible or text:find("shell status", 1, true) ~= nil
end
assert(shell_error_visible and shell_stdout_visible and shell_status_visible)
assert(dispatch("msg_clear"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)
assert(dispatch("msg_show", "confirm", { { 0, "Save changes?" } }, false, false, false, 11))
drain()
local confirm_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		confirm_win = win
	end
end
assert(confirm_win)
local confirm_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(confirm_win), 0, -1, false)
assert(table.concat(confirm_lines, "\n"):find("Save changes?", 1, true))
assert(dispatch("msg_clear"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)
assert(dispatch("msg_show", "future_kind", { { 0, "unknown message" } }, false, false, false, 12))
drain()
local unknown_visible = false
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
	unknown_visible = unknown_visible or table.concat(lines, "\n"):find("unknown message", 1, true) ~= nil
end
assert(unknown_visible)
assert(dispatch("msg_clear"))
drain()
cmdline.setup({ messages = { enabled = false } })
assert(not dispatch("msg_show", "echo", { { 0, "not consumed" } }, false, false, false, 13))
cmdline.setup({ messages = { enabled = true } })
local previous = vim.api.nvim_get_current_win()
assert(dispatch("msg_history_show", {
	{ "echo", { { 0, "old\nline" } }, false },
	{ "echon", { { 0, " continued" } }, true },
	{ "echo", { { 0, "new" } }, false },
}))
drain()
local history_buf = vim.api.nvim_get_current_buf()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(history_buf, 0, -1, false), { "new", "old", "line continued" }))
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
