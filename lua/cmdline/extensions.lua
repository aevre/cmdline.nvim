local M = {}

---@param state cmdline.ExtensionState Command-line state supplied by UI2.
---@return string Command text without its leading colon.
local function command(state)
	local text = table.concat(state.lines, " "):gsub("^%s*:", "")
	return text
end

---@param prompt string Prompt text to test.
---@param patterns cmdline.Pattern One pattern or an ordered list of patterns.
---@return boolean Whether any pattern matches.
local function matches_prompt(prompt, patterns)
	local list
	if type(patterns) == "string" then
		list = { patterns }
	else
		list = patterns
	end
	for _, pattern in ipairs(list) do
		if prompt:match(pattern) then
			return true
		end
	end
	return false
end

---@param extension cmdline.Extension User or built-in extension to evaluate.
---@param state cmdline.ExtensionState Current command-line state.
---@return cmdline.ExtensionResult Context selected by the extension, if any.
local function resolve_extension(extension, state)
	if type(extension) == "function" then
		return extension(state)
	end
	if type(extension) ~= "table" then
		return nil
	end
	if extension.prompt and state.prompt ~= "" and matches_prompt(state.prompt:lower(), extension.prompt) then
		return extension.name
	end
	if extension.resolve then
		return extension.resolve(state)
	end
end

M.builtin = {
	function(state)
		if state.firstc == "/" or state.firstc == "?" then
			return "search"
		end
	end,
	{ name = "rename", prompt = { "rename", "new%s+name" } },
	function(state)
		if state.prompt ~= "" then
			return "input"
		end
	end,
	function(state)
		if state.firstc == "=" then
			return "expression"
		elseif state.firstc == ">" then
			return "debug"
		end
	end,
	function(state)
		local text = command(state)
		if text:match("^lua%f[%W]") or text:match("^lua%s*=") then
			return "lua"
		elseif text:match("^s/") or text:match("^substitute%f[%W]") then
			return "substitute"
		elseif text:match("^filter%f[%W]") or text:match("^!") then
			return "filter"
		elseif text:match("^he?l?p?%s+") then
			return "help"
		end
	end,
}

---@param config cmdline.ResolvedConfig Complete plugin configuration.
---@param current cmdline.CommandlineState Current UI2 command-line state.
---@param lines string[] Plain-text content corresponding to current chunks.
---@return string First matching context, or the generic `cmdline` context.
function M.resolve(config, current, lines)
	local state = {
		chunks = current.chunks,
		firstc = current.firstc,
		indent = current.indent,
		level = current.level,
		lines = lines,
		pos = current.pos,
		prompt = current.prompt,
	}
	for _, extension in ipairs(config.cmdline.extensions or {}) do
		local name = resolve_extension(extension, state)
		if type(name) == "table" then
			return name.name
		elseif name then
			return name
		end
	end
	for _, extension in ipairs(M.builtin) do
		local name = resolve_extension(extension, state)
		if type(name) == "table" then
			return name.name
		elseif name then
			return name
		end
	end
	return "cmdline"
end

return M
