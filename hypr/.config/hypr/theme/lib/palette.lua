-- hypr/.config/hypr/theme/lib/palette.lua
-- Palette loading and color conversion utilities

local Palette = {}

function Palette.load(palette_dir, name)
	local path = palette_dir .. "/" .. name .. ".lua"
	local chunk = loadfile(path)
	if not chunk then
		print("Error: Could not load palette: " .. path)
		return nil
	end
	return chunk()
end

function Palette.hex_to_hypr(hex)
	-- Convert "#101825" or "101825" to "0xff101825"
	local clean = hex:gsub("#", "")
	return "0xff" .. clean
end

function Palette.ensure_hex(hex)
	-- Ensure hex has # prefix
	if hex:sub(1, 1) ~= "#" then
		return "#" .. hex
	end
	return hex
end

return Palette
