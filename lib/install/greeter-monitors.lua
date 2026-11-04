-- Writes the greeter's monitor rules (/etc/greetd/monitors.lua) from the owner's session config, so the login screen lays
-- out the displays as the session does. The greeter runs as another user and cannot read the owner's home, hence a copy
-- made at install time.
--
-- Usage: lua greeter-monitors.lua <machines_dir> <state_json>   (rules on stdout; warnings and failures on stderr)
-- Plain Lua with no Hyprland: the profile is a data file and the overrides are JSON read through the session's lib/json.lua.
--
-- Mirrors config/monitors/init.lua: same selectors, same override fields. Two deliberate differences, both so the login
-- screen never comes up dark or unplaced:
--   * `disabled` overrides are ignored, so every connected screen is lit.
--   * an entry without a mode gets "preferred" (the session leaves such an entry unconfigured).
-- An entry with `start_delay_ms` starts disabled and is turned on by a timer; see hold_rules.
-- A profile that does not load exits non-zero; the installer then writes an empty file and warns.

local script_dir = (arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = script_dir .. "/../../home/hypr/.config/hypr/?.lua;" .. package.path
local Json = require("lib.json")

local machines_dir, state_file = arg[1], arg[2]

-- Same derivation as config/machines/init.lua so both pick the same profile file.
local function hostname()
	local name = os.getenv("HOSTNAME")
	if not name or name == "" then
		local file = io.open("/etc/hostname", "r")
		if not file then
			return nil
		end
		name = file:read("*l")
		file:close()
	end
	name = name and name:match("^%s*(.-)%s*$"):match("^[^.]+")
	return name and name:match("^[A-Za-z0-9_-]+$") and name or nil
end

local function load_profile_file(path)
	if not io.open(path, "r") then
		return {}
	end
	local chunk, load_err = loadfile(path)
	if not chunk then
		error(load_err, 0)
	end
	local profile = chunk()
	if type(profile) ~= "table" then
		error(path .. " must return a table, got " .. type(profile), 0)
	end
	return profile
end

-- The session merges default.lua under the hostname profile (Machines.merge) with lib/utils deep_extend: a non-empty list
-- in the hostname profile replaces default's, while an absent or empty `monitors` leaves default's in place.
local function session_monitors()
	local name = hostname()
	local from_host = name and load_profile_file(machines_dir .. "/" .. name .. ".lua").monitors
	if type(from_host) == "table" and next(from_host) ~= nil then
		return from_host
	end
	return load_profile_file(machines_dir .. "/default.lua").monitors
end

-- Unreadable or malformed overrides are not fatal: they only refine the profile.
local function load_overrides()
	local file = state_file and io.open(state_file, "r")
	if not file then
		return {}
	end
	local text = file:read("*a")
	file:close()
	local ok, data = pcall(Json.decode, text)
	if not ok or type(data) ~= "table" or type(data.monitors) ~= "table" then
		return {}
	end
	return data.monitors
end

local function number_text(value)
	local number = tonumber(value)
	return number and string.format("%.15g", number)
end

-- The override carries the fields the Settings panel saved; each replaces the profile's value.
local function rule_fields(output, base, override)
	local rule = { mode = base.mode or "preferred", position = base.position or "auto", scale = base.scale or 1, transform = base.transform }
	if type(override) == "table" then
		if type(override.mode) == "string" then
			rule.mode = override.mode
		end
		if type(override.position) == "string" then
			rule.position = override.position
		end
		if override.scale ~= nil then
			rule.scale = override.scale
		end
		if type(override.transform) == "number" then
			rule.transform = override.transform
		end
	end
	local fields = string.format("output = %q, mode = %q, position = %q, scale = %s", output, rule.mode, rule.position, number_text(rule.scale) or "1")
	local transform = number_text(rule.transform)
	if transform then
		fields = fields .. ", transform = " .. transform
	end
	return fields
end

local function rule_for(output, base, override)
	return "hl.monitor({ " .. rule_fields(output, base, override) .. " })"
end

local function start_delay(entry)
	local delay = tonumber(entry.start_delay_ms)
	return delay and delay > 0 and math.floor(delay) or nil
end

-- Hyprland 0.57 aborts when a dock monitor comes up before the dock has settled (hyprwm/Hyprland#16727): the monitor
-- has no working mode, and building its framebuffer asserts on a zero size. A disabled monitor is skipped there, so a
-- delayed entry starts disabled and a timer turns it on. The release must say `disabled = false`, because hl.monitor()
-- keeps the fields a new rule leaves out. It lands only while another monitor draws, so nothing is held when every
-- entry is delayed.
local function hold_rules(held)
	local lines = {}
	for _, item in ipairs(held) do
		lines[#lines + 1] = string.format("hl.monitor({ output = %q, disabled = true })", item.output)
	end
	for _, item in ipairs(held) do
		lines[#lines + 1] = string.format(
			"hl.timer(function() hl.monitor({ %s, disabled = false }) end, { timeout = %d, type = \"oneshot\" })",
			item.fields,
			item.delay
		)
	end
	return lines
end

local function entry_output(entry)
	if type(entry.description) == "string" then
		return "desc:" .. entry.description
	end
	-- An id-only entry names a live monitor, which does not exist at install time.
	return type(entry.name) == "string" and entry.name or nil
end

local function generate()
	local entries = session_monitors()
	local overrides = load_overrides()
	local lines = { "-- Generated by lib/install/greeter-monitors.lua at greeter-sync; edit the machine profile instead." }
	local listed, rules, has_undelayed = {}, {}, false
	for _, entry in ipairs(type(entries) == "table" and entries or {}) do
		local output = entry_output(entry)
		if output then
			local override = overrides[entry.description or ""] or overrides[entry.name or ""]
			local delay = start_delay(entry)
			rules[#rules + 1] = { output = output, fields = rule_fields(output, entry, override), delay = delay }
			has_undelayed = has_undelayed or delay == nil
			listed[entry.description or entry.name] = true
		end
	end
	local held = {}
	for _, rule in ipairs(rules) do
		if rule.delay and has_undelayed then
			held[#held + 1] = rule
		else
			lines[#lines + 1] = "hl.monitor({ " .. rule.fields .. " })"
		end
	end
	for _, line in ipairs(hold_rules(held)) do
		lines[#lines + 1] = line
	end
	-- Overridden displays outside the profile: sorted so the output is stable.
	local extra = {}
	for key, override in pairs(overrides) do
		if not listed[key] and type(override) == "table" and (type(override.mode) == "string" or type(override.position) == "string") then
			extra[#extra + 1] = key
		end
	end
	table.sort(extra)
	for _, key in ipairs(extra) do
		local output = overrides[key].description == true and "desc:" .. key or key
		lines[#lines + 1] = rule_for(output, {}, overrides[key])
	end
	return table.concat(lines, "\n") .. "\n"
end

local ok, result = pcall(generate)
if not ok then
	io.stderr:write("greeter-monitors: ", tostring(result), "\n")
	os.exit(1)
end
io.write(result)
