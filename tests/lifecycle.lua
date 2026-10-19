vim.opt.runtimepath:prepend(vim.fn.getcwd())

local original_attach = vim.ui_attach
local attach_count, dispatch = 0
vim.ui_attach = function(_, _, callback)
	attach_count = attach_count + 1
	dispatch = callback
end
local baseline = #vim.api.nvim_list_wins()
local cmdline = require("cmdline")
assert(attach_count == 0 and #vim.api.nvim_list_wins() == baseline)
cmdline.close_history()
assert(cmdline.setup() == cmdline)
cmdline.setup()
assert(attach_count == 1)
assert(#vim.api.nvim_get_autocmds({ group = "cmdline.nvim" }) == 4)

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
assert(dispatch("cmdline_hide"))
drain()
assert(vim.o.cmdheight == 0 and vim.g.ui_cmdline_pos == nil)

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
assert(dispatch("cmdline_hide"))
drain()
assert(#vim.api.nvim_list_wins() == baseline)

assert(dispatch("msg_show", "echo", { { 0, "first\nsecond" } }))
drain()
assert(#vim.api.nvim_list_wins() == baseline + 1)
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
vim.ui_attach = original_attach
print("cmdline.nvim lifecycle: ok")
