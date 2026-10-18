local M = {}

local function command(state)
	return table.concat(state.lines, " "):gsub("^%s*:", "")
end

local function matches_prompt(prompt, patterns)
	patterns = type(patterns) == "table" and patterns or { patterns }
	for _, pattern in ipairs(patterns) do
		if prompt:match(pattern) then
			return true
		end
	end
	return false
end

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
		if name then
			return type(name) == "table" and name.name or name
		end
	end
	for _, extension in ipairs(M.builtin) do
		local name = resolve_extension(extension, state)
		if name then
			return name
		end
	end
	return "cmdline"
end

return M
