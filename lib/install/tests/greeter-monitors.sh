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

case_name='an unplugged monitor still gets its desc: rule, so a later plug-in is placed'
out=$(generate)
grep -Fq 'output = "desc:HP Z22n"' <<<"$out" || fail 'rule for an absent monitor was dropped'

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

if ((failures)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "greeter-monitors: all passed"
