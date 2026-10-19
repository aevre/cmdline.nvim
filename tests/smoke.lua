vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cmdline = require("cmdline")
assert(type(cmdline.setup) == "function")
cmdline.setup({ cmdline = { enabled = false }, messages = { enabled = false } })

assert(vim.deep_equal(vim.deepcopy({ "/", "?" }), { "/", "?" }))

local extensions = require("cmdline.extensions")
local config = require("cmdline.config").merge({
	cmdline = {
		extensions = {
			{ name = "file", prompt = { "already%s+open", "filename" } },
			function(state)
				return state.firstc == ":" and state.lines[1]:match("^Git") and "git" or nil
			end,
		},
	},
})
assert(extensions.resolve(config, { firstc = ":", chunks = {}, prompt = "" }, { "Git status" }) == "git")
assert(extensions.resolve(config, { firstc = ":", chunks = {}, prompt = "" }, { ":help foo" }) == "help")
assert(extensions.resolve(config, { firstc = ":", chunks = {}, prompt = "" }, { ":lua print(1)" }) == "lua")
assert(extensions.resolve(config, { firstc = "", chunks = {}, prompt = "File already open: " }, { "" }) == "file")
assert(extensions.resolve(config, { firstc = "", chunks = {}, prompt = "Enter value: " }, { "" }) == "input")
local native_notify = vim.notify
cmdline.setup()
local function visible(text)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
			if table.concat(lines, "\n"):find(text, 1, true) then
				return true
			end
		end
	end
	return false
end
vim.notify("native notification")
assert(vim.wait(500, function()
	return visible("native notification")
end))
assert(vim.notify == native_notify)
for _, win in ipairs(vim.api.nvim_list_wins()) do
	local opts = vim.api.nvim_win_get_config(win)
	if opts.relative == "editor" then
		assert(opts.col == 0 and opts.width == vim.o.columns)
		assert(opts.row == vim.o.lines - vim.o.cmdheight - opts.height)
		assert(opts.border == nil or opts.border == "none")
		assert(not opts.focusable and opts.title == nil)
		assert(vim.wo[win].winhighlight == "Normal:MsgArea,EndOfBuffer:MsgArea")
	end
end
vim.cmd.messages()
assert(vim.wait(500, function()
	return vim.api.nvim_win_get_config(0).relative ~= ""
end))
assert(visible("native notification"))
cmdline.close_history()
assert(vim.api.nvim_win_get_config(0).relative == "")

local received = {}
vim.notify = function(text, level, opts)
	received[#received + 1] = { text, level, opts.title }
end
for _, item in ipairs({
	{ "echo", vim.log.levels.INFO },
	{ "emsg", vim.log.levels.ERROR },
	{ "wmsg", vim.log.levels.WARN },
}) do
	vim.api.nvim_echo({ { item[1] } }, false, { kind = item[1] })
	assert(vim.wait(500, function()
		return #received > 0
	end))
	local notification = table.remove(received, 1)
	assert(notification[1] == item[1] and notification[2] == item[2])
	assert(notification[3] == "Messages")
end
vim.api.nvim_echo({ { "[3/10]" } }, false, { kind = "search_count" })
vim.wait(50)
assert(#received == 0)
vim.notify = function(text, level)
	native_notify(text, level)
end
vim.cmd('echo "wrapped notification"')
assert(vim.wait(500, function()
	return visible("wrapped notification")
end))
vim.notify = native_notify
vim.ui_detach(vim.api.nvim_create_namespace("cmdline.nvim"))
print("cmdline.nvim smoke: ok")
