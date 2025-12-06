-- hypr/.config/hypr/theme/lib/utils.lua
-- Utility functions for theme system

local Utils = {}

function Utils.write_file(path, content)
	local file = io.open(path, "w")
	if not file then
		print("Error: Could not write to " .. path)
		return false
	end
	file:write(content)
	file:close()
	return true
end

function Utils.load_palette(palette_dir, name)
	local path = palette_dir .. "/" .. name .. ".lua"
	local chunk = loadfile(path)
	if not chunk then
		print("Error: Could not load palette: " .. path)
		return nil
	end
	return chunk()
end

function Utils.hex_to_hypr(hex)
	-- Convert "#101825" or "101825" to "0xff101825"
	local clean = hex:gsub("#", "")
	return "0xff" .. clean
end

function Utils.ensure_hex(hex)
	-- Ensure hex has # prefix
	if hex:sub(1, 1) ~= "#" then
		return "#" .. hex
	end
	return hex
end

-- Wrapper for io.popen that shows a notification on error and asserts.
function Utils.popen_assert(cmd)
	local handle, err = io.popen(cmd)
	if not handle then
		local msg = "popen failed for command:\\n" .. cmd .. "\\nError: " .. tostring(err)
		os.execute('notify-send "Lua Script Error" "' .. msg .. '"')
		assert(handle, err)
	end
	return handle
end

return Utils
