-- steam-appid.yazi
-- Resolve Steam AppID folders and files to game names for Yazi linemode.

local M = {}

local STEAM_SUBDIRS = { downloading = true, compatdata = true, shadercache = true, temp = true }

local DEFAULTS = {
	steamapps_paths = {
		os.getenv("HOME") .. "/.local/share/Steam/steamapps",
	},
	icon = "󰓓",
}
local opts = DEFAULTS
local cache = {}

-- Returns the last path component.
local function basename(path)
	return tostring(path):match("([^/]+)$") or tostring(path)
end

-- Returns the full contents of a file, or nil on failure.
local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	return content
end

-- Reads the manifest for a specific appid; caches the result (false if not found).
local function get_game_name(appid)
	if cache[appid] ~= nil then
		return cache[appid]
	end

	for _, steamapps in ipairs(opts.steamapps_paths) do
		local path = steamapps .. "/appmanifest_" .. appid .. ".acf"
		local content = read_file(path)
		local name = content and content:match('"name"%s+"([^"]+)"')

		if name then
			cache[appid] = name
			return name
		end
	end

	cache[appid] = false
	return nil
end

-- Applies user configuration and resets the cache.
function M.setup(user_opts)
	user_opts = user_opts or {}

	opts = {
		steamapps_paths = user_opts.steamapps_paths or DEFAULTS.steamapps_paths,
		icon = user_opts.icon or DEFAULTS.icon,
	}

	cache = {}
end

-- Yazi linemode entry point: renders the game name for Steam AppID folders and files.
function M.linemode(ctx)
	local path = tostring(ctx._file.url)
	local name = basename(path)
	local parent = path:match("/([^/]+)/[^/]+$")

	local appid
	if parent == "steamapps" then
		appid = name:match("^appmanifest_(%d+)%.acf$")
	elseif STEAM_SUBDIRS[parent] then
		appid = name:match("^%d+$")
	end

	if not appid then
		return ui.Line("")
	end

	local game_name = get_game_name(appid)
	if not game_name then
		return ui.Line("")
	end

	return ui.Line(opts.icon .. " " .. game_name)
end

return M
