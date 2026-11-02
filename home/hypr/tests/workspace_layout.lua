-- Checks lib/workspace_layout.lua: which monitor owns each workspace with one or several monitors, where workspaces
-- go on dock and undock (handed off, parked, sent home), and the saved counts in workspaces.json.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local root = here .. "/../.config/hypr"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local state_dir = os.tmpname()
os.remove(state_dir)
os.execute("mkdir -p '" .. state_dir .. "'")
package.loaded["lib.state"] = function() return state_dir end

local Layout = require("lib.workspace_layout")

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function cfg()
	return { persistent_workspaces = 5, ws_per_monitor = 5, single_monitor_workspaces = 10 }
end

-- The owner's dock: laptop first in the profile, then Lenovo, Gigabyte and HP.
local LAPTOP, LENOVO, GIGA, HP = "eDP-1", "DP-1", "DP-2", "DP-3"
local DOCKED = { [LAPTOP] = 1, [LENOVO] = 2, [GIGA] = 3, [HP] = 4 }

local function on(monitor, first, last)
	local list = {}
	for n = first, last do
		list[#list + 1] = { id = n, monitor = monitor }
	end
	return list
end

local function concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, item in ipairs(list) do
			out[#out + 1] = item
		end
	end
	return out
end

-- "id>monitor" for every move, in id order.
local function moves(slots, workspaces)
	local parts = {}
	for _, move in ipairs(Layout.plan(cfg(), slots, workspaces)) do
		parts[#parts + 1] = move.id .. ">" .. move.monitor
	end
	return table.concat(parts, " ")
end

local function range(first, last, monitor)
	local parts = {}
	for n = first, last do
		parts[#parts + 1] = n .. ">" .. monitor
	end
	return table.concat(parts, " ")
end

-- Ownership.
local single = Layout.owners(cfg(), { [LAPTOP] = 1 })
check("one monitor owns 1-10", single[1] == LAPTOP and single[10] == LAPTOP and single[11] == nil)
local docked = Layout.owners(cfg(), DOCKED)
check("docked: laptop 1-5", docked[1] == LAPTOP and docked[5] == LAPTOP)
check("docked: Lenovo 6-10", docked[6] == LENOVO and docked[10] == LENOVO)
check("docked: HP 16-20", docked[16] == HP and docked[20] == HP and docked[21] == nil)
local external = Layout.owners(cfg(), { [GIGA] = 3 })
check("one external monitor alone owns 1-10", external[1] == GIGA and external[10] == GIGA and external[11] == nil)

-- Dock with all ten laptop workspaces in use: 6-10 go to the Lenovo, keeping their numbers.
check("dock hands 6-10 to the Lenovo", moves(DOCKED, on(LAPTOP, 1, 10)) == range(6, 10, LENOVO))

-- Dock with only the Gigabyte: 6-10 have no owner and stay parked on the laptop.
check("Gigabyte only: nothing moves", moves({ [LAPTOP] = 1, [GIGA] = 3 }, on(LAPTOP, 1, 10)) == "")

-- Undock from four monitors: 6-10 become the laptop's own, 11-20 park on it.
local all_docked = concat(on(LAPTOP, 1, 5), on(LENOVO, 6, 10), on(GIGA, 11, 15), on(HP, 16, 20))
check("undock brings 6-20 to the laptop", moves({ [LAPTOP] = 1 }, all_docked) == range(6, 20, LAPTOP))

-- Redock after that undock: every workspace goes home.
check(
	"redock sends 6-20 home",
	moves(DOCKED, on(LAPTOP, 1, 20))
		== table.concat({ range(6, 10, LENOVO), range(11, 15, GIGA), range(16, 20, HP) }, " ")
)

-- Unplug only the HP: its workspaces park on the laptop, the rest stay.
check(
	"unplug HP parks 16-20 on the laptop",
	moves({ [LAPTOP] = 1, [LENOVO] = 2, [GIGA] = 3 }, all_docked) == range(16, 20, LAPTOP)
)

-- Special and named workspaces are left alone.
check(
	"special and named workspaces stay",
	moves({ [LAPTOP] = 1 }, { { id = -98, monitor = HP, special = true }, { id = nil, monitor = HP } }) == ""
)
check("no monitors, no moves", moves({}, on(HP, 1, 3)) == "")

-- Saved counts.
local function write_state(text)
	local f = assert(io.open(state_dir .. "/workspaces.json", "w"))
	f:write(text)
	f:close()
end

write_state('{"per_monitor": 3, "single_monitor": 8}')
local c = cfg()
Layout.apply_state(c)
check("saved counts win", c.persistent_workspaces == 3 and c.ws_per_monitor == 3 and c.single_monitor_workspaces == 8)
check("ranges follow the saved counts", select(2, Layout.range(c, 2, 2)) == 6 and select(2, Layout.range(c, 1, 1)) == 8)

write_state('{"per_monitor": 11, "single_monitor": 0.5}')
c = cfg()
Layout.apply_state(c)
check("out-of-range counts are ignored", c.persistent_workspaces == 5 and c.single_monitor_workspaces == 10)

write_state('{"per_monitor": 4}')
c = { persistent_workspaces = false, single_monitor_workspaces = 10 }
Layout.apply_state(c)
check("global workspaces stay off", c.persistent_workspaces == false and c.ws_per_monitor == 5)

write_state("not json")
c = cfg()
Layout.apply_state(c)
check("a malformed file changes nothing", c.persistent_workspaces == 5 and c.single_monitor_workspaces == 10)

os.remove(state_dir .. "/workspaces.json")
os.remove(state_dir)

if failures > 0 then
	os.exit(1)
end
print("ok workspace_layout")
