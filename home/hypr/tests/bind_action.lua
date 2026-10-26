-- Runs lib/key/bind.lua against a stubbed `hl` and the real action manifest: Bind.action registers an action's
-- key, extra keys and label from the manifest, honours overrides, performs `lua` actions in-process, passes
-- opts.args on, warns and skips an unknown id or performer, and its binds can be removed with Bind.unbind.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

package.loaded["config"] = { leader = "SUPER" }

-- The real performers.lua loads over this: each picker records that it ran instead of opening a menu.
local menu_calls = {}
local function recorder(name)
	return function()
		return function()
			menu_calls[#menu_calls + 1] = name
		end
	end
end
package.loaded["lib.actions.menu"] = {
	clipboard = recorder("clipboard"),
	clipboard_delete = recorder("clipboard_delete"),
	zoxide = recorder("zoxide"),
	emoji = recorder("emoji"),
}

local binds, removed, timers, notices = {}, {}, {}, {}
_G.hl = {
	version = function()
		return "0.57.0"
	end,
	bind = function(key, action, opts)
		local entry = { key = key, action = action, opts = opts }
		function entry:remove()
			removed[#removed + 1] = key
		end
		binds[#binds + 1] = entry
		return entry
	end,
	timer = function(fn)
		timers[#timers + 1] = fn
	end,
	notification = {
		create = function(opts)
			notices[#notices + 1] = opts.text
		end,
	},
	dsp = {
		exec_cmd = function(cmd)
			return "exec:" .. cmd
		end,
	},
}

local Bind = require("lib.key.bind")
Bind.manifest_dir = here .. "/../../oasis-djinn/.config/oasis-djinn"
Bind.djinn_bin = "/bin/sh" -- any executable file stands in for the installed runner

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function reset()
	binds, removed = {}, {}
end

local function find(key)
	for _, entry in ipairs(binds) do
		if entry.key == key then
			return entry
		end
	end
end

-- Key, label and command come from the manifest.
check("Bind.action exists", type(Bind.action) == "function")
reset()
Bind.action("zoom.toggle")
local zoom = find("SUPER + Z")
check("zoom: leader key registered", zoom ~= nil and #binds == 1)
check("zoom: label from manifest", zoom and zoom.opts.desc == "Zoom")
check("zoom: calls the runner", zoom and zoom.action == "exec:~/.local/bin/oasis-djinn zoom.toggle")
check("zoom: not universal", zoom and not zoom.opts.submap_universal)

-- A universal key stays live inside submaps; extra keys register as further binds in manifest order.
reset()
Bind.action("screenshot.take")
check("extra keys: two binds", #binds == 2)
check("extra keys: universal main key", binds[1] and binds[1].key == "Print" and binds[1].opts.submap_universal == true)
check(
	"extra keys: leader extra after it",
	binds[2] and binds[2].key == "SUPER + I" and not binds[2].opts.submap_universal
)
check("extra keys: same label", binds[2] and binds[2].opts.desc == "Screenshot")
check("extra keys: same command", binds[2] and binds[2].action == binds[1].action)

-- A plain key (no leader).
reset()
Bind.action("overview.open")
check("plain key: ALT + TAB unprefixed", find("ALT + TAB") ~= nil and find("SUPER + TAB") ~= nil)

-- opts.key replaces the default key, not the extras or the label; other opts pass through.
reset()
Bind.action("zoom.toggle", { key = "CTRL + Z", submap_universal = true })
local over = find("CTRL + Z")
check("override: replaces the default key", over ~= nil and find("SUPER + Z") == nil and #binds == 1)
check("override: label kept", over and over.opts.desc == "Zoom")
check("override: submap_universal kept", over and over.opts.submap_universal == true)
check("override: key not leaked into bind opts", over and over.opts.key == nil)

reset()
Bind.action("screenshot.take", { key = { key = "F12", leader = true } })
check(
	"override table: leader applied",
	find("SUPER + F12") ~= nil and find("SUPER + I") ~= nil and find("Print") == nil
)

-- opts can also drop the manifest's universal flag.
reset()
Bind.action("screenshot.take", { submap_universal = false })
check("opts beat manifest universal", binds[1] and binds[1].opts.submap_universal == false)

-- An unknown id between two valid ones warns and skips only itself; the rest of the file still binds.
reset()
Bind.warnings = {}
local ok = pcall(function()
	Bind.action("zoom.toggle")
	Bind.action("nope.missing")
	Bind.action("overview.open")
end)
check("unknown id does not raise", ok)
check("unknown id: both valid actions registered", find("SUPER + Z") ~= nil and find("ALT + TAB") ~= nil)
check("unknown id: no bind for it", #binds == 3)
check("unknown id: warning names it", #Bind.warnings == 1 and Bind.warnings[1]:find("nope.missing", 1, true) ~= nil)
check("unknown id: one notification scheduled", #timers == 1)
timers[1]()
check("unknown id: notification carries the warning", #notices == 1 and notices[1]:find("nope.missing", 1, true) ~= nil)

-- An unreadable manifest warns once and skips every bind, rather than aborting the config.
local saved = Bind.manifest_dir
Bind.manifest_dir = here .. "/no-such-dir"
Bind.reload_manifest()
Bind.warnings = {}
reset()
ok = pcall(function()
	Bind.action("zoom.toggle")
	Bind.action("overview.open")
end)
check("missing manifest does not raise", ok)
check("missing manifest: no binds", #binds == 0)
check(
	"missing manifest: one warning naming the file",
	#Bind.warnings == 1 and Bind.warnings[1]:find("actions.json", 1, true) ~= nil
)
Bind.manifest_dir = saved
Bind.reload_manifest()

-- Without the runner (install.sh -m, --no-cargo, a failed build) the bind runs the performer directly.
local function first_exec(id)
	Bind.reload_manifest()
	reset()
	Bind.action(id)
	return binds[1].action
end
Bind.djinn_bin = here .. "/no-such-runner"
check(
	"no runner: command binding",
	first_exec("screenshot.pixel") == "exec:~/.config/hypr/scripts/screenshot.sh --pixel"
)
check("no runner: ipc binding", first_exec("zoom.toggle") == "exec:~/.config/hypr/scripts/qs-ipc call zoom toggle")
check("no runner: multi-word argv", first_exec("voice.wake") == "exec:~/.local/bin/voxcmd wake toggle")
Bind.djinn_bin = "/bin/sh"
check("runner present again: djinn path", first_exec("zoom.toggle") == "exec:~/.local/bin/oasis-djinn zoom.toggle")

-- The direct command quotes what the shell would otherwise interpret; only a leading `~/` is left to expand,
-- as oasis-djinn does.
local synthetic_dir = os.tmpname()
os.remove(synthetic_dir)
os.execute("mkdir -p '" .. synthetic_dir .. "/bindings'")
local function write_synthetic(name, text)
	local file = assert(io.open(synthetic_dir .. "/" .. name, "w"))
	file:write(text)
	file:close()
end
write_synthetic(
	"actions.json",
	'{"actions":[{"id":"quote.test","label":"Quote","intent":"x","params":[],'
		.. '"key":{"key":"Q","leader":true,"universal":false},"extra_keys":[]}]}'
)
write_synthetic(
	"bindings/quickshell.json",
	'{"bindings":{"quote.test":{"kind":"command","argv":["~/bin/run","two words","it\'s","$(id)","~","~user","a~b"]}}}'
)
local saved_dir = Bind.manifest_dir
Bind.manifest_dir = synthetic_dir
Bind.djinn_bin = here .. "/no-such-runner"
check(
	"quoting: spaces, quote, substitution and bare tilde words are quoted",
	first_exec("quote.test") == "exec:~/bin/run 'two words' 'it'\\''s' '$(id)' '~' '~user' 'a~b'"
)
Bind.manifest_dir = saved_dir
Bind.djinn_bin = "/bin/sh"
Bind.reload_manifest()
os.execute("rm -rf '" .. synthetic_dir .. "'")

-- Every id tools.lua binds is in the manifest, with or without the runner.
local tools = assert(io.open(hypr_dir .. "/keymaps/global/tools.lua")):read("a")
local used = 0
for id in tools:gmatch('Bind%.action%("([^"]+)"') do
	used = used + 1
	reset()
	Bind.warnings = {}
	Bind.action(id)
	check("tools.lua id exists: " .. id, #binds > 0 and #Bind.warnings == 0)
end
check("tools.lua ids found", used > 0)
Bind.djinn_bin = here .. "/no-such-runner"
Bind.reload_manifest()
for id in tools:gmatch('Bind%.action%("([^"]+)"') do
	reset()
	Bind.warnings = {}
	Bind.action(id)
	check("tools.lua id has a direct performer: " .. id, #binds > 0 and #Bind.warnings == 0)
end
Bind.djinn_bin = "/bin/sh"
Bind.reload_manifest()

-- A lua action is a function bind: no process hop, so a repeating key stays fast. The tools.lua pickers run their
-- Menu closure in-process.
reset()
menu_calls = {}
Bind.warnings = {}
Bind.action("picker.clipboard")
local clip = find("SUPER + CTRL + V")
check("lua: bind registered", clip ~= nil and #binds == 1 and #Bind.warnings == 0)
check("lua: in-process function, not exec", clip and type(clip.action) == "function")
check("lua: label from manifest", clip and clip.opts.desc == "Clipboard History")
if clip and type(clip.action) == "function" then
	clip.action()
end
check("lua: calls the performer", menu_calls[1] == "clipboard")
check("lua: id recorded for the dump", clip and (Bind.action_ids or {})[clip] == "picker.clipboard")

-- The same holds without the runner: a lua action never goes through oasis-djinn.
Bind.djinn_bin = here .. "/no-such-runner"
Bind.reload_manifest()
reset()
Bind.action("picker.emoji")
check("lua without runner: function bind", binds[1] and type(binds[1].action) == "function")
Bind.djinn_bin = "/bin/sh"
Bind.reload_manifest()

-- A plain Bind.key records no action id.
reset()
Bind.key("SUPER + F1", "exec:x", "Plain")
check("plain bind: no action id", binds[1] and (Bind.action_ids or {})[binds[1]] == nil)
reset()
Bind.action("zoom.toggle")
check("runner bind: id recorded", binds[1] and (Bind.action_ids or {})[binds[1]] == "zoom.toggle")

-- opts.args reach the runner as extra words, shell-quoted, and never reach hl.bind's opts.
reset()
Bind.action("zoom.toggle", { args = { "two words", 3 } })
check(
	"args: appended to the runner command",
	binds[1] and binds[1].action == "exec:~/.local/bin/oasis-djinn zoom.toggle 'two words' 3"
)
check("args: not leaked into bind opts", binds[1] and binds[1].opts.args == nil)

-- Synthetic manifest: a lua action with params, a lua action performers.lua lacks, and a command with a param.
local lua_dir = os.tmpname()
os.remove(lua_dir)
os.execute("mkdir -p '" .. lua_dir .. "/bindings'")
local function write_lua_fixture(name, text)
	local file = assert(io.open(lua_dir .. "/" .. name, "w"))
	file:write(text)
	file:close()
end
local function action_json(id, key, params)
	return '{"id":"'
		.. id
		.. '","label":"'
		.. id
		.. '","intent":"x","params":'
		.. params
		.. ',"key":{"key":"'
		.. key
		.. '","leader":false,"universal":false},"extra_keys":[]}'
end
write_lua_fixture(
	"actions.json",
	'{"actions":['
		.. action_json("t.lua", "F2", '[{"name":"n","type":"int"},{"name":"s","type":"string"}]')
		.. ","
		.. action_json("t.lost", "F3", "[]")
		.. ","
		.. action_json("t.after", "F4", "[]")
		.. ","
		.. action_json("t.cmd", "F5", '[{"name":"n","type":"int"},{"name":"m","type":"string","default":"d"}]')
		.. ","
		.. action_json("t.cmd2", "F7", '[{"name":"n","type":"int"},{"name":"m","type":"string","default":"d"}]')
		.. ',{"id":"t.keyless","label":"Keyless","intent":"x","params":[],"extra_keys":[]}'
		.. "]}"
)
write_lua_fixture(
	"bindings/quickshell.json",
	'{"bindings":{"t.cmd":{"kind":"command","argv":["~/bin/run","{n}","{m}"]}}}'
)
write_lua_fixture(
	"bindings/hyprland.json",
	'{"bindings":{"t.lua":{"kind":"lua"},"t.lost":{"kind":"lua"},"t.after":{"kind":"lua"},"t.keyless":{"kind":"lua"},"t.cmd2":{"kind":"lua"}}}'
)
local real_performers = package.loaded["lib.actions.performers"]
local performed = {}
package.loaded["lib.actions.performers"] = {
	get = function(id)
		if id == "t.lost" then
			return nil
		end
		return function(...)
			performed[#performed + 1] = { id = id, args = { ... } }
		end
	end,
}
Bind.manifest_dir = lua_dir
Bind.reload_manifest()

reset()
Bind.warnings = {}
ok = pcall(function()
	Bind.action("t.lua", { args = { 7, "x" } })
	Bind.action("t.lost")
	Bind.action("t.after")
end)
check("missing performer does not raise", ok)
check("missing performer: neighbours still bind", find("F2") ~= nil and find("F4") ~= nil and find("F3") == nil)
check("missing performer: warning names it", #Bind.warnings == 1 and Bind.warnings[1]:find("t.lost", 1, true) ~= nil)
local lua_bind = find("F2")
if lua_bind and type(lua_bind.action) == "function" then
	lua_bind.action()
end
check(
	"lua args: performer gets opts.args in order",
	performed[1] and performed[1].id == "t.lua" and performed[1].args[1] == 7 and performed[1].args[2] == "x"
)

-- A lua action's required param is checked at bind time too.
reset()
Bind.warnings = {}
Bind.action("t.lua")
check("lua args: a missing required param warns and skips", #binds == 0 and #Bind.warnings == 1)

-- A lua performer is handed the manifest default for a param opts.args leaves out.
reset()
performed = {}
Bind.action("t.cmd2", { args = { 4 } })
if find("F7") and type(find("F7").action) == "function" then
	find("F7").action()
end
check("lua args: manifest default filled", performed[1] and performed[1].args[1] == 4 and performed[1].args[2] == "d")

-- An action with no key binds only where opts.key gives one.
reset()
Bind.warnings = {}
ok = pcall(Bind.action, "t.keyless")
check("keyless: no bind and a warning, no error", ok and #binds == 0 and #Bind.warnings == 1)
reset()
Bind.action("t.keyless", { key = "F6" })
check("keyless: opts.key binds it", find("F6") ~= nil and #binds == 1)

-- Without the runner a command binding's {param} words are filled from opts.args, then the defaults.
Bind.djinn_bin = here .. "/no-such-runner"
Bind.reload_manifest()
reset()
Bind.action("t.cmd", { args = { 5 } })
check("direct args: placeholders filled", binds[1] and binds[1].action == "exec:~/bin/run 5 d")
reset()
Bind.warnings = {}
Bind.action("t.cmd")
check("direct args: a missing required param warns and skips", #binds == 0 and #Bind.warnings == 1)
Bind.djinn_bin = "/bin/sh"

-- With the runner installed, a missing required param is also caught at bind time, not on the keypress.
Bind.reload_manifest()
reset()
Bind.warnings = {}
Bind.action("t.cmd")
check("runner args: a missing required param warns and skips", #binds == 0 and #Bind.warnings == 1)

-- performers.lua failing to load warns and skips its binds; it does not abort the keymap file.
package.loaded["lib.actions.performers"] = nil
package.preload["lib.actions.performers"] = function()
	error("performers broke")
end
Bind.reload_manifest()
reset()
Bind.warnings = {}
ok = pcall(function()
	Bind.action("t.lua", { args = { 1, "x" } })
	Bind.action("t.cmd", { args = { 1 } })
end)
check("broken performers module does not raise", ok)
check("broken performers module: other kinds still bind", find("F5") ~= nil and find("F2") == nil)
check(
	"broken performers module: warning says why",
	Bind.warnings[1] ~= nil and Bind.warnings[1]:find("performers broke", 1, true) ~= nil
)
reset()
Bind.warnings = {}
Bind.action("t.lua", { args = { 1, "x" } })
Bind.action("t.lua", { args = { 1, "x" } })
check("broken performers module: every lua bind warns, not just the first", #Bind.warnings == 2)
package.preload["lib.actions.performers"] = nil
package.loaded["lib.actions.performers"] = real_performers

Bind.manifest_dir = here .. "/../../oasis-djinn/.config/oasis-djinn"
Bind.reload_manifest()
os.execute("rm -rf '" .. lua_dir .. "'")

-- Bind.unbind removes what Bind.action registered, extras included.
-- A fresh module, so handles from the checks above are not counted.
package.loaded["lib.key.bind"] = nil
Bind = require("lib.key.bind")
Bind.manifest_dir = here .. "/../../oasis-djinn/.config/oasis-djinn"
Bind.djinn_bin = "/bin/sh"
reset()
Bind.action("screenshot.take")
check("unbind: main key", Bind.unbind("Print") == 1)
check("unbind: leader extra", Bind.leader_unbind("I") == 1)
check("unbind: handles removed", #removed == 2)
check("unbind: nothing left", Bind.unbind("Print") == 0)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("bind action: all passed")
