-- Prints every bind the shipped keymaps register, one per line, as `submap<TAB>key<TAB>action id`, with `-` for a bind
-- that does not perform an action (a plain Bind.key). The global map is `global`. lib/check/steps/registry.py reads the
-- output in memory and fails on a plain bind that lib/check/registry.allow does not list. Binds are read under the
-- leader SUPER, with no monitors and with three; `custom/` is never loaded, so the owner's binds are not
-- checked.
--
--   lua home/hypr/tests/registry_binds.lua [--module NAME [--path DIR]]
--
-- --module loads NAME instead of `keymaps`, with DIR on package.path (the tests plant a fixture keymap there).
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local module, extra_path = "keymaps", nil
local index = 1
while arg[index] do
	if arg[index] == "--module" and arg[index + 1] then
		module, index = arg[index + 1], index + 2
	elseif arg[index] == "--path" and arg[index + 1] then
		extra_path, index = arg[index + 1], index + 2
	else
		io.stderr:write("usage: registry_binds.lua [--module NAME [--path DIR]]\n")
		os.exit(2)
	end
end

local Stubs = dofile(here .. "/act_stubs.lua")
if extra_path then
	package.path = extra_path .. "/?.lua;" .. package.path
end

-- Both without monitors and with three, since a keymap adds binds for the monitors it finds; a bind seen under any of them is listed once.
-- Not the leaderless variant: that one gives keys like " + A" that no bind has. Only the monitor count matters here.
local VARIANTS = {
	Stubs.VARIANTS[1],
	{ name = "monitors", leader = "SUPER", monitors = Stubs.VARIANTS[2].monitors },
}
local Bind, Act
local seen = {}
for _, variant in ipairs(VARIANTS) do
	-- Stubs.load clears the lib.* and keymaps.* modules but not the entry module itself.
	package.loaded[module] = nil
	Stubs.load(variant, { module })
	Act, Bind = require("lib.act"), require("lib.key.bind")
	if #Act.warnings > 0 then
		for _, warning in ipairs(Act.warnings) do
			io.stderr:write("registry_binds: " .. warning .. "\n")
		end
		os.exit(1)
	end
	for _, entry in ipairs(Stubs.binds) do
		local line = table.concat({
			entry.submap ~= "" and entry.submap or "global",
			entry.key,
			Bind.action_id(entry.action) or "-",
		}, "\t")
		if not seen[line] then
			seen[line] = true
			print(line)
		end
	end
end
