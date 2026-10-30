if vim.g.loaded_cmdline_nvim then
	return
end
vim.g.loaded_cmdline_nvim = true

---@type cmdline.Module
local cmdline = require("cmdline")
cmdline.setup()
