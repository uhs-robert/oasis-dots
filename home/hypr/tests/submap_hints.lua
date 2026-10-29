-- The hint bars the shipped submaps send Quickshell (Submap.define `hint`, lib/key/submap_hint.lua), built from the
-- keymaps under the stubs and compared with fixtures/submap_hints.txt, one line per group:
-- `variant<TAB>submap<TAB>group<TAB>cap label · cap label`, the Esc and ? keys as group `(footer)`. A hint item that no
-- bind row matches fails the test.
--
--   lua home/hypr/tests/submap_hints.lua            compare with the fixture
--   lua home/hypr/tests/submap_hints.lua --update   rewrite the fixture
--   lua home/hypr/tests/submap_hints.lua --json     print each submap's hint as sent, one JSON object per line
--                                                   (the default variant; the shadow preview feeds these to the bar)
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local Stubs = dofile(here .. "/act_stubs.lua")
local fixture = here .. "/fixtures/submap_hints.txt"
local mode = arg[1]

local lines = {}
for _, variant in ipairs(Stubs.VARIANTS) do
	-- Stubs.load clears the keymaps.* modules but not the entry module itself.
	package.loaded["keymaps"] = nil
	Stubs.load(variant, { "keymaps" })
	local SubmapHint = require("lib.key.submap_hint")
	local Json = require("lib.json")
	for _, err in ipairs(SubmapHint.errors) do
		print("FAIL " .. variant.name .. ": " .. err)
		os.exit(1)
	end
	local names = {}
	for name in pairs(SubmapHint.encoded) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		if mode == "--json" then
			if variant == Stubs.VARIANTS[1] then
				print(SubmapHint.encoded[name])
			end
		else
			local hint = Json.decode(SubmapHint.encoded[name])
			local rows = {}
			for _, group in ipairs(hint.groups) do
				rows[#rows + 1] = { group.name, group.keys }
			end
			rows[#rows + 1] = { "(footer)", hint.footer }
			for _, row in ipairs(rows) do
				local keys = {}
				for _, key in ipairs(row[2]) do
					keys[#keys + 1] = key[1] .. " " .. key[2]
				end
				lines[#lines + 1] = table.concat({ variant.name, name, row[1], table.concat(keys, " · ") }, "\t")
			end
		end
	end
end
if mode == "--json" then
	os.exit(0)
end

if mode == "--update" then
	local out = assert(io.open(fixture, "w"))
	out:write("# lua home/hypr/tests/submap_hints.lua --update\n", table.concat(lines, "\n"), "\n")
	out:close()
	os.exit(0)
end

local expected = {}
for line in io.lines(fixture) do
	if line ~= "" and line:sub(1, 1) ~= "#" then
		expected[#expected + 1] = line
	end
end
local failures = 0

-- A hint naming an action the submap has no row for is dropped with a notice, and the submap still binds its keys.
local SubmapHint = require("lib.key.submap_hint")
local Submap = require("lib.key.submap")
Submap.define({
	name = "HintTypo",
	binds = { { "X", "window.close" } },
	hint = { { "Typo", "window.closee" } },
}).setup()
if SubmapHint.encoded.HintTypo ~= nil or #SubmapHint.errors ~= 1 or not Submap.registry.HintTypo then
	failures = failures + 1
	print("FAIL a hint item matching no row should drop the hint and keep the submap")
end

for index = 1, math.max(#lines, #expected) do
	if lines[index] ~= expected[index] then
		failures = failures + 1
		print("FAIL line " .. index .. "\n  got:  " .. tostring(lines[index]) .. "\n  want: " .. tostring(expected[index]))
	end
end
if failures > 0 then
	print("submap_hints: " .. failures .. " lines differ; if the change is meant, rerun with --update")
	os.exit(1)
end
print("submap_hints: ok (" .. #lines .. " groups)")
