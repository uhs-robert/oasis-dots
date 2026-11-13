#!/usr/bin/env bash
# Run the full Quickshell bar in an invisible nested Hyprland that agents drive and screenshot,
# isolated from the owner's session: own runtime dir, HOME, session bus and Hyprland instance.
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The main checkout holds the gitignored bar assets, which a linked worktree lacks.
repo=$(dirname "$(git -C "$skill_dir" rev-parse --path-format=absolute --git-common-dir)")
qs_rel=home/quickshell/.config/quickshell
test_bar="$skill_dir/../owner-test-bar/owner-test-bar.sh"
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
root="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow"
# Holds the qs-shadow link; not a shadow name, so status skips it.
bin_dir="$root/bin"
system_path=/usr/local/bin:/usr/bin:/bin
owner_state="${XDG_STATE_HOME:-$HOME/.local/state}"
owner_data="${XDG_DATA_HOME:-$HOME/.local/share}"
owner_config="${XDG_CONFIG_HOME:-$HOME/.config}"
# With --no-audio the shadow has no PipeWire socket, so the bar's PipeWire connect error is expected; otherwise nothing is.
expected_errors_no_audio='quickshell.service.pipewire'
expected_errors_audio='^$'
fail_pattern='ERROR|TypeError|ReferenceError|Binding loop|is not a type|Could not set initial property|File not found|is not installed|Cannot assign'

die() {
  echo "shadow: $*" >&2
  exit 1
}

now_ms() { echo $(($(date +%s%N) / 1000000)); }

# Each held wtype lasts about 66 minutes and is replaced every 50, so two always overlap.
keyboard_hold_ms=4000000
keyboard_renew_s=3000

# Hyprland's event socket <runtime>/hypr/<62-char signature>/.socket2.sock must fit sun_path (107 chars).
# That is 107 - len("/tmp/shadow-<uid>-") - len("/hypr/") - 62 - len("/.socket2.sock").
max_name_len=$((107 - 13 - ${#UID} - 6 - 62 - 14))

set_name() {
  name=${1:-}
  [[ -n $name ]] || die "missing shadow name"
  [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "name '$name' must be lowercase letters, digits and dashes"
  ((${#name} <= max_name_len)) || die "name '$name' is ${#name} chars; at most $max_name_len fit, since Hyprland's socket path under /tmp/shadow-$UID-<name> must stay within 107 chars"
  base="$root/$name"
  runtime="/tmp/shadow-$UID-$name"
  shadow_home="$base/home"
  qs_dir="$base/qs"
  # Per shadow rather than shared, so one shadow's up rewriting its stubs never leaves another running without them.
  shim_dir="$base/shim"
  logs="$base/logs"
  set_env
}

# Every shadow process has the runtime dir in some variable (XDG_RUNTIME_DIR at least), children included.
# Anchored on "=<runtime>" plus "/" or the end, so shadow "demo" never matches "demo2".
carries_runtime() { grep -qzE "^[A-Z_]+=$runtime(/.*)?\$" "$1" 2>/dev/null; }

# The pattern of bar log lines that are expected in this shadow, which depends on whether it has a PipeWire.
expected_errors() { if [[ -f $base/no-audio ]]; then echo "$expected_errors_no_audio"; else echo "$expected_errors_audio"; fi; }

shadow_pids() {
  local env_file pid
  for env_file in /proc/[0-9]*/environ; do
    pid=${env_file#/proc/}
    pid=${pid%/environ}
    [[ $pid == "$$" || $pid == "$BASHPID" ]] && continue
    carries_runtime "$env_file" && echo "$pid"
  done
  return 0
}

# A minimal environment built from nothing: no owner WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE, bus or PipeWire.
# TMUX_TMPDIR gives the bar's tmux picker a private, empty tmux server instead of the owner's sessions.
# An array rather than a function so setsid can exec it.
set_env() {
  shadow_env=(env -i
    HOME="$shadow_home" USER="$USER" LOGNAME="$USER" PATH="$shim_dir:$system_path" LANG="${LANG:-C.UTF-8}" TERM=dumb
    SHADOW_SHIM_LOG="$logs/shim.log" TMUX_TMPDIR="$runtime"
    XDG_RUNTIME_DIR="$runtime" PIPEWIRE_RUNTIME_DIR="$runtime"
    XDG_CONFIG_HOME="$shadow_home/.config" XDG_STATE_HOME="$shadow_home/.local/state"
    XDG_CACHE_HOME="$shadow_home/.cache" XDG_DATA_HOME="$shadow_home/.local/share"
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"
    HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_CRASHREPORTER=1
    LIBSEAT_BACKEND=seatd SEATD_SOCK="$runtime/no-seatd.sock")
}

load_signature() {
  [[ -f $base/signature ]] || die "shadow '$name' is not up (no $base/signature); run: shadow.sh up $name"
  signature=$(<"$base/signature")
}

# Clients only ever see the shadow Hyprland: absolute socket path inside the runtime dir and its own signature.
set_client_env() {
  load_signature
  local wl_socket
  wl_socket="$runtime/$(<"$base/wl-socket")"
  [[ $wl_socket == "$runtime"/wayland-* && -S $wl_socket ]] || die "shadow socket $wl_socket is missing; refusing to send anything"
  client_env=("${shadow_env[@]}" WAYLAND_DISPLAY="$wl_socket" HYPRLAND_INSTANCE_SIGNATURE="$signature" QT_QPA_PLATFORM=wayland)
}

shadow_hyprctl() {
  load_signature
  "${shadow_env[@]}" HYPRLAND_INSTANCE_SIGNATURE="$signature" hyprctl "$@"
}

wait_for() {
  local tries=$1
  shift
  for _ in $(seq "$tries"); do
    "$@" && return 0
    sleep 0.05
  done
  return 1
}

# NVIDIA's node fails nested GBM allocation (bo null), so the first render node of another driver wins.
pick_render_node() {
  if [[ -n ${SHADOW_RENDER_NODE:-} ]]; then
    echo "$SHADOW_RENDER_NODE"
    return
  fi
  local node driver
  for node in /sys/class/drm/renderD*; do
    driver=$(basename "$(readlink -f "$node/device/driver")")
    [[ $driver == nvidia ]] && continue
    echo "/dev/dri/${node##*/}"
    return
  done
  die "no non-NVIDIA render node under /sys/class/drm; set SHADOW_RENDER_NODE=/dev/dri/renderD..."
}

# Copies of only the non-secret files the bar reads (core/Paths.qml dirs), never links into the owner's state.
seed_home() {
  local file
  mkdir -p "$shadow_home"/.config/fontconfig/conf.d "$shadow_home"/.local/state/{quickshell,hypr} \
    "$shadow_home"/.cache/quickshell "$shadow_home"/.local/share/quickshell
  for file in "$owner_state"/quickshell/*.json "$owner_state"/hypr/*.json "$owner_state"/hypr/theme; do
    # weather.local.json holds the owner's real coordinates.
    [[ ${file##*/} == weather.local.json ]] && continue
    [[ -f $file ]] && cp "$file" "$shadow_home/.local/state/${file#"$owner_state"/}"
  done
  # Fixed public coordinates: without them the tracked "auto" default looks the owner's city up by IP (ipwho.is) and shows it.
  printf '{"latitude": 40.7128, "longitude": -74.006, "location_name": "Kokiri Forest"}\n' >"$shadow_home/.local/state/quickshell/weather.local.json"
  # Opt-in: with frames the GoldenEye skin shows the footage, without them its drawn fallback.
  [[ -n ${SHADOW_GOLDENEYE_FRAMES:-} && -d $owner_data/quickshell/goldeneye-frames ]] && cp -rL "$owner_data/quickshell/goldeneye-frames" "$shadow_home/.local/share/quickshell/"
  [[ -f $owner_config/fontconfig/fonts.conf ]] && cp -L "$owner_config/fontconfig/fonts.conf" "$shadow_home/.config/fontconfig/"
  # The owner's user fonts are read in place (38 MB, not state); fontconfig's cache goes to the throwaway HOME.
  if [[ -d $owner_data/fonts ]]; then
    printf '<?xml version="1.0"?>\n<fontconfig><dir>%s</dir></fontconfig>\n' "$owner_data/fonts" \
      >"$shadow_home/.config/fontconfig/conf.d/00-owner-fonts.conf"
  fi
}

# The shadow shares the owner's PID namespace, hardware and system bus, so commands the bar runs that act on the
# whole machine are shadowed by stubs that log the call to logs/shim.log and exit 0. The case pattern after each
# name lists the calls that only read and may reach the real tool; an empty one blocks every call.
# shadow.sh itself never runs inside shadow_env, so its own pkill/kill reach the real tools.
machine_wide_commands=(
  'pkill:' 'killall:' 'kill:\ -0\ *'
  'systemctl:*\ is-active\ *|*\ is-enabled\ *|*\ status\ *|*\ show\ *|*\ list-units\ *'
  'loginctl:' 'shutdown:' 'reboot:' 'poweroff:' 'halt:' 'sudo:' 'pkexec:' 'keyd:'
  'ddcutil:'
  'nmcli:*\ list\ *|*\ show\ *|*\ general\ *|*\ -g\ *' 'bluetoothctl:' 'rfkill:' 'powerprofilesctl:'
  'busctl:*\ introspect\ *|*\ tree\ *|*\ list\ *|*\ get-property\ *|*\ status\ *'
  'udisksctl:' 'checkupdates:' 'claude:' 'nm-connection-editor:' 'blueman-manager:'
)

# The shadow's own pipewire.conf: a null stereo sink as the default audio sink and nothing else that reaches hardware.
# No libspa-alsa, bluez5, v4l2, libcamera or jack in the spa-libs, so the daemon cannot open the owner's sound card
# or camera, and no WirePlumber is started. The `default` metadata object that WirePlumber would write is declared
# here, since the bar's Pipewire service reads the default sink from it. libpipewire-module-access is needed: without
# it every client connect hangs.
write_pipewire_conf() {
  cat >"$base/pipewire.conf" <<'CONF'
context.properties = {
    core.daemon = true
    core.name = pipewire-0
}
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-metadata }
    { name = libpipewire-module-spa-node-factory }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-client-device }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-link-factory }
    { name = libpipewire-module-access args = { } }
    { name = libpipewire-module-session-manager }
]
context.objects = [
    { factory = spa-node-factory
        args = { factory.name = support.node.driver node.name = Dummy-Driver priority.driver = 200000 }
    }
    { factory = adapter
        args = {
            factory.name = support.null-audio-sink
            node.name = shadow_sink
            node.description = "Shadow Speakers"
            media.class = Audio/Sink
            audio.position = [ FL FR ]
            monitor.channel-volumes = true
            object.linger = true
        }
    }
    { factory = metadata
        args = {
            metadata.name = default
            metadata.values = [
                { key = default.audio.sink type = "Spa:String:JSON" value = { name = shadow_sink } }
                { key = default.configured.audio.sink type = "Spa:String:JSON" value = { name = shadow_sink } }
            ]
        }
    }
]
CONF
}

# A fake backlight device under the runtime dir. The brightnessctl stub reports it as `../../../<runtime>/backlight/fake`,
# which Backlight.qml appends to /sys/class/backlight/, so the bar reads these files without any QML change.
fake_backlight_dir() { echo "$runtime/backlight/fake"; }

write_backlight() {
  mkdir -p "$(fake_backlight_dir)"
  echo 255 >"$(fake_backlight_dir)/max_brightness"
  echo 128 >"$(fake_backlight_dir)/brightness"
}

# Replaces the generic brightnessctl stub: info, get and set on the fake device work, other devices only log.
write_brightnessctl_stub() {
  local real
  real=$(PATH=$system_path type -P brightnessctl || true)
  # shellcheck disable=SC2016 # the stub expands these when it runs
  {
    cat <<'STUB'
#!/bin/sh
# Generated by shadow.sh: the fake backlight lives under $XDG_RUNTIME_DIR/backlight/fake; nothing touches /sys.
echo "$(date +%T) brightnessctl $*" >>"${SHADOW_SHIM_LOG:-/dev/null}"
fake="$XDG_RUNTIME_DIR/backlight/fake"
dev= min=0 class= machine=0 cmd= value=
while [ $# -gt 0 ]; do
  case $1 in
  -d | --device) dev=$2; shift ;;
  --device=*) dev=${1#*=} ;;
  -c | --class) class=$2; shift ;;
  -m | --machine-readable) machine=1 ;;
  -n | --min-value) case $2 in [0-9]*) min=$2; shift ;; esac ;;
  -n[0-9]*) min=${1#-n} ;;
  --min-value=*) min=${1#*=} ;;
  info | get | set) cmd=$1; shift; value=${1:-}; break ;;
  esac
  shift
done
is_fake=0
case $dev in fake | */fake) is_fake=1 ;; esac
[ -z "$dev" ] && { [ -z "$class" ] || [ "$class" = backlight ]; } && is_fake=1
if [ "$is_fake" = 1 ] && [ -d "$fake" ]; then
  max=$(cat "$fake/max_brightness")
  cur=$(cat "$fake/brightness")
  case $cmd in
  info)
    pct=$(((cur * 100 + max / 2) / max))
    if [ "$machine" = 1 ]; then echo "../../../${XDG_RUNTIME_DIR#/}/backlight/fake,backlight,$cur,$pct%,$max"; else echo "Device 'fake' of class 'backlight': Current brightness: $cur ($pct%)"; fi
    ;;
  get) echo "$cur" ;;
  set)
    case $value in
    *%+) v=$((cur + (${value%\%+} * max + 50) / 100)) ;;
    *%-) v=$((cur - (${value%\%-} * max + 50) / 100)) ;;
    *%) v=$(((${value%\%} * max + 50) / 100)) ;;
    +*) v=$((cur + ${value#+})) ;;
    -*) v=$((cur - ${value#-})) ;;
    *) v=$value ;;
    esac
    [ "$v" -lt "$min" ] && v=$min
    [ "$v" -gt "$max" ] && v=$max
    echo "$v" >"$fake/brightness"
    ;;
  esac
  exit 0
fi
STUB
    # Anything else (the keyboard backlight, other devices): reads reach the real tool, writes only log.
    [[ -n $real ]] && printf 'case " $* " in *\ info\ *|*\ get\ *|*\ -l\ *|*\ --list\ *) exec %s "$@" ;; esac\n' "$real"
    echo 'exit 0'
  } >"$shim_dir/brightnessctl"
  chmod +x "$shim_dir/brightnessctl"
}

write_shims() {
  local entry cmd reads real
  rm -rf "$shim_dir"
  mkdir -p "$shim_dir"
  for entry in "${machine_wide_commands[@]}"; do
    cmd=${entry%%:*}
    reads=${entry#*:}
    real=$(PATH=$system_path type -P "$cmd" || true)
    # shellcheck disable=SC2016 # the stub expands $* and $SHADOW_SHIM_LOG when it runs
    {
      printf '#!/bin/sh\n# Generated by shadow.sh: %s acts on the whole machine, so the shadow logs it instead.\n' "$cmd"
      printf 'echo "$(date +%%T) %s $*" >>"${SHADOW_SHIM_LOG:-/dev/null}"\n' "$cmd"
      [[ -n $reads && -n $real ]] && printf 'case " $* " in %s) exec %s "$@" ;; esac\n' "$reads" "$real"
      echo 'exit 0'
    } >"$shim_dir/$cmd"
    chmod +x "$shim_dir/$cmd"
  done
  write_brightnessctl_stub
}

# The shadow has no voxtype daemon, so `voxtype status --follow` is replaced by a stream of the states written to
# $XDG_RUNTIME_DIR/voxtype-state (idle, recording, transcribing). That is the only way to raise the OSD without PipeWire.
write_voxtype_stub() {
  cat >"$shim_dir/voxtype" <<'STUB'
#!/bin/sh
# Generated by shadow.sh: follows the last line of $XDG_RUNTIME_DIR/voxtype-state as voxtype status JSON.
echo "$(date +%T) voxtype $*" >>"${SHADOW_SHIM_LOG:-/dev/null}"
[ "$1" = status ] || exit 0
state_file="$XDG_RUNTIME_DIR/voxtype-state"
: >>"$state_file"
tail -n 1 -F "$state_file" | while read -r state; do
  printf '{"alt":"%s","class":"%s","tooltip":""}\n' "$state" "$state"
done
STUB
  chmod +x "$shim_dir/voxtype"
}

write_hypr_config() {
  local size=$1 desktop=$2 src=$3
  mkdir -p "$base/hypr"
  cat >"$base/hypr/hyprland.lua" <<EOF
-- Generated by shadow.sh. The output starts disabled and is enabled by a reload once the host's first
-- configure is acked; aquamarine otherwise commits a buffer before acking, which wlroots rejects.
local enabled = io.open("$runtime/output-enabled") ~= nil
hl.monitor({ output = "WAYLAND-1", disabled = not enabled, mode = "${size}@60", position = "0x0", scale = "1" })
hl.config({
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
  xwayland = { enabled = false },
})
EOF
  ((desktop)) || return 0
  # The Lua globals Quickshell dispatches to, from the bar's own checkout; a checkout without the file loads none.
  local frame_lua="${src%/"$qs_rel"}/home/hypr/.config/hypr/config/general/frame.lua"
  [[ -f $frame_lua ]] && cp "$frame_lua" "$base/hypr/frame.lua"
  cat >>"$base/hypr/hyprland.lua" <<EOF
-- --desktop: the tracked config/general gaps, border and rounding, so tiled clients sit where they would on a desktop.
hl.config({ general = { gaps_in = 4, gaps_out = 6, border_size = 2 }, decoration = { rounding = 0 } })
local frame_lua = io.open("$base/hypr/frame.lua")
if frame_lua then
  frame_lua:close()
  dofile("$base/hypr/frame.lua")
end
EOF
}

# labwc advertises xdg_wm_base v6 headless, which aquamarine needs; cage, sway and weston cap it at v5.
# Prints the host's socket name.
start_host() {
  local render_node=$1
  command -v labwc >/dev/null || die "the shadow host is labwc, which is not installed (pacman -S labwc)"
  mkdir -p "$base/labwc"
  echo '<labwc_config/>' >"$base/labwc/rc.xml"
  # Headless counts as not nested to labwc, which would then push this env into the owner's systemd/D-Bus activation env.
  setsid "${shadow_env[@]}" WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 \
    LABWC_UPDATE_ACTIVATION_ENV=0 WLR_RENDER_DRM_DEVICE="$render_node" labwc -C "$base/labwc" \
    >"$logs/host.out" 2>"$logs/host.log" </dev/null &
  echo "$!" >"$base/host.sid"
  wait_for 200 compgen -G "$runtime/wayland-*[0-9]" >/dev/null || die "labwc made no socket; see $logs/host.log"
  basename "$(compgen -G "$runtime/wayland-*[0-9]" | head -1)"
}

# Headless labwc has no keyboard, so its seat never sends aquamarine an event and the nested Hyprland stalls
# before it even lists its output. A virtual keyboard (shift down and up) from wtype against the host socket,
# which is inside the runtime dir, gives it one.
host_output_listed() {
  output_listed all && return 0
  "${shadow_env[@]}" WAYLAND_DISPLAY="$runtime/$host_socket" wtype -M shift -m shift 2>/dev/null || true
  sleep 0.2
  return 1
}

held_keyboard_listed() { shadow_hyprctl devices -j 2>/dev/null | jq -e '.keyboards | length > 0' >/dev/null; }
hypr_socket_ready() { compgen -G "$runtime/hypr/*/.socket.sock" >/dev/null; }
output_listed() { shadow_hyprctl monitors "$@" -j 2>/dev/null | grep -q '"WAYLAND-1"'; }

# owner-test-bar.sh build only makes a worktree, merges and runs just check; it never stops or swaps the live bar.
# With no branches the bar comes from the caller's worktree (or --from DIR) as it is on disk, uncommitted edits
# included; outside any checkout of this repo it falls back to the main checkout.
worktree_source() {
  local dir=${from:-.} top common repo_common
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=
  [[ -z $top && -n $from ]] && die "--from $from is not inside a git checkout"
  repo_common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
  [[ -n $top ]] && common=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)
  if [[ -z $top || $common != "$repo_common" ]]; then
    # An unrelated repository around the cwd is no reason to fail when the caller named no checkout.
    [[ -z $from ]] || die "$top is a checkout of another repository, not this one"
    top=$repo
  fi
  [[ -d $top/$qs_rel ]] || die "$top has no $qs_rel"
  echo "$top/$qs_rel"
}

# Gitignored assets (theme.json, FF7 audio) exist only in the main checkout; fill in what the source lacks.
overlay_ignored_assets() {
  [[ ${1%/"$qs_rel"} == "$repo" ]] || "$test_bar" copy-assets "$qs_dir"
}

resolve_source() {
  (($# == 0)) && {
    worktree_source
    return
  }
  # Prefixed so a shadow's bar can never share a name with one the owner is testing.
  local bar="shadow-$name"
  if [[ -e $bars/$bar ]]; then
    pgrep -af "^qs .*-p $bars/$bar/" >/dev/null && die "test bar '$bar' is the owner's live bar; pick another shadow name"
    die "test bar '$bar' exists from an earlier shadow; remove it with: $test_bar remove $bar"
  fi
  "$test_bar" build "$bar" "$@" >&2 || die "owner-test-bar.sh build $bar $* failed"
  echo "$bar" >"$base/test-bar"
  printf '%s\n' "$@" >"$base/branches"
  echo "$bars/$bar/$qs_rel"
}

# Without this, a failed readiness check would leave the bus, host or Hyprland running, and the next up
# would refuse because the shadow still looks active.
abort_up() {
  local status=$? log
  trap - EXIT
  echo "shadow: '$name' failed to start; stopping what was launched (logs kept in $logs)" >&2
  for log in qs hypr host dbus; do
    [[ -s $logs/$log.log ]] || continue
    echo "== $log.log (last 10 lines)" >&2
    tail -n 10 "$logs/$log.log" | cut -c1-300 >&2
  done
  teardown
  exit "$status"
}

up() {
  set_name "${1:-}"
  shift
  local size=1920x1080 desktop=0 from='' audio=1
  local branches=()
  while (($# > 0)); do
    case $1 in
    --size)
      size=${2:?--size needs WxH}
      shift 2
      ;;
    --desktop)
      desktop=1
      shift
      ;;
    --no-audio)
      audio=0
      shift
      ;;
    --from)
      from=${2:?--from needs a worktree directory}
      shift 2
      ;;
    -*) die "unknown argument: $1" ;;
    *)
      branches+=("$1")
      shift
      ;;
    esac
  done
  [[ -z $from || ${#branches[@]} -eq 0 ]] || die "--from and branches are exclusive"
  [[ $size =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] || die "--size must be WxH, like 1080x1920"
  [[ -z $(shadow_pids) ]] || die "shadow '$name' is already running; run: shadow.sh down $name"
  local t0 src render_node host_socket
  t0=$(now_ms)
  rm -rf "$base"
  mkdir -p "$logs" "$bin_dir"
  trap abort_up EXIT
  echo "$size" >"$base/size"
  src=$(resolve_source "${branches[@]}")
  local t_src=$(($(now_ms) - t0))
  # A plain copy with links resolved, so later edits or removal of a worktree cannot change the running bar.
  cp -rL "$src" "$qs_dir"
  overlay_ignored_assets "$src"
  echo "${src%/"$qs_rel"}" >"$base/source"
  seed_home
  ln -sfn "$(command -v qs)" "$bin_dir/qs-shadow"
  write_shims
  write_voxtype_stub
  write_hypr_config "$size" "$desktop" "$src"
  render_node=$(pick_render_node)

  rm -rf "$runtime"
  mkdir -m 0700 "$runtime"
  setsid "${shadow_env[@]}" dbus-daemon --session --nofork --address="unix:path=$runtime/bus" >"$logs/dbus.log" 2>&1 </dev/null &
  echo "$!" >"$base/bus.sid"
  wait_for 100 test -S "$runtime/bus" || die "session bus did not start; see $logs/dbus.log"
  write_backlight
  setup_audio "$audio"

  host_socket=$(start_host "$render_node")
  local t_host=$(($(now_ms) - t0))

  setsid "${shadow_env[@]}" WAYLAND_DISPLAY="$runtime/$host_socket" Hyprland --config "$base/hypr/hyprland.lua" \
    >"$logs/hypr.log" 2>&1 </dev/null &
  echo "$!" >"$base/hypr.sid"
  wait_for 300 hypr_socket_ready || die "nested Hyprland made no socket; see $logs/hypr.log"
  basename "$(dirname "$(compgen -G "$runtime/hypr/*/.socket.sock" | head -1)")" >"$base/signature"
  wait_for 40 host_output_listed || die "nested Hyprland never listed WAYLAND-1; see $logs/hypr.log"
  sleep 0.3
  touch "$runtime/output-enabled"
  shadow_hyprctl reload >/dev/null
  wait_for 200 output_listed || die "WAYLAND-1 did not enable after reload; see $logs/hypr.log"
  shadow_hyprctl instances -j | jq -r --arg s "$(<"$base/signature")" '.[] | select(.instance == $s) | .wl_socket' >"$base/wl-socket"
  local t_hypr=$(($(now_ms) - t0))

  # Hyprland drops keyboard focus from an OnDemand layer (a picker) when the last keyboard leaves and does not give it
  # back when one returns. `keys` plugs a wtype keyboard in and out per call, so without this one lone keypress is lost.
  # wtype 0.4 overflows 32-bit microseconds above about 4294967 ms, so no single wtype can outlast a long run. The loop
  # starts the next one before the last ends: both keyboards overlap, so there is never a gap. A wtype ends with one
  # tap of Shift_L (press and release), harmless while idle.
  set_client_env
  # shellcheck disable=SC2016 # expanded by the child shell
  setsid "${client_env[@]}" sh -c 'while :; do wtype -s "$0" -k Shift_L & sleep "$1"; done' \
    "$keyboard_hold_ms" "$keyboard_renew_s" >"$logs/keyboard.log" 2>&1 </dev/null &
  echo "$!" >"$base/keyboard.sid"
  wait_for 100 held_keyboard_listed || die "the held keyboard never appeared; see $logs/keyboard.log"

  # Launched as qs-shadow, so pgrep -x qs, pkill -x qs and pgrep -af '^qs ' (owner-test-bar, git hooks) never match it.
  setsid "${client_env[@]}" "$bin_dir/qs-shadow" -p "$qs_dir" >"$logs/qs.log" 2>&1 </dev/null &
  echo "$!" >"$base/qs.sid"
  wait_for 400 grep -q 'Configuration Loaded' "$logs/qs.log" || die "the bar did not load; see $logs/qs.log"
  local t_qs=$(($(now_ms) - t0))
  trap - EXIT
  sleep 1
  local errors
  errors=$(sed 's/\x1b\[[0-9;]*m//g' "$logs/qs.log" | grep -E "$fail_pattern" | grep -vE "$(expected_errors)" || true)
  echo "shadow: '$name' up from ${src#"$HOME"/} (source ${t_src} ms, host ${t_host} ms, hyprland ${t_hypr} ms, bar ${t_qs} ms)"
  [[ -z $errors ]] || {
    echo "$errors" >&2
    echo "shadow: the bar logged errors (above); full log $logs/qs.log" >&2
  }
}

pw_socket_ready() { [[ -S $runtime/pipewire-0 ]]; }

# pw-cli and pw-dump against the shadow's own PipeWire, which `up` starts. The explicit PIPEWIRE_RUNTIME_DIR (shadow_env
# has it too) and the socket check mean no call can reach the owner's PipeWire, whose socket is under /run/user.
require_pw_socket() {
  [[ -S $runtime/pipewire-0 && $runtime == /tmp/shadow-* ]] || die "shadow '$name' has no PipeWire socket at $runtime/pipewire-0 (started with --no-audio, or not up); refusing"
}

pw_run() { timeout 5 "${shadow_env[@]}" PIPEWIRE_RUNTIME_DIR="$runtime" "$@"; }

sink_listed() { pw_run pw-dump 2>/dev/null | jq -e '.[] | select(.info.props["node.name"] == "shadow_sink")' >/dev/null; }

sink_id() { pw_run pw-dump | jq -r '[.[] | select(.info.props["node.name"] == "shadow_sink") | .id] | first // empty'; }

# Starts the shadow's private PipeWire from shadow_env, with only the generated conf. A shadow without audio is marked,
# which turns the bar's PipeWire connect error back into an expected one.
setup_audio() {
  if (($1)); then
    write_pipewire_conf
    setsid "${shadow_env[@]}" pipewire -c "$base/pipewire.conf" >"$logs/pipewire.log" 2>&1 </dev/null &
    echo "$!" >"$base/pipewire.sid"
    wait_for 100 pw_socket_ready || die "PipeWire made no socket; see $logs/pipewire.log"
    wait_for 100 sink_listed || die "the shadow sink never appeared in PipeWire; see $logs/pipewire.log"
  else
    touch "$base/no-audio"
  fi
}

# Sets the shadow sink's volume or mutes it. The bar shows the cube root of the channel volume (WirePlumber's scale), so
# 40 is stored as 0.4^3 and reads as 40% in the OSD.
volume() {
  set_name "${1:-}"
  local what=${2:-} id vol
  [[ $what =~ ^([0-9]|[1-9][0-9]|100|mute|unmute)$ ]] || die "usage: shadow.sh volume <name> {0-100|mute|unmute}"
  require_pw_socket
  id=$(sink_id)
  [[ -n $id ]] || die "the shadow sink is not in the shadow's PipeWire graph"
  case $what in
  mute) pw_run pw-cli s "$id" Props '{ mute: true }' >/dev/null ;;
  unmute) pw_run pw-cli s "$id" Props '{ mute: false }' >/dev/null ;;
  *)
    vol=$(awk -v p="$what" 'BEGIN { printf "%.6f", (p / 100) ^ 3 }')
    pw_run pw-cli s "$id" Props "{ mute: false, channelVolumes: [ $vol, $vol ] }" >/dev/null
    ;;
  esac
}

# Sets the fake backlight (1-100 %) and asks the bar to re-read it, which raises the brightness OSD.
brightness() {
  set_name "${1:-}"
  local pct=${2:-} dir
  [[ $pct =~ ^([1-9][0-9]?|100)$ ]] || die "usage: shadow.sh brightness <name> <1-100>"
  dir=$(fake_backlight_dir)
  [[ $runtime == /tmp/shadow-* && -f $dir/max_brightness ]] || die "shadow '$name' has no fake backlight at $dir; refusing"
  echo $((pct * $(<"$dir/max_brightness") / 100)) >"$dir/brightness"
  ipc "$name" brightness refresh >/dev/null
}

# Drives the bar by action id, with the parameter checks hypr-act applies. The shadow's Hyprland loads no keymaps, so
# the id is resolved headlessly (act_refs.lua --resolve) and an ipc-kind action is sent through ipc(). A command or lua
# action would act on the owner's machine or need a live Hyprland, so it is refused.
action() {
  set_name "${1:-}" || return 2
  shift
  if (($# == 0)); then
    echo "usage: shadow.sh action <name> <action id> [params...]" >&2
    return 2
  fi
  # Ids come from the checkout the shadow's bar was started from when that is known (--from), else from this script's.
  local checkout plan status kind
  checkout=$(<"$base/source" 2>/dev/null) || checkout=
  [[ -f $checkout/home/hypr/tests/act_refs.lua ]] || checkout=$(CDPATH='' cd -- "$skill_dir/../../.." && pwd)
  plan=$(lua "$checkout/home/hypr/tests/act_refs.lua" --resolve "$@")
  status=$?
  ((status == 0)) || return "$status"
  kind=$(jq -r '.kind // empty' <<<"$plan")
  case $kind in
  ipc)
    # NUL-delimited so a param holding a newline stays one word.
    local -a call
    mapfile -d '' call < <(jq --raw-output0 '.target, .function, .args[]' <<<"$plan")
    ipc "$name" "${call[@]}"
    ;;
  command)
    echo "shadow: action '$1' runs a command ($(jq -r '.argv | join(" ")' <<<"$plan")) that would act on this machine, not the shadow; use spawn or hyprctl instead" >&2
    return 5
    ;;
  lua)
    echo "shadow: action '$1' needs a live Hyprland with the repo keymaps; the shadow loads none" >&2
    return 5
    ;;
  *)
    echo "shadow: action '$1': the resolver returned no known kind: $plan" >&2
    return 5
    ;;
  esac
}

ipc() {
  set_name "${1:-}"
  shift
  (($# > 0)) || die "usage: shadow.sh ipc <name> {show|<target> <function> [args...]}"
  set_client_env
  if [[ $1 == show ]]; then
    "${client_env[@]}" "$bin_dir/qs-shadow" -p "$qs_dir" ipc show
    return
  fi
  local reply
  reply=$("${client_env[@]}" "$bin_dir/qs-shadow" -p "$qs_dir" ipc call "$@" 2>&1)
  [[ -z $reply ]] || echo "$reply"
  # qs exits 0 even when the target or function does not exist.
  if grep -qE '^(Target|Function) not found|^No running instances' <<<"$reply"; then
    die "ipc call $* failed; list targets with: shadow.sh ipc $name show"
  fi
}

keys() {
  set_name "${1:-}"
  shift
  (($# > 0)) || die "usage: shadow.sh keys <name> <wtype args...>"
  # set_client_env refuses unless the socket is inside this shadow's runtime dir; the child checks its own env again.
  set_client_env
  # shellcheck disable=SC2016 # expanded by the child shell
  "${client_env[@]}" sh -c 'case $WAYLAND_DISPLAY in "$0"/*) exec wtype "$@" ;; *) echo "shadow: WAYLAND_DISPLAY outside $0" >&2; exit 1 ;; esac' "$runtime" "$@"
}

# Exit 0 when under 1% of the image's pixels differ from its most common colour.
is_uniform() {
  python3 - "$1" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
colors = im.getcolors(im.size[0] * im.size[1])
top = max(colors)[0]
sys.exit(0 if im.size[0] * im.size[1] - top < 0.01 * im.size[0] * im.size[1] else 1)
PY
}

shot() {
  set_name "${1:-}"
  shift
  local ns="" pad=0 out=""
  while (($# > 0)); do
    case $1 in
    --pad)
      pad=${2:?--pad needs a number}
      shift 2
      ;;
    --out)
      out=${2:?--out needs a path}
      shift 2
      ;;
    -*) die "unknown argument: $1" ;;
    *)
      ns=$1
      shift
      ;;
    esac
  done
  [[ $pad =~ ^[0-9]+$ ]] || die "--pad must be a non-negative integer"
  set_client_env
  mkdir -p "$base/shots"
  out=${out:-$base/shots/${ns:-output}-$(date +%H%M%S).png}
  if [[ -z $ns ]]; then
    "${client_env[@]}" grim "$out"
  else
    local geom x y w h
    geom=$(shadow_hyprctl layers -j | jq -r --arg ns "$ns" '[.[].levels[][] | select(.namespace == $ns)][0] // empty | "\(.x) \(.y) \(.w) \(.h)"')
    [[ -n $geom ]] || die "no layer '$ns' in shadow '$name'; layers: $(shadow_hyprctl layers -j | jq -r '[.[].levels[][].namespace] | unique | join(" ")')"
    read -r x y w h <<<"$geom"
    local x0=$((x - pad < 0 ? 0 : x - pad)) y0=$((y - pad < 0 ? 0 : y - pad))
    "${client_env[@]}" grim -g "$x0,$y0 $((w + x - x0 + pad))x$((h + y - y0 + pad))" "$out"
  fi
  echo "$out"
  # A drawn surface always has text or edges, so a near-uniform layer capture means nothing was drawn yet.
  if [[ -n $ns ]] && is_uniform "$out"; then
    die "'$ns' captured blank (still animating in, or its content failed to load; check logs/qs.log). For popups and the OSD, run shadow.sh wait first"
  fi
}

# Polls a surface's state IPC until it reports itself fully drawn (or closed), so a shot or key press never lands mid-animation.
wait_surface() {
  set_name "${1:-}"
  shift
  local usage="usage: shadow.sh wait <name> {popup <popup>|osd <volume|brightness|voxtype>|popup closed|osd closed|clickhints open|clickhints closed} [--timeout SECONDS]"
  local target=${1:-} want=${2:-} timeout=5 state deadline
  [[ $target =~ ^(popup|osd|clickhints)$ && -n $want ]] || die "$usage"
  shift 2
  [[ ${1:-} != --timeout ]] || timeout=${2:?--timeout needs seconds}
  [[ $timeout =~ ^[0-9]+$ ]] || die "--timeout must be whole seconds"
  [[ $want == closed || $target == clickhints ]] || want="open $want"
  deadline=$(($(now_ms) + timeout * 1000))
  while :; do
    state=$(ipc "$name" "$target" state 2>&1) || die "$target state failed ($state); the bar may predate the $target state IPC"
    [[ $state == "$want" ]] && return 0
    (($(now_ms) < deadline)) || die "$target is '$state' after ${timeout}s, not '$want'"
    sleep 0.05
  done
}

set_voxtype() {
  set_name "${1:-}"
  local state=${2:-}
  [[ $state =~ ^(idle|recording|transcribing)$ ]] || die "usage: shadow.sh voxtype <name> {idle|recording|transcribing}"
  load_signature
  echo "$state" >>"$runtime/voxtype-state"
}

player_listed() { "${shadow_env[@]}" playerctl -l 2>/dev/null | grep -qx shadowfake; }

# A fake MPRIS player on the shadow's private bus, so the media popup has a track. It starts from shadow_env, never
# client_env (it needs no Wayland), and only once the shadow's own bus socket exists. A second start replaces the first
# (one player, one bus name), and stop on a dead player is a no-op.
player() {
  set_name "${1:-}"
  local action=${2:-}
  [[ $action =~ ^(start|stop)$ ]] || die "usage: shadow.sh player <name> {start|stop} [--title T] [--artist A]"
  shift 2
  if [[ $action == stop ]]; then
    kill_session player
    return 0
  fi
  local -a track=()
  while (($# > 0)); do
    case $1 in
    --title | --artist) track+=("$1" "${2?$1 needs a value}") ;;
    *) die "unknown player option '$1'" ;;
    esac
    shift 2
  done
  [[ -S $runtime/bus ]] || die "shadow '$name' has no bus at $runtime/bus; run: shadow.sh up $name"
  kill_session player
  setsid "${shadow_env[@]}" python3 "$skill_dir/fake_player.py" "${track[@]}" >>"$logs/player.log" 2>&1 </dev/null &
  echo "$!" >"$base/player.sid"
  wait_for 100 player_listed || die "the fake player did not appear on the shadow's bus within 5 s; see $logs/player.log"
}

client_count_above() { (($(shadow_hyprctl clients -j | jq length) > $1)); }

# A client inside the shadow (default foot), so the bar's reserved zones can be judged against tiled windows. Each
# runs in its own session, which down stops with the rest.
spawn() {
  set_name "${1:-}"
  shift
  (($# > 0)) || set -- foot
  set_client_env
  local before
  before=$(shadow_hyprctl clients -j | jq length)
  setsid "${client_env[@]}" "$@" >>"$logs/spawn.log" 2>&1 </dev/null &
  echo "$!" >"$base/spawn-$!.sid"
  wait_for 100 client_count_above "$before" || die "'$*' mapped no window within 5 s; see $logs/spawn.log"
}

# PSS, so libraries and GPU mappings shared with the owner's session are not counted twice.
pss_mb() {
  local pid kb=0 pss
  for pid in "$@"; do
    pss=$(awk '/^Pss:/ { print $2 }' "/proc/$pid/smaps_rollup" 2>/dev/null || true)
    kb=$((kb + ${pss:-0}))
  done
  echo $((kb / 1024))
}

status_one() {
  set_name "$1"
  local pids
  mapfile -t pids < <(shadow_pids)
  if ((${#pids[@]} == 0)); then
    echo "$name: down"
    return
  fi
  local source
  source="worktree $(cat "$base/source" 2>/dev/null || echo unknown)"
  [[ -f $base/branches ]] && source="test bar $(<"$base/test-bar") ($(paste -sd ' ' "$base/branches"))"
  echo "$name: up, ${#pids[@]} processes, $(pss_mb "${pids[@]}") MB PSS, size $(cat "$base/size" 2>/dev/null || echo unknown), source $source"
  echo "  runtime $runtime, signature $(cat "$base/signature" 2>/dev/null || echo none)"
  local component sid
  for component in qs keyboard hypr host bus player pipewire; do
    sid=$(cat "$base/$component.sid" 2>/dev/null || true)
    if [[ -n $sid ]] && pgrep -s "$sid" >/dev/null; then echo "  $component: running (session $sid)"; else echo "  $component: not running"; fi
  done
  local errors
  errors=$(sed 's/\x1b\[[0-9;]*m//g' "$logs/qs.log" 2>/dev/null | grep -E "$fail_pattern" | grep -cvE "$(expected_errors)" || true)
  echo "  bar log: $logs/qs.log ($errors error lines)"
}

status() {
  if (($# > 0)); then
    status_one "$1"
    return
  fi
  local dir found=0
  for dir in "$root"/*/; do
    [[ -d $dir && ${dir%/} != "$bin_dir" ]] || continue
    found=1
    status_one "$(basename "$dir")"
  done
  ((found)) || echo "shadow: none"
}

# Only sessions whose leader still carries this shadow's runtime dir, so a recycled session id is never hit.
kill_session() {
  local sid_file="$base/$1.sid" sid
  [[ -f $sid_file ]] || return 0
  sid=$(<"$sid_file")
  if carries_runtime "/proc/$sid/environ"; then
    pkill -TERM -s "$sid" || true
    for _ in $(seq 40); do
      pgrep -s "$sid" >/dev/null || break
      sleep 0.05
    done
    pkill -KILL -s "$sid" || true
  fi
  rm -f "$sid_file"
}

# Stops whatever of the shadow is running and removes its runtime dir and test bar; logs and shots stay (a failed
# `up` keeps them for debugging, `down` removes them unless asked to keep them).
teardown() {
  local component pid left sid_file
  for sid_file in "$base"/spawn-*.sid; do
    [[ -e $sid_file ]] || continue
    component=${sid_file##*/}
    kill_session "${component%.sid}"
  done
  for component in player qs pipewire keyboard hypr host bus; do kill_session "$component"; done
  if mountpoint -q "$runtime/gvfs" 2>/dev/null; then fusermount -u "$runtime/gvfs" || fusermount -uz "$runtime/gvfs"; fi
  # Strays outside the recorded sessions (a service the bus activated, a daemonized child) get one sweep.
  for pid in $(shadow_pids); do
    echo "shadow: sweeping stray $pid $(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)" >&2
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 0.5
  left=$(shadow_pids)
  if [[ -n $left ]]; then
    for pid in $left; do echo "  $pid $(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)" >&2; done
    die "processes still carry $runtime in their environment (above)"
  fi
  rm -rf "$runtime"
  rm -f "$base/signature" "$base/wl-socket"
  if [[ -f $base/test-bar ]]; then
    "$test_bar" remove "$(<"$base/test-bar")"
    rm -f "$base/test-bar"
  fi
}

down() {
  set_name "${1:-}"
  local keep=${2:-}
  [[ -z $keep || $keep == --keep ]] || die "usage: shadow.sh down <name> [--keep]"
  teardown
  # The throwaway HOME, the config copy and the shims are rebuilt on every `up`, so only logs and shots would be
  # lost; without --keep the whole folder goes so stopped shadows don't pile up (about 21 MB each).
  if [[ -z $keep && -n $name && $base == "$root/$name" ]]; then
    rm -rf "$base"
    echo "shadow: '$name' down and removed, no process references $runtime"
  else
    echo "shadow: '$name' down, no process references $runtime; logs and shots kept in $base"
  fi
}

usage="usage: shadow.sh {up <name> [--size WxH] [--desktop] [--no-audio] [--from DIR|<branch>...]|spawn <name> [<command>...]|ipc <name> <ipc call args>|action <name> <action id> [params...]|player <name> {start|stop} [--title T] [--artist A]|volume <name> {0-100|mute|unmute}|brightness <name> <1-100>|keys <name> <wtype args>|voxtype <name> {idle|recording|transcribing}|hyprctl <name> <args>|wait <name> {popup|osd|clickhints} {<what>|open|closed} [--timeout SECONDS]|shot <name> [<layer namespace>] [--pad N] [--out PATH]|status [<name>]|down <name> [--keep]}"
cmd=${1:-}
(($# > 0)) && shift
# Sourced by the tests, it only defines the functions.
[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
case $cmd in
up) up "$@" ;;
ipc) ipc "$@" ;;
action) action "$@" ;;
keys) keys "$@" ;;
voxtype) set_voxtype "$@" ;;
player) player "$@" ;;
volume) volume "$@" ;;
brightness) brightness "$@" ;;
spawn) spawn "$@" ;;
hyprctl)
  set_name "${1:-}"
  shift
  shadow_hyprctl "$@"
  ;;
wait) wait_surface "$@" ;;
shot) shot "$@" ;;
status) status "$@" ;;
down) down "$@" ;;
*) die "$usage" ;;
esac
