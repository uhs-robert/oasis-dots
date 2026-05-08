-- hypr/.config/hypr/theme/lib/generators/base.lua
-- Base generator class that all app generators extend

-- Load shared utilities from lua/lib/utils.lua
local home = os.getenv("HOME")
package.path = home .. "/.config/hypr/lua/?.lua;" .. package.path
local Utils = require("lib.utils")

local BaseGenerator = {}
BaseGenerator.__index = BaseGenerator

function BaseGenerator:new()
	local obj = {}
	setmetatable(obj, self)
	return obj
end

-- Override this in child classes
function BaseGenerator:generate(palette, output_dir, palette_name)
	error("generate() must be implemented by child class")
end

-- Helper to write output file
function BaseGenerator:write_output(path, content)
	if Utils.write_file(path, content) then
		print("✓ Generated: " .. path)
		return true
	end
	return false
end

return BaseGenerator
