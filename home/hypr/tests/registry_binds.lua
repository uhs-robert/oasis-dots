-- Prints every bind the shipped keymaps register, one per line, as `submap<TAB>key<TAB>action id`, with `-` for a bind
-- that does not perform an action (a plain Bind.key). The global map is `global`. lib/check/steps/registry.py reads the
-- output in memory and fails on a plain bind that lib/check/registry.allow does not list. Binds are read under the
-- leader SUPER, with no monitors and with three; `custom/` is never loaded, so the owner's binds are not
-- checked.
--
--   lua home/hypr/tests/registry_binds.lua [--labels] [--default-config] [--module NAME [--path DIR]]
--
-- --labels appends the which-key label and the event (`press` or `release`) and `transparent` (a keyless passthrough, else `-`) as columns four to six, for
-- lib/docs/gen-keybinds; the registry step reads three. --default-config reads only the no-monitor variant, the one a
-- doc can describe: the other variant's binds depend on the machine's monitors.
-- --module loads NAME instead of `keymaps`, with DIR on package.path (the tests plant a fixture keymap there).
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local module, extra_path, with_labels, default_only = "keymaps", nil, false, false
local index = 1
while arg[index] do
	if arg[index] == "--labels" then
		with_labels, index = true, index + 1
	elseif arg[index] == "--default-config" then
		default_only, index = true, index + 1
	elseif arg[index] == "--module" and arg[index + 1] then
		module, index = arg[index + 1], index + 2
	elseif arg[index] == "--path" and arg[index + 1] then
		extra_path, index = arg[index + 1], index + 2
	else
		io.stderr:write("usage: registry_binds.lua [--labels] [--default-config] [--module NAME [--path DIR]]\n")
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
if default_only then
	VARIANTS = { VARIANTS[1] }
end
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
		local columns = {
			entry.submap ~= "" and entry.submap or "global",
			entry.key,
			Bind.action_id(entry.action) or "-",
		}
		if with_labels then
			columns[4] = tostring(entry.opts.desc or ""):gsub("%s", " ")
			columns[5] = entry.opts.release and "release" or "press"
			columns[6] = entry.opts.transparent and "transparent" or "-"
		end
		local line = table.concat(columns, "\t")
		if not seen[line] then
			seen[line] = true
			print(line)
		end
	end
end
