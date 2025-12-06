-- hypr/.config/hypr/lua-theme/wallpapers/lib/apply.lua
-- Period resolution, file selection, and hyprpaper application

local Apply = {}

local function list_images(dir, util)
	-- Use -print0 to safely handle spaces/newlines
	local cmd = string.format(
		'find -L "%s" -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\) -print0',
		dir
	)
	local p = io.popen(cmd)
	if not p then
		return {}
	end
	local data = p:read("*a") or ""
	p:close()
	local files = {}
	for entry in data:gmatch("([^%z]+)") do
		table.insert(files, entry)
	end
	return files
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local function pick_wallpapers(dir, count, util)
	local files = list_images(dir, util)
	if #files == 0 then
		return {}
	end
	shuffle(files)
	local out = {}
	for i = 1, count do
		out[i] = files[((i - 1) % #files) + 1]
	end
	return out
end

local function current_period(cfg)
	local t = os.date("*t")
	local ct = t.hour + t.min / 60
	local m = cfg.start_hours.morning
	local d = cfg.start_hours.day
	local e = cfg.start_hours.evening
	local n = cfg.start_hours.night

	if ct >= n or ct < m then
		return "night"
	elseif ct >= m and ct < d then
		return "morning"
	elseif ct >= d and ct < e then
		return "day"
	else
		return "evening"
	end
end

local function resolve_dir(cfg, period, util)
	if cfg.force_dir then
		return cfg.force_dir
	end
	local candidate = cfg.dirs[period]
	if candidate and #list_images(candidate, util) > 0 then
		return candidate
	end
	if cfg.default_wallpaper_dir then
		return cfg.default_wallpaper_dir
	end
	return candidate
end

local function parse_monitors_json(out)
	local mons = {}
	if not out then
		return mons
	end
	-- Iterate monitor objects; keep only plausible monitor names (contain a dash, not just digits)
	for block in out:gmatch("{(.-)}") do
		local name = block:match('"name"%s*:%s*"([^"]+)"')
		if name and name:find("%-") and not name:match("^%d+$") then
			mons[name] = true
		end
	end
	local uniq = {}
	for name, _ in pairs(mons) do
		table.insert(uniq, name)
	end
	return uniq
end

local function hyprctl(cmd, util)
	-- Try with current env
	local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
	local out = util.run_cmd(base .. "hyprctl " .. cmd .. " 2>/dev/null")
	if out and out:match("%S") and not out:match("socket timeout") then
		return out
	end

	-- Try to auto-detect a signature from /tmp/hypr/*
	local sig = util.run_cmd("ls -1 /tmp/hypr 2>/dev/null | head -n 1")
	if sig then
		sig = sig:match("([^\n]+)")
	end

	if sig and sig ~= "" then
		local env_cmd = string.format("HYPRLAND_INSTANCE_SIGNATURE=%s hyprctl %s 2>/dev/null", sig, cmd)
		out = util.run_cmd(env_cmd)
		if out and out:match("%S") and not out:match("socket timeout") then
			util.log("hyprctl succeeded after setting HYPRLAND_INSTANCE_SIGNATURE=" .. sig, { verbose = true })
			return out
		end
	end

	return out
end

local function monitors(cfg, util)
	-- Prefer JSON output for reliability
	local out_json = hyprctl("-j monitors", util)
	local mons = parse_monitors_json(out_json)

	if #mons == 0 then
		-- Fallback to text parsing
		local out_txt = hyprctl("monitors | awk '/Monitor/ {print $2}'", util)
		local set = {}
		if out_txt then
			for m in out_txt:gmatch("[^\\n]+") do
				if m:find("%-") and not m:match("^%d+$") then
					set[m] = true
				end
			end
		end
		for name, _ in pairs(set) do
			table.insert(mons, name)
		end

		if #mons == 0 and (out_json or out_txt) then
			local raw = (out_json or "") .. (out_txt or "")
			util.log("hyprctl output (monitors) empty or unparsable:\n" .. raw, cfg)
			return {}
		end
	end

	return mons
end

function Apply.to_monitors(cfg, util)
	local period = current_period(cfg)
	local dir = resolve_dir(cfg, period, util)
	if not dir then
		util.log("No directory resolved for period " .. period, cfg)
		return false
	end

	local mons = monitors(cfg, util)
	if #mons == 0 then
		util.log("No monitors found via hyprctl monitors", cfg)
		return false
	end

	local picks = pick_wallpapers(dir, #mons, util)
	if #picks == 0 then
		util.log("No wallpapers found in " .. dir .. " (period " .. period .. ")", cfg)
		return false
	end

	util.log(string.format("Period %s -> dir %s; monitors=%d; wallpapers=%d", period, dir, #mons, #picks), cfg)
	if cfg.verbose then
		for i, img in ipairs(picks) do
			util.log(string.format("  pick[%d]=%s", i, img), cfg)
		end
	end

	for i, mon in ipairs(mons) do
		local img = picks[i]
		if img then
			-- sanitize path (remove embedded newlines) and ensure absolute
			img = img:gsub("[\r\n]", "")
			-- ensure file exists
			local f = io.open(img, "r")
			if not f then
				-- Try relative to dir as fallback
				local alt = dir .. "/" .. img
				f = io.open(alt, "r")
				if f then
					img = alt
				end
			end
			if not f then
				util.log(string.format("Skipping missing file: %s", img), cfg)
			else
				f:close()
				local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
				local rc1 = os.execute(string.format("%shyprctl hyprpaper preload '%s' >/dev/null 2>&1", base, img))
				if rc1 ~= 0 and rc1 ~= true then
					util.log(string.format("hyprpaper preload failed (rc=%s) for %s", tostring(rc1), img), cfg)
				end
				util.sleep(0.15)
				local rc2 =
					os.execute(string.format("%shyprctl hyprpaper wallpaper '%s,%s' >/dev/null 2>&1", base, mon, img))
				if rc2 ~= 0 and rc2 ~= true then
					util.log(
						string.format("hyprpaper wallpaper failed (rc=%s) for %s on %s", tostring(rc2), img, mon),
						cfg
					)
				end
			end
		end
	end
	local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
	os.execute(string.format("%shyprctl hyprpaper unload unused >/dev/null 2>&1", base))
	return true
end

function Apply.list_images(dir, util)
	return list_images(dir, util)
end

return Apply
