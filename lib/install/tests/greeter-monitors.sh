#!/usr/bin/env bash
# Tests the greeter's generated monitor rules: the generator against fixture profiles, the installer's fall-back to an
# empty file, and that the greeter's hyprland.lua still loads when monitors.lua is missing or throws. Needs no Hyprland.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
if ! command -v lua >/dev/null 2>&1; then
  echo "skip: the greeter monitor test needs lua"
  exit 0
fi
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/greeter.sh"

failures=0
case_name=''
fail() {
  printf 'FAIL %s: %s\n' "$case_name" "$1" >&2
  failures=$((failures + 1))
}
expect_eq() { [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }

machines=$scratch/machines
state=$scratch/monitors.json
mkdir -p "$machines"
export HOSTNAME=testhost
export HYPR_MACHINES_DIR=$machines
export XDG_STATE_HOME=$scratch/state
mkdir -p "$XDG_STATE_HOME/hypr"
state=$XDG_STATE_HOME/hypr/monitors.json

cat >"$scratch/print_outputs.lua" <<'LUA'
hl = { monitor = function(rule) print(rule.output) end }
dofile(arg[1])
LUA

generate() { lua "$GREETER_MONITORS_GENERATOR" "$machines" "$state" 2>"$scratch/gen.err"; }
rules() { grep -v '^--' <<<"$1"; }

cat >"$machines/testhost.lua" <<'LUA'
return {
  path_prepend = { "/ignored" },
  monitors = {
    { description = "BOE 0x0C8E", mode = "2560x1600@240", position = "317x1080", scale = 1.6 },
    { description = "HP Z22n", mode = "1920x1080@60", position = "4480x0", scale = 1, transform = 3 },
    { description = 'Odd "quoted" 100% panel', mode = "1920x1080@60", position = "0x0" },
    { name = "DP-9", position = "10x20" },
    { id = 3, mode = "1920x1080@60" },
  },
}
LUA

case_name='a normal profile gives one rule per entry, in the session mode'
out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" 'hl.monitor({ output = "desc:BOE 0x0C8E", mode = "2560x1600@240", position = "317x1080", scale = 1.6 })
hl.monitor({ output = "desc:HP Z22n", mode = "1920x1080@60", position = "4480x0", scale = 1, transform = 3 })
hl.monitor({ output = "desc:Odd \"quoted\" 100% panel", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-9", mode = "preferred", position = "10x20", scale = 1 })'

case_name='an id-only entry is skipped, and a description with quotes and a percent sign loads as the same string'
[[ $out != *"id"* ]] || fail 'id-only entry leaked into the output'
printf '%s\n' "$out" >"$scratch/quoted.lua"
recorded=$(lua "$scratch/print_outputs.lua" "$scratch/quoted.lua" | sed -n 3p)
expect_eq "$recorded" 'desc:Odd "quoted" 100% panel'

case_name='monitors.json overrides replace fields, and disabled is ignored'
cat >"$state" <<'JSON'
{"monitors":{
  "BOE 0x0C8E":{"mode":"2560x1600@120","position":"0x0","scale":2,"transform":1,"description":true},
  "HP Z22n":{"disabled":true,"description":true},
  "Dark One":{"disabled":true,"description":true},
  "Extra Panel":{"mode":"1280x720@60","position":"9x9","scale":1.25,"description":true}
}}
JSON
out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" 'hl.monitor({ output = "desc:BOE 0x0C8E", mode = "2560x1600@120", position = "0x0", scale = 2, transform = 1 })
hl.monitor({ output = "desc:HP Z22n", mode = "1920x1080@60", position = "4480x0", scale = 1, transform = 3 })
hl.monitor({ output = "desc:Odd \"quoted\" 100% panel", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-9", mode = "preferred", position = "10x20", scale = 1 })
hl.monitor({ output = "desc:Extra Panel", mode = "1280x720@60", position = "9x9", scale = 1.25 })'
[[ $out != *disabled* && $out != *"Dark One"* ]] || fail 'a disabled override reached the output'

case_name='a malformed monitors.json is ignored'
printf '{not json' >"$state"
out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
[[ $(rules "$out" | wc -l) -eq 4 ]] || fail 'profile rules lost to a bad state file'
rm -f "$state"

case_name='a missing machine file gives no rules and succeeds'
export HOSTNAME=nosuchhost
out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" ''
case_name='an empty monitor list gives no rules'
printf 'return { monitors = {} }\n' >"$machines/emptyhost.lua"
HOSTNAME=emptyhost out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" ''
export HOSTNAME=testhost

cat >"$machines/default.lua" <<'LUA'
return { monitors = { { description = "Default Panel", mode = "1280x720@60", position = "0x0" } } }
LUA
default_rule='hl.monitor({ output = "desc:Default Panel", mode = "1280x720@60", position = "0x0", scale = 1 })'
case_name='default.lua monitors apply when the hostname has no profile'
HOSTNAME=nosuchhost out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" "$default_rule"
case_name='the hostname profile replaces default.lua monitors'
export HOSTNAME=testhost
out=$(generate)
[[ $out != *"Default Panel"* ]] || fail 'default monitors leaked past the hostname list'
case_name='a hostname profile without monitors falls back to default.lua, as does an empty list'
printf 'return { wallpaper_location = true }\n' >"$machines/nomonhost.lua"
HOSTNAME=nomonhost out=$(generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" "$default_rule"
HOSTNAME=emptyhost out=$(generate)
expect_eq "$(rules "$out")" "$default_rule"
rm "$machines/default.lua"
export HOSTNAME=testhost

case_name='an unplugged monitor still gets its desc: rule, so a later plug-in is placed'
out=$(generate)
grep -Fq 'output = "desc:HP Z22n"' <<<"$out" || fail 'rule for an absent monitor was dropped'

cat >"$machines/dockhost.lua" <<'LUA'
return {
  monitors = {
    { description = "Panel", mode = "2560x1600@240", position = "0x0", scale = 1.6 },
    { description = "Dock A", mode = "1920x1080@60", position = "2560x0", start_delay_ms = 3000 },
    { name = "DP-5", transform = 3, start_delay_ms = 1500 },
    { description = "Dock C", mode = "1920x1080@60", position = "0x1600", start_delay_ms = 0 },
  },
}
LUA
case_name='a delayed entry goes into GREETER_HELD with its full rule instead of a monitor rule'
out=$(HOSTNAME=dockhost generate) || fail "generator failed: $(cat "$scratch/gen.err")"
expect_eq "$(rules "$out")" 'hl.monitor({ output = "desc:Panel", mode = "2560x1600@240", position = "0x0", scale = 1.6 })
GREETER_HELD[#GREETER_HELD + 1] = { delay = 3000, rule = { output = "desc:Dock A", mode = "1920x1080@60", position = "2560x0", scale = 1 } }
GREETER_HELD[#GREETER_HELD + 1] = { delay = 1500, rule = { output = "DP-5", mode = "preferred", position = "auto", scale = 1, transform = 3 } }
hl.monitor({ output = "desc:Dock C", mode = "1920x1080@60", position = "0x1600", scale = 1 })'

case_name='the installer writes the rules to the file it is given'
write_greeter_monitors "$scratch/installed.lua" 2>/dev/null
expect_eq "$(rules "$(cat "$scratch/installed.lua")" | wc -l)" 4

case_name='a broken profile warns and the installer writes an empty stub'
printf 'return { monitors = {\n' >"$machines/brokenhost.lua"
warning=$(HOSTNAME=brokenhost write_greeter_monitors "$scratch/broken.lua" 2>&1 >/dev/null)
[[ $warning == *"Could not generate"* ]] || fail "no warning: [$warning]"
expect_eq "$(rules "$(cat "$scratch/broken.lua")")" ''
case_name='a profile that returns the wrong type warns and writes the stub'
printf 'return 5\n' >"$machines/brokenhost.lua"
warning=$(HOSTNAME=brokenhost write_greeter_monitors "$scratch/broken2.lua" 2>&1 >/dev/null)
[[ $warning == *"Could not generate"* ]] || fail "no warning: [$warning]"

# The greeter's hyprland.lua, pointed at the scratch dir, under a recorder for hl.
greetd=$scratch/greetd
mkdir -p "$greetd"
printf 'nobody\n' >"$greetd/admin_user"
sed "s#\"/etc/greetd\"#\"$greetd\"#" "$repo_dir/system/etc/greetd/hyprland.lua" >"$scratch/hyprland.lua"
cat >"$scratch/record_calls.lua" <<'LUA'
local calls = {}
local function noop() end
local proxy
proxy = setmetatable({}, { __index = function() return proxy end, __call = function() return {} end })
hl = setmetatable({ monitor = function(rule) calls[#calls + 1] = rule.output end }, { __index = function() return noop end })
hl.dsp = proxy
dofile(arg[1])
print(table.concat(calls, "|"))
LUA
load_greeter_config() { XDG_RUNTIME_DIR=$scratch/run lua "$scratch/record_calls.lua" "$scratch/hyprland.lua" 2>&1 </dev/null; }

case_name='hyprland.lua loads with monitors.lua missing and still applies the catch-all'
rm -f "$greetd/monitors.lua"
# The catch-all's output is the empty string, so the recorded list is empty.
expect_eq "$(load_greeter_config)" ''

case_name='hyprland.lua loads with monitors.lua throwing, keeping the rules before the error and the catch-all'
printf 'hl.monitor({ output = "first" })\nerror("boom")\nhl.monitor({ output = "never" })\n' >"$greetd/monitors.lua"
result=$(load_greeter_config)
[[ $result == *"greetd: monitors.lua failed"*"first"* ]] || fail "unexpected: [$result]"
[[ $result != *never* ]] || fail 'ran past the error'

case_name='hyprland.lua loads with a syntax error in monitors.lua'
printf 'hl.monitor({\n' >"$greetd/monitors.lua"
result=$(load_greeter_config)
[[ $result == *"greetd: monitors.lua failed"* ]] || fail "unexpected: [$result]"

case_name='hyprland.lua applies the generated rules ahead of the catch-all'
generate >"$greetd/monitors.lua"
expect_eq "$(load_greeter_config)" 'desc:BOE 0x0C8E|desc:HP Z22n|desc:Odd "quoted" 100% panel|DP-9|'

case_name='the install commands put monitors.lua in /etc/greetd and keep it out of the Quickshell rsync'
cmds=$(greeter_install_cmds /stage /repo)
grep -Fq "sudo install -Dm644 '/stage/monitors.lua' '/etc/greetd/monitors.lua'" <<<"$cmds" || fail 'monitors.lua is not installed'
grep -Fq -- '--exclude=/monitors.lua' <<<"$cmds" || fail 'monitors.lua would land in the Quickshell dir'

# The greeter's late-monitor hold, under a fake hl that records rules and runs timers on demand.
HOSTNAME=dockhost generate >"$greetd/monitors.lua"
cat >"$scratch/late_monitors.lua" <<'LUA'
local lit, timers, reloads = tonumber(arg[2]), {}, 0
local proxy
proxy = setmetatable({}, { __index = function() return proxy end, __call = function() return {} end })
local function record(rule)
  if rule.output ~= "" then print(rule.output .. " disabled=" .. tostring(rule.disabled) .. " mode=" .. tostring(rule.mode)) end
end
hl = setmetatable({
  monitor = record,
  timer = function(fn, opts) timers[#timers + 1] = fn print("timer " .. opts.timeout) end,
  get_monitors = function()
    local list = {}
    for i = 1, lit do list[i] = { name = "X-" .. i, description = "Panel " .. i } end
    if arg[4] == "dock_listed" then list[#list + 1] = { name = "DP-1", description = "Dock A" } end
    return list
  end,
  dispatch = function() reloads = reloads + 1 end,
}, { __index = function() return function() end end })
hl.dsp = proxy
dofile(arg[1])
print("-- " .. arg[3])
if arg[3] == "handoff" then GREETER_HANDOFF() end
for _, fn in ipairs(timers) do fn() end
if arg[3] == "release_handoff" then
  -- The release reloads the config, which runs hyprland.lua again in the same Lua state.
  dofile(arg[1])
  print("-- handoff")
  GREETER_HANDOFF()
end
print("reloads=" .. reloads)
LUA
late() { HYPRLAND_INSTANCE_SIGNATURE=test XDG_RUNTIME_DIR=$scratch/run lua "$scratch/late_monitors.lua" "$scratch/hyprland.lua" "$@" 2>&1 </dev/null | grep -v '^desc:Panel\|^desc:Dock C'; }
mkdir -p "$scratch/run/hypr/test"

case_name='held monitors start disabled, and with another monitor lit the timer leaves them dark'
expect_eq "$(late 1 timers)" 'desc:Dock A disabled=true mode=nil
DP-5 disabled=true mode=nil
timer 3000
-- timers
reloads=0'
[[ ! -e $scratch/run/hypr/test/greeter-monitors-released ]] || fail 'a marker was written without a release'

case_name='a held monitor Hyprland lists does not count as lit, so the timer still falls back to the dock'
result=$(late 0 timers dock_listed)
[[ $result == *"reloads=1"* ]] || fail "expected one reload: [$result]"
rm -f "$scratch/run/hypr/test/greeter-monitors-released"

case_name='the handoff after a dark-dock greeter disables nothing, and a pending timer does not light them'
expect_eq "$(late 1 handoff)" 'desc:Dock A disabled=true mode=nil
DP-5 disabled=true mode=nil
timer 3000
-- handoff
reloads=0'

case_name='the handoff before an undocked fallback release lights nothing'
expect_eq "$(late 0 handoff)" 'desc:Dock A disabled=true mode=nil
DP-5 disabled=true mode=nil
timer 3000
-- handoff
reloads=0'

case_name='the handoff after a fallback release still disables the dock'
rm -f "$scratch/run/hypr/test/greeter-monitors-released"
result=$(late 0 release_handoff)
[[ $result == *"-- handoff"*"desc:Dock A disabled=true"*"reloads=1"* ]] || fail "unexpected: [$result]"
rm -f "$scratch/run/hypr/test/greeter-monitors-released"

case_name='with no other monitor lit, the release reloads once, and the reload applies the rules without a hold'
result=$(late 0 timers)
[[ $result == *"reloads=1"* ]] || fail "expected one reload: [$result]"
[[ -e $scratch/run/hypr/test/greeter-monitors-released ]] || fail 'no marker for the reload'
expect_eq "$(late 0 timers)" 'desc:Dock A disabled=nil mode=1920x1080@60
DP-5 disabled=nil mode=preferred
-- timers
reloads=0'
rm -f "$scratch/run/hypr/test/greeter-monitors-released"

if ((failures)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "greeter-monitors: all passed"
