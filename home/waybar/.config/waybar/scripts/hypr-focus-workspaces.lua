#!/usr/bin/env lua

local address = arg[1]
local button = tonumber(arg[2])

local function get_no_warps()
	local handle = io.popen("hyprctl getoption cursor:no_warps")
	local output = handle:read("*a")
	handle:close()
	return output:match("int: (%d+)") == "1"
end

local function get_workspace(addr)
	local handle = io.popen("hyprctl clients -j")
	local output = handle:read("*a")
	handle:close()
	return output:match('"address": "' .. addr .. '".-"workspace": {%s*"id": (%d+)')
end

if button == 1 then
	local ws = get_workspace(address)
	if ws then
		os.execute(string.format("hyprctl dispatch \"hl.dsp.focus({ workspace = '%s' })\"", ws))
	end
	local already_no_warps = get_no_warps()
	if not already_no_warps then
		os.execute("hyprctl eval 'hl.config({ cursor = { no_warps = true } })'")
	end
	os.execute(string.format("hyprctl dispatch \"hl.dsp.focus({ window = 'address:%s' })\"", address))
	if not already_no_warps then
		os.execute("hyprctl eval 'hl.config({ cursor = { no_warps = false } })'")
	end
elseif button == 2 then
	os.execute(string.format("hyprctl dispatch \"hl.dsp.window.close({ address = '%s' })\"", address))
end
