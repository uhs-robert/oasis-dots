#!/usr/bin/env bash
# Tests the shadow's private audio and backlight: the generated PipeWire conf has no hardware or session-manager path,
# PipeWire starts only with the shadow's env and runtime dir (never the owner's PipeWire variables), `volume` and
# `brightness` refuse without a socket or fake device inside the runtime dir and build the calls they should,
# `teardown` sweeps the PipeWire session, `--no-audio` starts nothing, and the generated brightnessctl stub serves and
# changes only the fake device. Recording stubs stand in for pipewire, pw-dump and pw-cli; no shadow, Hyprland or sound
# card is involved. Runs from a temp dir and fails if the repo's `git status` differs afterwards.
# shellcheck disable=SC2154 # the sourced script assigns runtime, base, shim_dir, logs and shadow_home
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
failures=0
before=$(git -C "$checkout_root" status --porcelain)

fail() {
  failures=$((failures + 1))
  echo "FAIL $*" >&2
}

# The owner's PipeWire and bus, which must never reach a shadow process.
export PIPEWIRE_RUNTIME_DIR=/run/user/owner-pw PIPEWIRE_REMOTE=/run/user/owner-pw/pipewire-0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/owner-bus
export XDG_CACHE_HOME=$work/cache
cd "$work" || exit 1

# shellcheck source=/dev/null # the shadow script, sourced for its functions only
source "$checkout_root/.claude/skills/shadow/shadow.sh"
set +e +o pipefail

# Per-run names so two runs at once never share a runtime dir (at most 8 characters).
run_id=$(((RANDOM << 15 | RANDOM) % 1000000))
na=a$run_id
nb=b$run_id
nc=c$run_id
nd=d$run_id
# The real shadow_pids reads every /proc/*/environ; the sessions in the .sid files are what is under test here.
shadow_pids() { :; }
cleanup() {
  local n
  for n in "$na" "$nb" "$nc" "$nd"; do
    set_name "$n"
    kill_session pipewire
    rm -rf "$runtime"
  done
  rm -rf "$work"
}
trap cleanup EXIT

calls=$work/calls
ipc() {
  printf '[%s]' "$@" >>"$calls"
  echo >>"$calls"
}

make_shadow() {
  set_name "$1"
  mkdir -p "$runtime" "$shim_dir" "$logs"
  : >"$calls"
  cat >"$shim_dir/pipewire" <<'STUB'
#!/bin/bash
# Records the environment and arguments, makes the socket like the daemon does, then idles under a countable argv0.
{ env; echo "ARGS $*"; } >"$XDG_RUNTIME_DIR/pipewire.env"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$XDG_RUNTIME_DIR/pipewire-0"
exec -a "fakepipewire-test:$XDG_RUNTIME_DIR" sleep 300
STUB
  cat >"$shim_dir/pw-dump" <<'STUB'
#!/bin/sh
[ -S "$XDG_RUNTIME_DIR/pipewire-0" ] || exit 1
echo '[{"id":24,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"shadow_sink"}}}]'
STUB
  cat >"$shim_dir/pw-cli" <<'STUB'
#!/bin/sh
{ echo "ARGS $*"; echo "REMOTE=$PIPEWIRE_RUNTIME_DIR"; env | grep -c owner-pw; } >>"$XDG_RUNTIME_DIR/pw-cli.calls"
exit 0
STUB
  chmod +x "$shim_dir/pipewire" "$shim_dir/pw-dump" "$shim_dir/pw-cli"
}

players_of() { pgrep -f "^fakepipewire-test:$runtime "; }

# The generated conf reaches no hardware, camera, Bluetooth or session manager.
make_shadow "$na"
write_pipewire_conf
conf=$base/pipewire.conf
grep -qiE 'alsa|bluez|v4l2|libcamera|jack|wireplumber|portal|libpipewire-module-rt' "$conf" && fail "the conf names a hardware or session path: $(grep -iE 'alsa|bluez|v4l2|libcamera|jack|wireplumber|portal' "$conf")"
grep -q 'support.null-audio-sink' "$conf" || fail "the conf has no null sink"
grep -q 'default.audio.sink' "$conf" || fail "the conf sets no default sink"

# volume and brightness refuse while the shadow has no socket or fake device.
(volume "$na" 40) 2>/dev/null && fail "volume ran without a PipeWire socket"
[[ ! -e $runtime/pw-cli.calls ]] || fail "volume called pw-cli without a socket"
rm -rf "$runtime/backlight"
(brightness "$na" 40) 2>/dev/null && fail "brightness ran without a fake device"
(volume "$na" 101) 2>/dev/null && fail "volume accepted 101"
(brightness "$na" 0) 2>/dev/null && fail "brightness accepted 0"

# Case: PipeWire starts with the shadow's env and runtime dir only.
setup_audio 1 || fail "setup_audio 1 failed"
[[ -f $base/pipewire.sid ]] || fail "no pipewire.sid"
if [[ ! -f $runtime/pipewire.env ]]; then
  fail "the stub pipewire never ran"
else
  env_file=$runtime/pipewire.env
  grep -qx "PIPEWIRE_RUNTIME_DIR=$runtime" "$env_file" || fail "PIPEWIRE_RUNTIME_DIR is not the shadow's: $(grep PIPEWIRE "$env_file")"
  grep -qx "XDG_RUNTIME_DIR=$runtime" "$env_file" || fail "XDG_RUNTIME_DIR is not the shadow's"
  grep -qx "HOME=$shadow_home" "$env_file" || fail "HOME is not the shadow's"
  grep -q 'owner-pw\|owner-bus' "$env_file" && fail "an owner variable reached PipeWire: $(grep 'owner-' "$env_file")"
  grep -qx "ARGS -c $base/pipewire.conf" "$env_file" || fail "pipewire args wrong: $(grep ARGS "$env_file")"
fi
# The shadow env must not hide the client config: pw-dump loads it before it connects, so no daemon is needed.
if command -v pw-dump >/dev/null; then
  pw_out=$("${shadow_env[@]}" timeout 5 /usr/bin/env PATH="$system_path" pw-dump 2>&1 </dev/null)
  [[ $pw_out == *"load config"* ]] && fail "pw-dump cannot load its config in the shadow env: $pw_out"
fi
[[ $(players_of | wc -l) == 1 ]] || fail "expected one PipeWire process, got $(players_of | wc -l)"
[[ ! -e $base/no-audio ]] || fail "a shadow with audio was marked no-audio"
[[ $(expected_errors) == '^$' ]] || fail "audio shadow still expects the PipeWire error"

# volume builds the call and stays inside the runtime dir.
volume "$na" 40 || fail "volume 40 failed"
volume "$na" mute || fail "volume mute failed"
volume "$na" unmute || fail "volume unmute failed"
pw_calls=$runtime/pw-cli.calls
grep -qx 'ARGS s 24 Props { mute: false, channelVolumes: \[ 0.064000, 0.064000 \] }' "$pw_calls" || fail "volume 40 call wrong: $(grep ARGS "$pw_calls")"
grep -qx 'ARGS s 24 Props { mute: true }' "$pw_calls" || fail "mute call wrong"
grep -qx 'ARGS s 24 Props { mute: false }' "$pw_calls" || fail "unmute call wrong"
[[ $(grep -c "^REMOTE=$runtime$" "$pw_calls") == 3 ]] || fail "pw-cli did not get the shadow's runtime dir every time"
[[ $(grep -c '^[1-9]' "$pw_calls") == 0 ]] || fail "an owner variable reached pw-cli"

# brightness writes the fake device and asks the bar to re-read it.
write_backlight
brightness "$na" 40 || fail "brightness 40 failed"
[[ $(<"$(fake_backlight_dir)/brightness") == 102 ]] || fail "brightness 40 wrote $(<"$(fake_backlight_dir)/brightness"), wanted 102"
[[ $(<"$calls") == "[$na][brightness][refresh]" ]] || fail "brightness ipc call wrong: $(<"$calls")"

# teardown (what down runs) sweeps the PipeWire session.
teardown >/dev/null 2>&1 || fail "teardown failed"
[[ $(players_of | wc -l) == 0 ]] || fail "down left PipeWire running"
[[ ! -d $runtime ]] || fail "down left the runtime dir"

# A failed start (what `up` runs: abort_up on the EXIT trap after die) kills the PipeWire it launched, keeps the logs and
# removes the runtime dir. The stub stays alive in both cases, so a missing kill shows as a player left behind.
failed_start() {
  local label=$1 want=$2 out rc
  # Polls faster than the real wait_for so the timeouts cost 2 s and 1.2 s; scoped to this call so the passing start keeps the real one.
  out=$(
    (
      wait_for() {
        local tries=$1
        shift
        for _ in $(seq "$tries"); do
          "$@" && return 0
          sleep 0.02
        done
        return 1
      }
      trap abort_up EXIT
      setup_audio 1
    ) 2>&1
  )
  rc=$?
  [[ $rc == 1 ]] || fail "$label: exit code $rc, wanted 1"
  [[ $out == *"$want"* ]] || fail "$label: error text missing '$want': $out"
  [[ $out == *"== pipewire.log"*"pipewire stub: $label"* ]] || fail "$label: abort_up did not tail pipewire.log: $out"
  [[ $out == *"logs kept in $logs"* ]] || fail "$label: abort_up did not name the kept logs: $out"
  [[ $(players_of | wc -l) == 0 ]] || fail "$label: PipeWire left running"
  [[ ! -d $runtime ]] || fail "$label: the runtime dir was left"
  [[ ! -e $base/pipewire.sid ]] || fail "$label: pipewire.sid was left"
  [[ -f $logs/pipewire.log ]] || fail "$label: the logs were not kept"
}

# Case: no sink appears (pw-dump lists nothing).
make_shadow "$nc"
printf '#!/bin/sh\necho []\n' >"$shim_dir/pw-dump"
sed -i '2i echo "pipewire stub: no sink" >&2' "$shim_dir/pipewire"
failed_start "no sink" "the shadow sink never appeared"

# Case: no socket appears (the daemon runs but never binds).
make_shadow "$nd"
printf '#!/bin/bash\necho "pipewire stub: no socket" >&2\nexec -a "fakepipewire-test:$XDG_RUNTIME_DIR" sleep 300\n' >"$shim_dir/pipewire"
failed_start "no socket" "PipeWire made no socket"

# --no-audio starts nothing and brings the expected PipeWire error back.
make_shadow "$nb"
setup_audio 0
[[ ! -e $base/pipewire.sid && ! -e $runtime/pipewire.env ]] || fail "--no-audio started PipeWire"
[[ -f $base/no-audio ]] || fail "--no-audio left no marker"
[[ $(expected_errors) == quickshell.service.pipewire ]] || fail "--no-audio does not expect the PipeWire error"
(volume "$nb" 40) 2>/dev/null && fail "volume ran in a --no-audio shadow"

# The brightnessctl stub serves and changes only the fake device.
write_shims
write_backlight
bc() { env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$runtime" SHADOW_SHIM_LOG="$logs/shim.log" "$shim_dir/brightnessctl" "$@"; }
[[ $(bc -m -c backlight info) == "../../../${runtime#/}/backlight/fake,backlight,128,50%,255" ]] || fail "info -m: $(bc -m -c backlight info)"
bc -d fake set 80%
[[ $(<"$(fake_backlight_dir)/brightness") == 204 ]] || fail "set 80% wrote $(<"$(fake_backlight_dir)/brightness")"
bc -d fake set 5%+
[[ $(<"$(fake_backlight_dir)/brightness") == 217 ]] || fail "set 5%+ wrote $(<"$(fake_backlight_dir)/brightness")"
bc -d fake -n1 set 100%-
[[ $(<"$(fake_backlight_dir)/brightness") == 1 ]] || fail "-n1 set 100%- wrote $(<"$(fake_backlight_dir)/brightness")"
bc -d fake set 100%
[[ $(bc -d fake get) == 255 ]] || fail "get after set 100%: $(bc -d fake get)"
bc -d some_kbd_backlight set 50%
[[ $(bc -d fake get) == 255 ]] || fail "a set on another device changed the fake"
grep -q 'set 50%' "$logs/shim.log" || fail "the call was not logged"

# The short operations, the bare machine-readable read and relative steps (media.lua and voxcmd system.sh use these).
fake_value() { cat "$(fake_backlight_dir)/brightness"; }
bc -d fake set 50%
bc s 10%+
[[ $(fake_value) == 154 ]] || fail "s 10%+ wrote $(fake_value), wanted 154"
bc s +10%
[[ $(fake_value) == 180 ]] || fail "s +10% wrote $(fake_value), wanted 180"
bc s 10%-
[[ $(fake_value) == 154 ]] || fail "s 10%- wrote $(fake_value), wanted 154"
bc s -10%
[[ $(fake_value) == 128 ]] || fail "s -10% wrote $(fake_value), wanted 128"
bc -n1 set 10%-
[[ $(fake_value) == 102 ]] || fail "-n1 set 10%- wrote $(fake_value), wanted 102"
bc s 40%
[[ $(fake_value) == 102 ]] || fail "s 40% wrote $(fake_value), wanted 102"
[[ $(bc g) == 102 ]] || fail "g: $(bc g)"
[[ $(bc m) == 255 ]] || fail "m: $(bc m)"
[[ $(bc i -m | cut -d, -f4) == 40% ]] || fail "i -m: $(bc i -m)"
[[ $(bc -m | cut -d, -f4) == 40% ]] || fail "bare -m: $(bc -m)"
bc -d fake set 5
bc s +5
[[ $(fake_value) == 10 ]] || fail "s +5 wrote $(fake_value), wanted 10"
bc -d fake set 50%

# Save and restore never run and never reach the real tool, which -r would write to the real backlight.
real_dir=$work/realbin
mkdir -p "$real_dir"
printf '#!/bin/sh\necho "REAL $*" >>"%s/real.calls"\n' "$work" >"$real_dir/brightnessctl"
chmod +x "$real_dir/brightnessctl"
saved_system_path=$system_path
system_path=$real_dir
write_shims
system_path=$saved_system_path
write_backlight
: >"$work/real.calls"
bc -r
bc --restore
bc -s set 10
bc -d fake -s set 10%
bc -d amdgpu_bl1 -r
bc -c leds --save set 1
bc -sd amdgpu_bl1 set 1
bc -d amdgpu_bl1 set 5 -r
bc --rest
bc --sav -d amdgpu_bl1 set 1
bc -d amdgpu_bl1 --restor
[[ ! -s $work/real.calls ]] || fail "a save or restore call reached the real tool: $(<"$work/real.calls")"
[[ $(fake_value) == 128 ]] || fail "a save or restore call changed the fake device: $(fake_value)"
: >"$work/real.calls"

# Reads on other devices reach the real tool with their full arguments (the test points system_path at a recorder).
: >"$work/real.calls"
bc -c leds -m info
bc -d amdgpu_bl1 get
bc -l
bc -d amdgpu_bl1 set 50%
[[ $(<"$work/real.calls") == "REAL -c leds -m info
REAL -d amdgpu_bl1 get
REAL -l" ]] || fail "passthrough reads did not reach the real tool: $(<"$work/real.calls")"
rm -rf "$runtime"

[[ $(git -C "$checkout_root" status --porcelain) == "$before" ]] || fail "the test changed the repo"
((failures == 0)) || exit 1
echo "shadow-audio: ok"
