-- Runs lib/key/bind.lua against a stubbed `hl` and the real action manifest: Bind.action registers an action's
-- key, extra keys and label from the manifest, honours overrides, fails loudly on an unknown id, and its binds
-- can be removed with Bind.unbind.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

package.loaded["config"] = { leader = "SUPER" }

local binds, removed = {}, {}
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

-- An unknown id raises, naming the id.
local ok, err = pcall(Bind.action, "nope.missing")
check("unknown id raises", not ok and tostring(err):find("nope.missing", 1, true) ~= nil)

-- An unreadable manifest raises too, rather than dropping every bind.
local saved = Bind.manifest_dir
Bind.manifest_dir = here .. "/no-such-dir"
Bind.reload_manifest()
ok, err = pcall(Bind.action, "zoom.toggle")
check("missing manifest raises", not ok and tostring(err):find("actions.json", 1, true) ~= nil)
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
	check("tools.lua id exists: " .. id, pcall(Bind.action, id))
end
check("tools.lua ids found", used > 0)
Bind.djinn_bin = here .. "/no-such-runner"
Bind.reload_manifest()
for id in tools:gmatch('Bind%.action%("([^"]+)"') do
	reset()
	check("tools.lua id has a direct performer: " .. id, pcall(Bind.action, id))
end
Bind.djinn_bin = "/bin/sh"
Bind.reload_manifest()

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
