-- hypr/.config/hypr/lua-theme/lib/generators/init.lua
-- Generator registry - loads and manages all app generators

local Generators = {}

-- Dynamically load all generators from apps/ directory
local function load_generators()
	local home = os.getenv("HOME")
	local apps_dir = home .. "/.config/hypr/lua-theme/lib/generators/apps"

	-- Get list of .lua files in apps directory
	local handle = io.popen('ls "' .. apps_dir .. '"/*.lua 2>/dev/null')
	if not handle then
		print("✗ Could not read generators directory")
		return
	end

	for file in handle:lines() do
		local name = file:match("([^/]+)%.lua$")
		if name then
			local module_path = "lib.generators.apps." .. name
			local success, generator_module = pcall(require, module_path)
			if success and generator_module.new then
				Generators[name] = generator_module:new()
			else
				print("⚠ Warning: Could not load generator: " .. name)
			end
		end
	end
	handle:close()
end

-- Load all generators
load_generators()

-- Generate all themes
function Generators.generate_all(palette, output_dir, palette_name)
	-- Iterate through all loaded generators and call their generate method
	for name, generator in pairs(Generators) do
		if type(generator) == "table" and generator.generate then
			generator:generate(palette, output_dir, palette_name)
		end
	end
end

return Generators
