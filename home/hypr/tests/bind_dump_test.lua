-- Runs bind_dump.lua as a program: on the real keymaps it succeeds and names the tools.lua actions; on fixture
-- keymaps a plain Bind.key dumps `action: null`, --compare reports a changed bind, and an unstubbed require fails
-- with the module's name.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local dump = "lua " .. here .. "/bind_dump.lua"

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

--- Output (stdout and stderr) and whether the command exited 0.
local function run(command)
	local pipe = assert(io.popen(command .. " 2>&1"))
	local out = pipe:read("a")
	local ok = pipe:close()
	return out, ok == true
end

--- True when one line of `out` holds `"key":"<key>"` and, after it, `"action":<action>`, both matched literally.
local function has_row(out, key, action)
	local function literal(text)
		return (text:gsub("%p", "%%%0"))
	end
	return out:find(literal('"key":"' .. key .. '"') .. "[^\n]*" .. literal('"action":' .. action)) ~= nil
end

local function write(path, text)
	local file = assert(io.open(path, "w"))
	file:write(text)
	file:close()
end

local real, real_ok = run(dump)
check("real keymaps: dump succeeds", real_ok)
for id, key in pairs({
	["picker.clipboard"] = "SUPER + CTRL + V",
	["picker.clipboard_delete"] = "SUPER + CTRL + SHIFT + V",
	["picker.directory"] = "SUPER + CTRL + SPACE",
	["picker.emoji"] = "SUPER + CTRL + E",
	["hyprvim.terminal"] = "SUPER + SHIFT + SEMICOLON",
	["hyprvim.jump_mark"] = "SUPER + APOSTROPHE",
}) do
	check("real keymaps: " .. id, has_row(real, key, '"' .. id .. '"'))
end
check("real keymaps: a submap row is dumped", real:find('"submap":"Go"', 1, true) ~= nil)

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")
local keymap = dir .. "/keymap.lua"
write(
	keymap,
	'local Bind = require("lib.key.bind")\n'
		.. 'Bind.key("SUPER + F1", hl.dsp.window.close(), "Plain")\n'
		.. 'Bind.action("zoom.toggle")\n'
)
local fixture, fixture_ok = run(dump .. " --keymap " .. keymap)
check("fixture: dump succeeds", fixture_ok)
check("fixture: plain bind has a null action", has_row(fixture, "SUPER + F1", "null"))
check("fixture: Bind.action bind has its id", has_row(fixture, "SUPER + Z", '"zoom.toggle"'))

local saved = dir .. "/saved.jsonl"
write(saved, fixture)
local _, same_ok = run(dump .. " --keymap " .. keymap .. " --compare " .. saved)
check("compare: identical dump exits 0", same_ok)
write(saved, (fixture:gsub('"desc":"Plain"', '"desc":"Old"')))
local diff, diff_ok = run(dump .. " --keymap " .. keymap .. " --compare " .. saved)
check("compare: a changed label exits 1", not diff_ok)
check(
	"compare: shows both sides",
	diff:find('- {"desc":"Old"', 1, true) ~= nil and diff:find('+ {"desc":"Plain"', 1, true) ~= nil
)

write(keymap, 'require("lib.no_such_module")\n')
local broken, broken_ok = run(dump .. " --keymap " .. keymap)
check("unstubbed require: fails", not broken_ok)
check("unstubbed require: names the module", broken:find("lib.no_such_module", 1, true) ~= nil)

os.execute("rm -rf '" .. dir .. "'")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("bind dump: all passed")
