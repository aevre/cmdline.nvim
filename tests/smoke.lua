vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cmdline = require("cmdline")
assert(type(cmdline.setup) == "function")
cmdline.setup({ enabled = false })

assert(vim.deep_equal(vim.deepcopy({ "/", "?" }), { "/", "?" }))
print("cmdline.nvim smoke: ok")
