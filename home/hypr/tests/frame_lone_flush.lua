-- Runs config/general/frame.lua against a stubbed `hl` and checks the lone-window opt-out (SUPER+M on a lone tiled
-- window) and the workspace animation swap: when the opt-out starts, ends and stays ended, and what the animation is.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local frame_path = here .. "/../.config/hypr/config/general/frame.lua"

local windows, active, handlers = {}, nil, {}
local rule_log, animation, config_calls = {}, nil, {}
local gaps_out = 6

local function new_rule(kind, spec)
	local rule = { kind = kind, spec = spec, enabled = true }
	function rule:set_enabled(on)
		self.enabled = on
	end
	table.insert(rule_log, rule)
	return rule
end

local function tagged(window)
	return window.tag_set ~= nil and window.tag_set["frame_gapped"] == true
end

_G.hl = {
	get_config = function(key)
		if key == "general.gaps_out" then
			return gaps_out
		end
		return 0
	end,
	get_layers = function()
		return { { mapped = true } }
	end,
	workspace_rule = function(spec)
		return new_rule("workspace", spec)
	end,
	window_rule = function(spec)
		return new_rule("window", spec)
	end,
	config = function(values)
		table.insert(config_calls, values)
	end,
	curve = function() end,
	animation = function(spec)
		animation = spec
	end,
	timer = function()
		return { set_enabled = function() end }
	end,
	on = function(event, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	get_active_window = function()
		return active
	end,
	get_windows = function()
		local copy = {}
		for _, w in ipairs(windows) do
			w.tags = tagged(w) and { "frame_gapped" } or {}
			table.insert(copy, w)
		end
		return copy
	end,
	get_workspace_windows = function(id)
		local found = {}
		for _, w in ipairs(windows) do
			if w.workspace.id == id then
				table.insert(found, w)
			end
		end
		return found
	end,
	dsp = {
		no_op = function()
			return {}
		end,
		window = {
			tag = function(args)
				return { tag = args.tag, window = args.window }
			end,
		},
	},
	dispatch = function(action)
		local address = action.window:gsub("^address:", "")
		for _, w in ipairs(windows) do
			if w.address == address then
				w.tag_set = w.tag_set or {}
				w.tag_set["frame_gapped"] = action.tag:sub(1, 1) == "+"
			end
		end
	end,
}

dofile(frame_path)

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function window(address, workspace_id)
	local w = {
		address = address,
		mapped = true,
		floating = false,
		fullscreen = 0,
		workspace = { id = workspace_id },
		tags = {},
	}
	table.insert(windows, w)
	return w
end

local function fire(event)
	for _, fn in ipairs(handlers[event] or {}) do
		fn()
	end
end

local function gap_rule_enabled(workspace_id)
	for _, rule in ipairs(rule_log) do
		if rule.kind == "workspace" and rule.spec.workspace == tostring(workspace_id) and rule.enabled then
			return true
		end
	end
	return false
end

local function remove(w)
	for i, other in ipairs(windows) do
		if other == w then
			table.remove(windows, i)
		end
	end
end

-- Without a frame the key is not ours.
local first = window("a", 1)
active = first
check("no frame: not handled", _G.ScreenFrame.toggle_lone_flush() == false)

_G.WorkspacesAnimation = { leaf = "workspaces", enabled = true, speed = 5, bezier = "smooth", style = "slidefade 20%" }
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
check(
	"frame on: plain slide on no-overshoot curve",
	animation.style == "slide" and animation.speed == 3.5 and animation.bezier == "easeOutQuint"
)
local rules_file = assert(io.open(here .. "/../.config/hypr/config/rules/init.lua"))
local rules_source = rules_file:read("a")
rules_file:close()
check("frame on: curve is defined by config/rules", rules_source:find('hl.curve("easeOutQuint"', 1, true) ~= nil)

check("lone: handled", _G.ScreenFrame.toggle_lone_flush() == true)
check("lone: tag set", tagged(first))
check("lone: gaps rule on", gap_rule_enabled(1))
check("lone: toggle back handled", _G.ScreenFrame.toggle_lone_flush() == true)
check("lone: tag cleared", not tagged(first))
check("lone: gaps rule off", not gap_rule_enabled(1))

-- A second tiled window ends the opt-out, and it stays ended when that window leaves.
_G.ScreenFrame.toggle_lone_flush()
local second = window("b", 1)
fire("window.open")
check("second window: tag cleared", not tagged(first))
check("second window: gaps rule off", not gap_rule_enabled(1))
check(
	"two tiled: key maximizes",
	(function()
		active = first
		return _G.ScreenFrame.toggle_lone_flush() == false
	end)()
)
remove(second)
fire("window.close")
check("second gone: still flush", not tagged(first) and not gap_rule_enabled(1))

-- Floating it ends the opt-out too, and re-tiling does not bring it back.
_G.ScreenFrame.toggle_lone_flush()
first.floating = true
fire("window.update_rules")
check("floated: tag cleared", not tagged(first))
check("floated: gaps rule off", not gap_rule_enabled(1))
first.floating = false
fire("window.update_rules")
check("re-tiled: still flush", not tagged(first) and not gap_rule_enabled(1))

-- A maximized window is not a lone window to opt out.
first.fullscreen = 1
check("maximized: key maximizes", _G.ScreenFrame.toggle_lone_flush() == false)
first.fullscreen = 0

-- Clearing the frame releases the opt-out and restores the animation.
_G.ScreenFrame.toggle_lone_flush()
_G.ScreenFrame.clear()
check("clear: tag cleared", not tagged(first))
check("clear: gaps rule off", not gap_rule_enabled(1))
check(
	"clear: animation restored",
	animation.style == "slidefade 20%" and animation.speed == 5 and animation.bezier == "smooth"
)

-- The frame can come back after a clear, and the slide applies again.
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
check("on again: slide", animation.style == "slide" and animation.speed == 3.5 and animation.bezier == "easeOutQuint")
_G.ScreenFrame.clear()
check(
	"off again: restored",
	animation.style == "slidefade 20%" and animation.speed == 5 and animation.bezier == "smooth"
)

-- A tag left by an earlier Lua state (config reload) is dropped when the frame is set again.
first.tag_set = { frame_gapped = true }
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
check("reload: stale tag dropped", not tagged(first))

-- A hidden group member is not counted by w[tv1], so the lone window still opts out and a new hidden member keeps it.
gaps_out = 6
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
local hidden = window("h", 1)
hidden.visible = false
first.visible = true
active = first
check("hidden member: lone window handled", _G.ScreenFrame.toggle_lone_flush() == true and tagged(first))
fire("window.open")
check("hidden member: opt-out kept", tagged(first))
_G.ScreenFrame.toggle_lone_flush()
remove(hidden)

-- The opt-out rule keeps a per-edge gaps table whole.
local edges = { top = 4, right = 8, bottom = 6, left = 10 }
gaps_out = edges
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
local before = #rule_log
_G.ScreenFrame.toggle_lone_flush()
local edge_rule = rule_log[before + 1]
check("css gaps: rule keeps the table", edge_rule ~= nil and edge_rule.spec.gaps_out == edges)
_G.ScreenFrame.toggle_lone_flush()

-- Same smallest edge, another edge edited with no reload: the rule must carry the new edges, not the cached old ones.
local edited = { top = 4, right = 12, bottom = 6, left = 10 }
gaps_out = edited
before = #rule_log
_G.ScreenFrame.toggle_lone_flush()
local edited_rule = rule_log[before + 1]
check("css gaps edited: new rule carries the new edges", edited_rule ~= nil and edited_rule.spec.gaps_out == edited)
_G.ScreenFrame.toggle_lone_flush()

-- A gap wide enough to flatten the gapped chamfer corner still leaves the flush windows a chamfer.
gaps_out = 24
_G.ScreenFrame.set("chamfer", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
local flush_powers = {}
for _, rule in ipairs(rule_log) do
	if rule.kind == "window" and rule.enabled and rule.spec.name:find("^quickshell%-frame%-lone") then
		table.insert(flush_powers, rule.spec.rounding_power)
	end
end
check("big gap chamfer: flush power chamfered", #flush_powers == 1 and flush_powers[1] == 1)

-- Flush single windows: on by default, off keeps lone windows gapped, and back on restores the flush.
local function flush_workspace_rule_enabled()
	for _, rule in ipairs(rule_log) do
		if rule.kind == "workspace" and rule.spec.workspace == "w[tv1]" then
			return rule.enabled
		end
	end
	return nil
end
local function lone_rounding_rules_enabled()
	for _, rule in ipairs(rule_log) do
		if rule.kind == "window" and rule.enabled and rule.spec.name:find("^quickshell%-frame%-lone") then
			return true
		end
	end
	return false
end
-- A 5-argument call (an older Quickshell) must mean on, even straight after an off.
gaps_out = 6
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)", false)
check("flush default: starts off", flush_workspace_rule_enabled() == false)
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)")
check("flush default: 5 args means on", flush_workspace_rule_enabled() == true)
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)", true)
check("flush on: workspace rule on", flush_workspace_rule_enabled() == true)
check("flush on: lone rounding rule on", lone_rounding_rules_enabled())
active = first
check("flush on: key opts out", _G.ScreenFrame.toggle_lone_flush() == true and tagged(first))
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)", false)
check("flush off: workspace rule off", flush_workspace_rule_enabled() == false)
check("flush off: held opt-out released", not tagged(first) and not gap_rule_enabled(1))
check("flush off: lone rounding rule off", not lone_rounding_rules_enabled())
check("flush off: key maximizes", _G.ScreenFrame.toggle_lone_flush() == false and not tagged(first))
_G.ScreenFrame.set("round", 12, 1, "rgba(33ccffee)", "rgba(595959aa)", true)
check("flush back on: workspace rule on", flush_workspace_rule_enabled() == true)
check("flush back on: key opts out", _G.ScreenFrame.toggle_lone_flush() == true and tagged(first))
_G.ScreenFrame.toggle_lone_flush()
_G.ScreenFrame.clear()
check("clear: workspace rule off", flush_workspace_rule_enabled() == false)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("frame lone flush: all passed")
