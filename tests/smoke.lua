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
print("cmdline.nvim smoke: ok")
