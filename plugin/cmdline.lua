if vim.g.loaded_cmdline_nvim then
	return
end
vim.g.loaded_cmdline_nvim = true

require("cmdline").setup()
