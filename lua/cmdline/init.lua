local M = {}
local config_module = require("cmdline.config")
local highlights = require("cmdline.highlights")
local commandline = require("cmdline.commandline")
local popupmenu = require("cmdline.popupmenu")
local messages = require("cmdline.messages")
local ns
local attached = false
local original_cmdheight

M.close_history = messages.close_history

---@param event string UI2 event name dispatched by `vim.ui_attach()`.
---@return boolean? handled Whether the plugin consumed the event.
local function handle(event, ...)
	local handled = commandline.handle(event, ...)
	if event == "cmdline_hide" and handled then
		vim.schedule(popupmenu.close)
	end
	if handled then
		return handled
	end
	return popupmenu.handle(event, ...) or messages.handle(event, ...)
end

---@param opts? cmdline.Config Partial grouped configuration to merge with defaults.
---@return cmdline.Module module The public module for chaining and API access.
function M.disable()
	if not attached then
		return M
	end
	vim.api.nvim_del_augroup_by_name("cmdline.nvim")
	vim.ui_detach(ns)
	commandline.teardown()
	popupmenu.close()
	messages.close()
	vim.o.cmdheight = original_cmdheight
	original_cmdheight = nil
	attached = false
	return M
end

function M.setup(opts)
	local config = config_module.merge(opts)
	commandline.configure(config, ns)
	popupmenu.configure(config)
	messages.configure(config)
	if not config.cmdline.enabled and not config.messages.enabled then
		return M.disable()
	end
	highlights.setup(config)
	if vim.fn.has("nvim-0.12") == 0 then
		vim.notify("cmdline.nvim requires Neovim 0.12", vim.log.levels.WARN)
		return M
	end
	ns = ns or vim.api.nvim_create_namespace("cmdline.nvim")
	commandline.configure(config, ns)
	if not attached then
		original_cmdheight = vim.o.cmdheight
		vim.ui_attach(ns, {
			ext_cmdline = true,
			ext_popupmenu = true,
			ext_messages = true,
			set_cmdheight = false,
		}, handle)
		vim.o.cmdheight = 0
		attached = true
	end
	local group = vim.api.nvim_create_augroup("cmdline.nvim", { clear = true })
	vim.api.nvim_create_autocmd({ "CmdlineEnter", "CmdlineChanged" }, {
		group = group,
		callback = function()
			vim.schedule(commandline.patch_cmp)
		end,
	})
	vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
		group = group,
		callback = commandline.resize,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
		group = group,
		callback = commandline.refresh_search_count,
	})
	return M
end

return M
