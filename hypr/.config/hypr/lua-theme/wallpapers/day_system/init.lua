-- hypr/.config/hypr/lua-theme/wallpapers/day_system/init.lua
-- Public entry that exposes run and CLI for the day/night wallpaper rotator

local main = require("wallpapers.day_system.main")

local M = {}

function M.run(opts)
	return main.run(opts)
end

-- CLI entry; accepts argv (defaults to global arg)
function M.main_cli(argv)
	local ok = M.run({ argv = argv })
	if not ok then
		os.exit(1)
	end
end

return M
