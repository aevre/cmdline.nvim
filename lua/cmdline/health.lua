local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local error = health.error or health.report_error

function M.check()
	start("cmdline.nvim")
	if vim.fn.has("nvim-0.12") == 1 then
		ok("Neovim 0.12+ is available")
	else
		error("Neovim 0.12+ is required")
	end

	if type(vim.ui_attach) == "function" and type(vim.ui_detach) == "function" then
		ok("UI attachment API is available")
	else
		error("vim.ui_attach() and vim.ui_detach() are required")
	end
end

return M
