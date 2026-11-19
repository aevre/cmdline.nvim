LUA_FILES := $(shell find lua plugin -name '*.lua')
TEST_FILES := $(wildcard tests/*.lua)

.PHONY: fmt fmt-check lint test health check

fmt:
	stylua $(LUA_FILES) $(TEST_FILES)

fmt-check:
	stylua --check $(LUA_FILES) $(TEST_FILES)

lint:
	selene $(LUA_FILES)

test:
	nvim --headless -u NONE -c 'luafile tests/smoke.lua' -c 'qa!'
	nvim --headless -u NONE -c 'luafile tests/lifecycle.lua' -c 'qa!'

health:
	nvim --headless -u NONE --cmd 'set rtp^=.' -c 'checkhealth cmdline' -c 'lua vim.wait(1000); assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("cmdline.nvim", 1, true))' -c 'qa!'

check: fmt-check lint test health
