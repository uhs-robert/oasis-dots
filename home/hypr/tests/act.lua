-- Runs lib/act/init.lua against a stubbed `hl`: define registers an action and bind gives it keys, params are checked and coerced,
-- run_cli survives hostile strings, Ipc/Cmd carry their data and render params in one pass, and a bad definition
-- warns and skips without aborting the config.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

package.loaded["config"] = { leader = "SUPER" }

local binds, timers, notices, executed = {}, {}, {}, {}
local bind_error = nil
_G.hl = {
	version = function()
		return "0.57.0"
	end,
	bind = function(key, action, opts)
		if bind_error then
			error(bind_error)
		end
		local entry = { key = key, action = action, opts = opts }
		function entry:remove() end
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
			return { exec = cmd }
		end,
	},
	dispatch = function(dispatcher)
		executed[#executed + 1] = dispatcher.exec
	end,
}

local failures = 0
local passed = 0
local function check(name, ok)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local Act

--- A fresh module, so one section's actions and warnings do not leak into the next.
local function fresh()
	package.loaded["lib.act"] = nil
	package.loaded["lib.key.bind"] = nil
	binds, timers, notices, executed = {}, {}, {}, {}
	Act = require("lib.act")
end

local function find(key)
	for _, entry in ipairs(binds) do
		if entry.key == key then
			return entry
		end
	end
end

--- Message of the error `fn` raises, or nil when it does not raise.
local function raises(fn, ...)
	local ok, err = pcall(fn, ...)
	if ok then
		return nil
	end
	return tostring(err)
end

local function has(text, part)
	return text ~= nil and text:find(part, 1, true) ~= nil
end

---------------------------------------------------------------------------------------------------
-- define and bind
---------------------------------------------------------------------------------------------------
fresh()
local ran = {}
local zoom = Act.define("zoom.toggle", {
	label = "Zoom",
	intent = "Toggle the zoom.",
	opts = { repeating = true },
	run = function()
		ran[#ran + 1] = "zoom"
	end,
})
check("define: returns a handle with the id", zoom ~= nil and zoom.id == "zoom.toggle")
check("define: binds nothing", #binds == 0 and #Act.warnings == 0)
Act.bind("zoom.toggle", { key = { key = "Z", leader = true } })
Act.bind("zoom.toggle", { key = { key = "Print", universal = true } })
Act.bind("zoom.toggle", { key = "ALT + Z" })
check("bind: three binds, no warnings", #binds == 3 and #Act.warnings == 0)
check("bind: leader key is prefixed", find("SUPER + Z") ~= nil)
check("bind: label is the bind description", find("SUPER + Z").opts.desc == "Zoom")
check("bind: the define's opts pass through to hl.bind", find("SUPER + Z").opts.repeating == true)
check("bind: universal key is submap_universal", find("Print").opts.submap_universal == true)
check(
	"bind: plain string key is bound as written",
	find("ALT + Z") ~= nil and not find("ALT + Z").opts.submap_universal
)
find("SUPER + Z").action()
check("bind: the key runs the action", #ran == 1)

-- A define may carry its own key, as custom/ files can; tracked actions bind theirs in keymaps/.
fresh()
Act.define("a.keyed", { label = "Keyed", key = "ALT + K", extra_keys = { "ALT + J" }, run = function() end })
check(
	"define: key and extra keys are bound",
	find("ALT + K") ~= nil and find("ALT + J") ~= nil and #Act.warnings == 0
)

-- An action with params gets its keys from Act.bind with args.
fresh()
local seen = {}
Act.define("workspace.focus", {
	label = "Workspace",
	params = { { name = "n", type = "int" } },
	run = function(n)
		seen[#seen + 1] = n
	end,
})
check("keyless: no bind", #binds == 0 and #Act.warnings == 0)
for n = 1, 3 do
	Act.bind("workspace.focus", { key = { key = tostring(n), leader = true }, args = { n } })
end
check("bind: one bind per call", #binds == 3)
binds[2].action()
check("bind: the key passes its args", seen[1] == 2)
check("bind: label is the description", binds[1].opts.desc == "Workspace")

Act.bind("workspace.focus", { key = "F1", args = { 1 }, repeating = true, submap_universal = false })
check("bind: other opts reach hl.bind", find("F1").opts.repeating == true and find("F1").opts.submap_universal == false)
check("bind: args and key are not leaked into hl.bind", find("F1").opts.args == nil and find("F1").opts.key == nil)

-- `desc` names one key: a string replaces the label, false leaves the key undescribed, absent keeps the label.
Act.bind("workspace.focus", { key = "F5", args = { 1 }, desc = "Go to Workspace 1" })
Act.bind("workspace.focus", { key = "F6", args = { 1 }, desc = false })
Act.bind("workspace.focus", { key = "F7", args = { 1 } })
check("bind desc: a string replaces the label", find("F5").opts.desc == "Go to Workspace 1")
check("bind desc: false leaves the key undescribed", find("F6").opts.desc == nil)
check("bind desc: absent keeps the label", find("F7").opts.desc == "Workspace")
check("bind desc: the key still runs the action", pcall(find("F6").action))

-- A define's opts.desc is not a label for its keys: the label stays.
fresh()
Act.define("desc.opt", { label = "Label", opts = { desc = "Other", locked = true }, run = function() end })
Act.bind("desc.opt", { key = "F1" })
check("define: opts.desc does not rename the key", find("F1").opts.desc == "Label" and find("F1").opts.locked == true)

fresh()
Act.define("workspace.focus", {
	label = "Workspace",
	params = { { name = "n", type = "int" } },
	run = function() end,
})
Act.bind("workspace.focus", { key = "F1", args = { 1 } })

-- Bind failures warn and skip only that bind.
local before = #binds
Act.bind("workspace.focus", { key = "F2", args = { "three" } })
Act.bind("workspace.focus", { key = "F3" })
Act.bind("workspace.focus", { key = "F4", args = { 1, 2 } })
Act.bind("workspace.focus", { args = { 1 } })
check("bind: bad args or key skipped", #binds == before and #Act.warnings == 4)
check("bind: warning names the problem", has(Act.warnings[1], "expects an int"))

---------------------------------------------------------------------------------------------------
-- warn-and-skip
---------------------------------------------------------------------------------------------------
fresh()
local ok = pcall(function()
	Act.define("a.first", { label = "First", run = function() end })
	Act.bind("a.first", { key = "F1" })
	Act.bind("nope.missing", { key = "F9" })
	Act.define("a.dup", { label = "Dup", run = function() end })
	Act.define("a.dup", { label = "Dup again", run = function() end })
	Act.bind("a.dup", { key = "F2" })
	Act.define("a.nolabel", { run = function() end })
	Act.define("a.norun", { label = "No run" })
	Act.define("a.Bad", { label = "Bad", run = function() end })
	Act.define("BadId", { label = "Bad", run = function() end })
	Act.define("a.nilspec")
	Act.define("a.last", { label = "Last", run = function() end })
	Act.bind("a.last", { key = 5 })
	Act.bind("a.last", { key = "F7" })
end)
check("warn-skip: nothing raises", ok)
check(
	"warn-skip: valid binds around the bad ones still bind",
	find("F1") ~= nil and find("F7") ~= nil and find("F2") ~= nil
)
check("warn-skip: no bind for the rejected ones", #binds == 3 and find("F9") == nil)
check("warn-skip: one warning per problem", #Act.warnings == 8)
check("warn-skip: unknown id named", has(Act.warnings[1], "nope.missing"))
check("warn-skip: duplicate named", has(Act.warnings[2], "already defined"))
check("warn-skip: bad key named", has(Act.warnings[8], "non-empty string"))
check("warn-skip: first definition kept", find("F2") ~= nil and find("F2").opts.desc == "Dup")
check("warn-skip: one notification scheduled for all", #timers == 1)
timers[1]()
check(
	"warn-skip: notification carries the warnings",
	#notices == 1 and has(notices[1], "nope.missing") and has(notices[1], "already defined")
)
check("warn-skip: shown warnings are cleared", #Act.warnings == 0)
Act.bind("later.missing", { key = "F8" })
check("warn-skip: a later warning schedules a new notification", #timers == 2)
timers[2]()
check(
	"warn-skip: the later notification lists only the new warning",
	#notices == 2 and has(notices[2], "later.missing") and not has(notices[2], "nope.missing")
)

-- A handler or definition that raises inside define is caught.
fresh()
local boom_spec = setmetatable({}, {
	__index = function(_, key)
		if key == "label" then
			error("kaboom")
		end
	end,
})
ok = pcall(Act.define, "a.boom", boom_spec)
check("pcall: a define that raises warns instead", ok and #Act.warnings == 1 and has(Act.warnings[1], "kaboom"))

-- A failed hl.bind is caught too.
fresh()
bind_error = "no such key"
Act.define("a.badbind", { label = "Bad bind", run = function() end })
ok = pcall(Act.bind, "a.badbind", { key = "X" })
bind_error = nil
check("pcall: a failing hl.bind warns instead", ok and #Act.warnings == 1 and has(Act.warnings[1], "no such key"))

---------------------------------------------------------------------------------------------------
-- params
---------------------------------------------------------------------------------------------------
fresh()
local got
local probe_count = 0
local function define_probe(params)
	probe_count = probe_count + 1
	local id = "probe.p" .. probe_count
	Act.define(id, {
		label = "Probe",
		params = params,
		run = function(...)
			got = table.pack(...)
		end,
	})
	return id
end

local int_id = define_probe({ { name = "n", type = "int" } })
Act.run_cli(int_id, { "40" })
check("int: parsed", got.n == 1 and got[1] == 40 and got[1] % 1 == 0)
Act.run_cli(int_id, { "-5" })
check("int: negative with a leading dash", got[1] == -5)
Act.run_cli(int_id, { "+7" })
check("int: leading plus", got[1] == 7)
Act.run_cli(int_id, { "1000000000000000" })
check("int: sixteen digits within the safe range", got[1] == 1000000000000000)
Act.run_cli(int_id, { "-999999999999999" })
check("int: negative fifteen digits", got[1] == -999999999999999)
Act.run_cli(int_id, { "0000000000000000007" })
check("int: leading zeros", got[1] == 7)
Act.run(int_id, 1000000000000000)
check("int: run takes the same range", got[1] == 1000000000000000)
Act.run_cli(int_id, { "9007199254740991" })
check("int: the largest safe integer", got[1] == 9007199254740991)
for _, bad in ipairs({
	"",
	"1.0",
	"1e3",
	"0x10",
	" 1",
	"1 ",
	"abc",
	"9007199254740992",
	"99999999999999999999",
	"--5",
	"٣",
}) do
	check("int: rejects '" .. bad .. "'", has(raises(Act.run_cli, int_id, { bad }), "expects an int"))
end
check("int: run rejects 2^53", has(raises(Act.run, int_id, 2 ^ 53), "expects an int"))
check("int: run rejects a float value", has(raises(Act.run, int_id, 1.5), "expects an int"))
check("int: run rejects a string value", has(raises(Act.run, int_id, "3"), "expects an int"))
Act.run(int_id, 3)
check("int: run takes a Lua integer", got[1] == 3)

local float_id = define_probe({ { name = "x", type = "float" } })
for word, want in pairs({ ["0.5"] = 0.5, ["-2"] = -2, [".25"] = 0.25, ["3."] = 3, ["1e2"] = 100, ["-1.5E-1"] = -0.15 }) do
	Act.run_cli(float_id, { word })
	check("float: parses '" .. word .. "'", got[1] == want)
end
for _, bad in ipairs({ "", "nan", "inf", "-inf", "0x1p4", "1e999", ".", "1..2", "abc" }) do
	check("float: rejects '" .. bad .. "'", has(raises(Act.run_cli, float_id, { bad }), "expects a float"))
end
check("float: run rejects nan", has(raises(Act.run, float_id, 0 / 0), "expects a float"))
check("float: run rejects infinity", has(raises(Act.run, float_id, math.huge), "expects a float"))

local string_id = define_probe({ { name = "s", type = "string" } })
Act.run_cli(string_id, { "" })
check("string: empty is a string", got[1] == "")
Act.run_cli(string_id, { "-x" })
check("string: leading dash kept", got[1] == "-x")
check("string: run rejects a number", has(raises(Act.run, string_id, 5), "expects a string"))

local bool_id = define_probe({ { name = "b", type = "bool" } })
for word, want in pairs({ ["true"] = true, ["1"] = true, ["false"] = false, ["0"] = false }) do
	Act.run_cli(bool_id, { word })
	check("bool: parses '" .. word .. "'", got[1] == want)
end
for _, bad in ipairs({ "", "yes", "TRUE", "2", "nil" }) do
	check("bool: rejects '" .. bad .. "'", has(raises(Act.run_cli, bool_id, { bad }), "expects true, false"))
end
check("bool: run rejects a string", has(raises(Act.run, bool_id, "true"), "expects a bool"))

local enum_id = define_probe({ { name = "mode", type = "enum", values = { "on", "off" } } })
Act.run_cli(enum_id, { "off" })
check("enum: member accepted", got[1] == "off")
check("enum: non-member rejected", has(raises(Act.run_cli, enum_id, { "maybe" }), "expects one of on|off, got 'maybe'"))
check("enum: case matters", raises(Act.run_cli, enum_id, { "ON" }) ~= nil)
check("enum: run rejects a non-member", has(raises(Act.run, enum_id, "maybe"), "expects one of"))

-- A finite float too large for %d renders instead of raising.
Act.define("big.float", {
	label = "Big",
	params = { { name = "x", type = "float" } },
	run = Act.Cmd("echo", "{x}"),
})
local seen_exec = {}
local keep_exec = Act.exec
Act.exec = function(command)
	seen_exec[#seen_exec + 1] = command
end
check("float: run renders 1e19", raises(Act.run, "big.float", 1e19) == nil and seen_exec[1] == "echo 1e+19")
check(
	"float: run_cli renders 1e19",
	raises(Act.run_cli, "big.float", { "1e19" }) == nil and seen_exec[2] == "echo 1e+19"
)
check("float: run renders an integral float", raises(Act.run, "big.float", 3.0) == nil and seen_exec[3] == "echo 3")
Act.exec = keep_exec

-- NUL cuts a command line short in exec_cmd, so it is refused.
check("NUL: run_cli refuses a word with NUL", has(raises(Act.run_cli, string_id, { "a\0b" }), "NUL"))
check("NUL: run refuses a string value with NUL", has(raises(Act.run, string_id, "a\0b"), "NUL"))

-- Counts and defaults.
local two_id = define_probe({ { name = "a", type = "int" }, { name = "b", type = "int", default = 9 } })
Act.run_cli(two_id, { "1" })
check("default: trailing default fills in", got[1] == 1 and got[2] == 9 and got.n == 2)
Act.run_cli(two_id, { "1", "2" })
check("default: given value beats it", got[2] == 2)
check("count: too few", has(raises(Act.run_cli, two_id, {}), "needs at least 1"))
check("count: too many", has(raises(Act.run_cli, two_id, { "1", "2", "3" }), "takes at most 2"))
check("count: none for a no-param action", has(raises(Act.run_cli, define_probe(nil), { "x" }), "takes at most 0"))
Act.run_cli(define_probe(nil), {})
check("count: no-param action runs with none", got.n == 0)
Act.run(two_id, 4)
check("default: run fills defaults too", got[1] == 4 and got[2] == 9)
check("count: run checks too few", has(raises(Act.run, two_id), "needs at least 1"))
check("count: run checks too many", has(raises(Act.run, two_id, 1, 2, 3), "takes at most 2"))
check("count: error names the action", has(raises(Act.run, two_id), two_id))

-- Unknown ids at run time raise (unlike config time), so `hyprctl eval` fails loudly.
check("run: unknown id raises", has(raises(Act.run, "no.such"), "unknown action 'no.such'"))
check("run_cli: unknown id raises", has(raises(Act.run_cli, "no.such", {}), "unknown action 'no.such'"))
check("run_cli: non-table args raise", raises(Act.run_cli, int_id, "40") ~= nil)
check("run_cli: non-string word raises", raises(Act.run_cli, int_id, { 40 }) ~= nil)

-- A handler error propagates, so the caller sees it.
Act.define("probe.fails", {
	label = "Fails",
	run = function()
		error("handler failed", 0)
	end,
})
check("run: a handler error propagates", has(raises(Act.run_cli, "probe.fails", {}), "handler failed"))

-- Definition-time param checks.
fresh()
local function rejected(name, params, part)
	local count = #Act.warnings
	local made = Act.define("bad.p" .. count, { label = "Bad", params = params, run = function() end })
	check(name, made == nil and #Act.warnings == count + 1 and has(Act.warnings[count + 1], part))
end
rejected("params: unknown type", { { name = "n", type = "number" } }, "has type 'number'")
rejected("params: missing name", { { type = "int" } }, "needs a name")
rejected("params: bad name", { { name = "N", type = "int" } }, "needs a name")
rejected("params: duplicate name", { { name = "n", type = "int" }, { name = "n", type = "int" } }, "declared twice")
rejected(
	"params: default before required",
	{ { name = "a", type = "int", default = 1 }, { name = "b", type = "int" } },
	"defaults go last"
)
rejected("params: default of the wrong type", { { name = "a", type = "int", default = "x" } }, "default of 'a'")
rejected("params: enum without values", { { name = "a", type = "enum" } }, "needs a list of string values")
rejected(
	"params: enum default outside values",
	{ { name = "a", type = "enum", values = { "x" }, default = "y" } },
	"default of 'a'"
)
rejected("params: values on a non-enum", { { name = "a", type = "int", values = { "x" } } }, "not an enum")
rejected("params: not a list", "n", "params must be a list")
Act.define("ok.defaulted", {
	label = "Defaulted",
	params = { { name = "n", type = "int", default = 1 } },
	run = function() end,
})
Act.bind("ok.defaulted", { key = "K" })
check("params: a key without args may use defaults", find("K") ~= nil)

---------------------------------------------------------------------------------------------------
-- Ipc and Cmd
---------------------------------------------------------------------------------------------------
fresh()
local ipc = Act.Ipc("zoom", "toggle", "{n}", "plain")
check("Ipc: carries its data", ipc.kind == "ipc" and ipc.target == "zoom" and ipc["function"] == "toggle")
check("Ipc: carries its args", ipc.args[1] == "{n}" and ipc.args[2] == "plain" and #ipc.args == 2)
local cmd = Act.Cmd("~/bin/run", "{name}", "--flag")
check("Cmd: carries its argv", cmd.kind == "command" and #cmd.argv == 3 and cmd.argv[1] == "~/bin/run")
check("Cmd: a callable table", getmetatable(cmd).__call ~= nil)

Act.define("zoom.size", {
	label = "Zoom set",
	params = {
		{ name = "n", type = "int" },
		{ name = "mode", type = "enum", values = { "in", "out" }, default = "in" },
	},
	run = Act.Ipc("zoom", "size", "{n}", "{mode}"),
})
Act.run_cli("zoom.size", { "3" })
check("Ipc: renders typed params and defaults", executed[1] == "~/.config/hypr/scripts/qs-ipc call zoom size 3 in")
Act.run("zoom.size", 4, "out")
check("Ipc: run renders too", executed[2] == "~/.config/hypr/scripts/qs-ipc call zoom size 4 out")

-- resolve is run_cli's parse path without the performing
local before_resolve = #executed
local _, resolved_values, resolved_plan = Act.resolve("zoom.size", { "3" })
check("resolve: returns the typed values with defaults", resolved_values[1] == 3 and resolved_values[2] == "in")
check(
	"resolve: ipc plan has the rendered words",
	resolved_plan.kind == "ipc"
		and resolved_plan.target == "zoom"
		and resolved_plan["function"] == "size"
		and table.concat(resolved_plan.args, " ") == "3 in"
)
check("resolve: performs nothing", #executed == before_resolve)
check("resolve: a bad word raises as run_cli does", has(raises(Act.resolve, "zoom.size", { "x" }), "expects an int"))
check("resolve: an unknown id raises", has(raises(Act.resolve, "no.such", {}), "unknown action 'no.such'"))
Act.run_cli("zoom.size", { "3" })
check("resolve: run_cli still performs the same line", executed[#executed] == executed[1])
executed[#executed] = nil -- later sections count from the first lines
Act.define("zoom.toggle", { label = "Toggle", run = Act.Ipc("zoom", "toggle") })
Act.run_cli("zoom.toggle", {})
check("Ipc: no params", executed[3] == "~/.config/hypr/scripts/qs-ipc call zoom toggle")

Act.define("say.it", {
	label = "Say",
	params = { { name = "text", type = "string" }, { name = "other", type = "string", default = "x" } },
	run = Act.Cmd("~/bin/say", "{text}", "--other={other}", "-v"),
})
-- Single pass: a value that looks like a placeholder, or like the other param, stays literal text.
Act.run_cli("say.it", { "{other}", "{text}" })
check("render: single pass", executed[4] == "~/bin/say '{other}' '--other={text}' -v")
Act.run_cli("say.it", { "a {text} b" })
check("render: placeholder text inside a value", executed[5] == "~/bin/say 'a {text} b' --other=x -v")
check("render: an undeclared {name} is rejected at define", Act.define("say.bad", {
	label = "Bad",
	params = { { name = "text", type = "string" } },
	run = Act.Cmd("echo", "{typo}"),
}) == nil and has(Act.warnings[#Act.warnings], "{typo}"))
check("render: the program cannot be a placeholder", Act.define("say.bad3", {
	label = "Bad",
	params = { { name = "text", type = "string" } },
	run = Act.Cmd("{text}"),
}) == nil and has(Act.warnings[#Act.warnings], "program word"))
check("render: Ipc placeholders are checked too", Act.define("say.bad2", {
	label = "Bad",
	run = Act.Ipc("zoom", "size", "{n}"),
}) == nil)

---------------------------------------------------------------------------------------------------
-- Hostile strings from a shell
---------------------------------------------------------------------------------------------------
-- Every word is quoted for the shell. Prove it by running the produced command line through sh with a program
-- that prints its argv NUL-separated, and comparing with what was passed in.
local echo_count = 0
local function argv_through_sh(words)
	local quoted_cmd
	local original_exec = Act.exec
	Act.exec = function(command)
		quoted_cmd = command
	end
	echo_count = echo_count + 1
	local echo_id = "hostile.echo" .. echo_count
	Act.define(echo_id, {
		label = "Echo",
		params = { { name = "w", type = "string" } },
		run = Act.Cmd("printf", "%s\\0", "{w}"),
	})
	Act.run_cli(echo_id, words)
	Act.exec = original_exec
	local pipe = assert(io.popen(quoted_cmd, "r"))
	local out = pipe:read("a")
	pipe:close()
	return out, quoted_cmd
end

local hostile = {
	"plain",
	"it's",
	'say "hi"',
	"a]]b",
	"a]=]b",
	"a]==]b",
	"x]",
	"]",
	"x]=",
	"x]==",
	"line1\nline2",
	"{w}",
	"{param}",
	"-rf",
	"--",
	"-",
	"$(id)",
	"`id`",
	"a;b|c&d>e",
	"~",
	"~/x",
	"~root",
	"\\",
	"*",
	"",
	"  spaced  ",
	"%s",
	"\\0",
}
for _, word in ipairs(hostile) do
	local out = argv_through_sh({ word })
	check("sh round trip: " .. word:gsub("\n", "\\n"), out == word .. "\0")
end

-- The same strings reach a Lua handler untouched, and are never reinterpreted as placeholders.
Act.define("hostile.fn", {
	label = "Fn",
	params = { { name = "s", type = "string" }, { name = "t", type = "string", default = "{s}" } },
	run = function(s, t)
		got = { s, t }
	end,
})
for _, word in ipairs(hostile) do
	Act.run_cli("hostile.fn", { word })
	check("handler gets it verbatim: " .. word:gsub("\n", "\\n"), got[1] == word and got[2] == "{s}")
end

-- hypr-act (P3) hands run_cli its words as Lua long strings inside a chunk for `hyprctl eval`. Build that chunk
-- here, choosing a bracket level the word does not contain, and evaluate it.
local function long_string(word)
	local level = 0
	-- The closer is searched in word.."]" because a trailing "]" would otherwise merge with the closing bracket.
	while (word .. "]"):find("]" .. string.rep("=", level) .. "]", 1, true) do
		level = level + 1
	end
	local equals = string.rep("=", level)
	-- A newline right after the opening bracket is skipped by Lua, so one is added to keep a leading newline.
	return "[" .. equals .. "[\n" .. word .. "]" .. equals .. "]"
end
for _, word in ipairs(hostile) do
	local chunk = 'return require("lib.act").run_cli("hostile.fn", {' .. long_string(word) .. "})"
	local fn = assert(load(chunk))
	got = nil
	fn()
	check("eval chunk: " .. word:gsub("\n", "\\n"), got ~= nil and got[1] == word)
end
-- A word that tries to close the literal and run code is still just text.
local attack = "]])os.exit(7)--"
got = nil
assert(load('return require("lib.act").run_cli("hostile.fn", {' .. long_string(attack) .. "})"))()
check("eval chunk: closing bracket attack stays text", got ~= nil and got[1] == attack)

-- A bad word raises from the chunk (so eval exits non-zero) rather than silently doing nothing.
local bad_chunk = assert(load('return require("lib.act").run_cli("workspace.focus", {"x"})'))
Act.define("workspace.focus", {
	label = "Workspace",
	params = { { name = "n", type = "int" } },
	run = function() end,
})
check("eval chunk: a bad param raises", has(raises(bad_chunk), "expects an int"))

---------------------------------------------------------------------------------------------------
-- list / write_list
---------------------------------------------------------------------------------------------------
fresh()
local Json = require("lib.json")
Act.define("zoom.toggle", {
	label = "Zoom",
	intent = "Toggle zoom.",
	run = Act.Ipc("zoom", "toggle", "{n}"),
	params = { { name = "n", type = "int", default = 1 } },
})
Act.bind("zoom.toggle", { key = { key = "Z", leader = true } })
Act.bind("zoom.toggle", { key = { key = "Print", universal = true } })
Act.define("a.first", { label = "First", run = function() end })
Act.define("mode.set", {
	label = "Mode",
	params = { { name = "m", type = "enum", values = { "a", "b" } } },
	run = Act.Cmd("~/x.sh", "{m}"),
})

local listed = Json.decode(Act.list_json())
check("list: version 1", listed.version == 1)
check(
	"list: sorted by id",
	listed.actions[1].id == "a.first" and listed.actions[2].id == "mode.set" and listed.actions[3].id == "zoom.toggle"
)
local first, mode, zoom = listed.actions[1], listed.actions[2], listed.actions[3]
check(
	"list: keyless action has no keys, no params, a null intent",
	#first.keys == 0 and #first.params == 0 and first.intent == nil
)
check("list: lua perform", first.perform.kind == "lua")
check("list: leader applied to the key", zoom.keys[1].key == "SUPER + Z" and zoom.keys[1].leader == true)
check("list: second key follows, universal kept", zoom.keys[2].key == "Print" and zoom.keys[2].universal == true)
check(
	"list: ipc perform",
	zoom.perform.kind == "ipc"
		and zoom.perform.target == "zoom"
		and zoom.perform["function"] == "toggle"
		and zoom.perform.args[1] == "{n}"
)
check(
	"list: param default only when set",
	zoom.params[1].default == 1 and zoom.params[1].values == nil and mode.params[1].default == nil
)
check("list: enum values", mode.params[1].values[2] == "b")
check("list: command perform", mode.perform.kind == "command" and mode.perform.argv[1] == "~/x.sh")
check(
	"list: null intent and empty arrays are written out",
	Act.list_json():find('"intent":null', 1, true) and Act.list_json():find('"keys":[]', 1, true)
)

-- Keys changed after the keymaps loaded, as custom/init.lua does, show in the list: an Act.bind key is added and an
-- unbound shipped key is dropped.
fresh()
local Bind = require("lib.key.bind")
Act.define("zoom.toggle", { label = "Zoom", run = function() end })
Act.bind("zoom.toggle", { key = { key = "Z", leader = true } })
Act.bind("zoom.toggle", { key = "ALT + X" })
local before = Json.decode(Act.list_json()).actions[1].keys
check(
	"custom keys: shipped and added key listed",
	#before == 2 and before[1].key == "SUPER + Z" and before[2].key == "ALT + X"
)
Bind.leader_unbind("Z")
local after = Json.decode(Act.list_json()).actions[1].keys
check("custom keys: unbound shipped key dropped, added key kept", #after == 1 and after[1].key == "ALT + X")
Bind.unbind("ALT + X")
check("custom keys: all unbound gives no keys", #Json.decode(Act.list_json()).actions[1].keys == 0)

-- A key unbound and then bound again must not revive the old association.
local function keys_of(action_id)
	for _, action in ipairs(Json.decode(Act.list_json()).actions) do
		if action.id == action_id then
			return action.keys
		end
	end
end
fresh()
Bind = require("lib.key.bind")
Act.define("a.one", { label = "One", run = function() end })
Act.bind("a.one", { key = "ALT + Q" })
Act.define("a.two", { label = "Two", run = function() end })
Bind.unbind("ALT + Q")
Act.bind("a.two", { key = "ALT + Q" })
check("rebind: key moved to another action leaves the old one", #keys_of("a.one") == 0)
check("rebind: key moved to another action lists on the new one", #keys_of("a.two") == 1)

fresh()
Bind = require("lib.key.bind")
Act.define("a.one", { label = "One", run = function() end })
Act.bind("a.one", { key = "ALT + Q" })
Bind.unbind("ALT + Q")
Bind.key("ALT + Q", function() end, "plain callback")
check("rebind: key reused by a plain callback leaves the action", #keys_of("a.one") == 0)

fresh()
Bind = require("lib.key.bind")
Act.define("a.one", { label = "One", run = function() end })
Act.bind("a.one", { key = "ALT + Q" })
Bind.unbind("ALT + Q")
Act.bind("a.one", { key = "ALT + Q" })
check("rebind: same action lists the key once", #keys_of("a.one") == 1)

-- The picker and HyprVim actions (lib/act/defs/pickers.lua, keys from keymaps/global/pickers.lua): same keys and
-- labels as the binds they replaced, and running one calls the Menu closure or the hyprvim module once.
fresh()
Bind = require("lib.key.bind")
local menu_calls, hyprvim_calls = {}, {}
package.loaded["lib.desktop.menu"] = setmetatable({}, {
	__index = function(_, name)
		return function()
			return function()
				menu_calls[#menu_calls + 1] = name
			end
		end
	end,
})
package.loaded["lua.plugins.hyprvim"] = {
	command = {
		prompt = function()
			hyprvim_calls[#hyprvim_calls + 1] = "prompt"
		end,
	},
	marks = {
		enter_jump = function()
			hyprvim_calls[#hyprvim_calls + 1] = "enter_jump"
		end,
	},
	editor = {
		open = function(opts)
			hyprvim_calls[#hyprvim_calls + 1] = "open_" .. tostring(opts.insert_mode)
		end,
	},
}
assert(loadfile(hypr_dir .. "/keymaps/global/pickers.lua"))()
check("pickers: no warnings, six binds", #Act.warnings == 0 and #binds == 6)
local picker_keys = {
	{ "picker.clipboard", "Clipboard History", "SUPER + CTRL + V", "clipboard" },
	{ "picker.directory", "Jump to Directory", "SUPER + CTRL + SPACE", "zoxide" },
	{ "picker.emoji", "Emoji Picker", "SUPER + CTRL + E", "emoji" },
}
for _, row in ipairs(picker_keys) do
	local id, label, key, menu_name = row[1], row[2], row[3], row[4]
	local entry = find(key)
	check("pickers: " .. id .. " binds " .. key .. " as '" .. label .. "'", entry ~= nil and entry.opts.desc == label)
	menu_calls = {}
	Act.run_cli(id, {})
	check("pickers: " .. id .. " runs Menu." .. menu_name .. " once", #menu_calls == 1 and menu_calls[1] == menu_name)
	check("pickers: " .. id .. " takes no args", has(raises(Act.run_cli, id, { "x" }), "takes at most 0"))
end
-- Keyless: only the clipboard picker's delete mode opens through it.
menu_calls = {}
Act.run_cli("picker.clipboard_delete", {})
check(
	"pickers: picker.clipboard_delete runs Menu.clipboard_delete",
	#menu_calls == 1 and menu_calls[1] == "clipboard_delete"
)
-- Keyless globally: the Leader and Go rows bind it.
menu_calls = {}
Act.run_cli("picker.agents", {})
check("pickers: picker.agents runs Menu.agents_picker", #menu_calls == 1 and menu_calls[1] == "agents_picker")
check(
	"hyprvim: terminal binds SHIFT + SEMICOLON",
	find("SUPER + SHIFT + SEMICOLON") ~= nil and find("SUPER + SHIFT + SEMICOLON").opts.desc == "HyprVim Terminal"
)
check(
	"hyprvim: jump mark binds APOSTROPHE",
	find("SUPER + APOSTROPHE") ~= nil and find("SUPER + APOSTROPHE").opts.desc == "Jump to Mark"
)
Act.run("hyprvim.terminal")
Act.run("hyprvim.jump_mark")
Act.run("hyprvim.edit_selection")
check(
	"hyprvim: edit selection binds N as 'Edit Selection in Vim'",
	find("SUPER + N") ~= nil and find("SUPER + N").opts.desc == "Edit Selection in Vim"
)
check(
	"hyprvim: each action calls its module once",
	#hyprvim_calls == 3
		and hyprvim_calls[1] == "prompt"
		and hyprvim_calls[2] == "enter_jump"
		and hyprvim_calls[3] == "open_true"
)
local picker_listed = 0
for _, handle in ipairs(Act.list()) do
	if handle.id:match("^picker%.") or handle.id:match("^hyprvim%.") then
		picker_listed = picker_listed + 1
		check("pickers: " .. handle.id .. " has an intent", handle.intent ~= nil and handle.intent ~= "")
	end
end
check("pickers: eight listed", picker_listed == 8)
package.loaded["lib.desktop.menu"] = nil
package.loaded["lua.plugins.hyprvim"] = nil

local list_path = os.tmpname()
local write_chunk = assert(load('require("lib.act").write_list([=====[' .. list_path .. "]=====])"))
write_chunk()
local list_file = assert(io.open(list_path))
local written = list_file:read("a")
list_file:close()
os.remove(list_path)
check("write_list: file holds the list from an eval-style chunk", written == Act.list_json() .. "\n")

if failures > 0 then
	print(failures .. " failed, " .. passed .. " passed")
	os.exit(1)
end
print("action: " .. passed .. " passed")
