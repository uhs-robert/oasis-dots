-- Prints every bind the shipped keymaps register, one per line, as `submap<TAB>key<TAB>action id`, with `-` for a bind
-- that does not perform an action (a plain Bind.key). The global map is `global`. lib/check/steps/registry.py reads the
-- output in memory and fails on a plain bind that lib/check/registry.allow does not list. Binds are read under the
-- default variant of act_stubs.lua (leader SUPER, no monitors); `custom/` is never loaded, so the owner's binds are not
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
Stubs.load(Stubs.VARIANTS[1], { module })

local Act = require("lib.act")
if #Act.warnings > 0 then
	for _, warning in ipairs(Act.warnings) do
		io.stderr:write("registry_binds: " .. warning .. "\n")
	end
	os.exit(1)
end

local Bind = require("lib.key.bind")
for _, entry in ipairs(Stubs.binds) do
	print(
		table.concat(
			{ entry.submap ~= "" and entry.submap or "global", entry.key, Bind.action_id(entry.action) or "-" },
			"\t"
		)
	)
end
