#!/usr/bin/env bash
# Run the full Quickshell bar in an invisible nested Hyprland that agents drive and screenshot,
# isolated from the owner's session: own runtime dir, HOME, session bus and Hyprland instance.
set -euo pipefail

skill_dir=$(cd "$(dirname "$0")" && pwd)
# The main checkout even when run from a linked worktree, since only it holds the gitignored bar assets.
repo=$(dirname "$(git -C "$skill_dir" rev-parse --path-format=absolute --git-common-dir)")
qs_rel=home/quickshell/.config/quickshell
test_bar="$skill_dir/../test-bar/test-bar.sh"
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
root="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow"
# Holds the qs-shadow link; not a shadow name, so status skips it.
bin_dir="$root/bin"
system_path=/usr/local/bin:/usr/bin:/bin
owner_state="${XDG_STATE_HOME:-$HOME/.local/state}"
owner_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
owner_data="${XDG_DATA_HOME:-$HOME/.local/share}"
owner_config="${XDG_CONFIG_HOME:-$HOME/.config}"
# The shadow has no PipeWire socket by design, so the bar's PipeWire connect error is expected.
expected_errors='quickshell.service.pipewire'
fail_pattern='ERROR|TypeError|ReferenceError|Binding loop|is not a type|Could not set initial property|File not found|is not installed|Cannot assign'

die() {
  echo "shadow: $*" >&2
  exit 1
}

now_ms() { echo $(($(date +%s%N) / 1000000)); }

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
# TMUX_TMPDIR gives the bar's tmux overview a private, empty tmux server instead of the owner's sessions.
# An array rather than a function so setsid can exec it.
set_env() {
  shadow_env=(env -i
    HOME="$shadow_home" USER="$USER" LOGNAME="$USER" PATH="$shim_dir:$system_path" LANG="${LANG:-C.UTF-8}" TERM=dumb
    SHADOW_SHIM_LOG="$logs/shim.log" TMUX_TMPDIR="$runtime"
    XDG_RUNTIME_DIR="$runtime"
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

# Copies of only the non-secret files the bar reads (theme/Paths.qml dirs), never links into the owner's state.
seed_home() {
  local file
  mkdir -p "$shadow_home"/.config/fontconfig/conf.d "$shadow_home"/.local/state/{quickshell,hypr} \
    "$shadow_home"/.cache/quickshell "$shadow_home"/.local/share/quickshell
  for file in "$owner_state"/quickshell/*.json "$owner_state"/hypr/*.json "$owner_state"/hypr/theme; do
    [[ -f $file ]] && cp "$file" "$shadow_home/.local/state/${file#"$owner_state"/}"
  done
  [[ -f $owner_cache/quickshell/weather.json ]] && cp "$owner_cache/quickshell/weather.json" "$shadow_home/.cache/quickshell/"
  [[ -d $owner_data/quickshell/goldeneye-frames ]] && cp -r "$owner_data/quickshell/goldeneye-frames" "$shadow_home/.local/share/quickshell/"
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
  'brightnessctl:*\ info\ *|*\ get\ *|*\ -l\ *|*\ --list\ *' 'ddcutil:'
  'nmcli:*\ list\ *|*\ show\ *|*\ general\ *|*\ -g\ *' 'bluetoothctl:' 'rfkill:' 'powerprofilesctl:'
  'busctl:*\ introspect\ *|*\ tree\ *|*\ list\ *|*\ get-property\ *|*\ status\ *'
  'udisksctl:' 'checkupdates:' 'claude:' 'nm-connection-editor:' 'blueman-manager:'
)

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
}

write_hypr_config() {
  mkdir -p "$base/hypr"
  cat >"$base/hypr/hyprland.lua" <<EOF
-- Generated by shadow.sh. The output starts disabled and is enabled by a reload once the host's first
-- configure is acked; aquamarine otherwise commits a buffer before acking, which wlroots rejects.
local enabled = io.open("$runtime/output-enabled") ~= nil
hl.monitor({ output = "WAYLAND-1", disabled = not enabled, mode = "1920x1080@60", position = "0x0", scale = "1" })
hl.config({
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
  xwayland = { enabled = false },
})
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

hypr_socket_ready() { compgen -G "$runtime/hypr/*/.socket.sock" >/dev/null; }
output_listed() { shadow_hyprctl monitors "$@" -j 2>/dev/null | grep -q '"WAYLAND-1"'; }

# test-bar.sh build only makes a worktree, merges and runs just check; it never stops or swaps the live bar.
resolve_source() {
  (($# == 0)) && {
    echo "$repo/$qs_rel"
    return
  }
  local bar="${name}s"
  [[ -e $bars/$bar ]] && die "test bar '$bar' exists from an earlier shadow; remove it with: $test_bar remove $bar"
  "$test_bar" build "$bar" "$@" >&2 || die "test-bar.sh build $bar $* failed"
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
  [[ -z $(shadow_pids) ]] || die "shadow '$name' is already running; run: shadow.sh down $name"
  local t0 src render_node host_socket
  t0=$(now_ms)
  rm -rf "$base"
  mkdir -p "$logs" "$bin_dir"
  trap abort_up EXIT
  src=$(resolve_source "$@")
  local t_src=$(($(now_ms) - t0))
  # A plain copy with links resolved, so later edits or removal of a worktree cannot change the running bar.
  cp -rL "$src" "$qs_dir"
  seed_home
  ln -sfn "$(command -v qs)" "$bin_dir/qs-shadow"
  write_shims
  write_hypr_config
  render_node=$(pick_render_node)

  rm -rf "$runtime"
  mkdir -m 0700 "$runtime"
  setsid "${shadow_env[@]}" dbus-daemon --session --nofork --address="unix:path=$runtime/bus" >"$logs/dbus.log" 2>&1 </dev/null &
  echo "$!" >"$base/bus.sid"
  wait_for 100 test -S "$runtime/bus" || die "session bus did not start; see $logs/dbus.log"

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

  # Launched as qs-shadow, so pgrep -x qs, pkill -x qs and pgrep -af '^qs ' (test-bar, git hooks) never match it.
  set_client_env
  setsid "${client_env[@]}" "$bin_dir/qs-shadow" -p "$qs_dir" >"$logs/qs.log" 2>&1 </dev/null &
  echo "$!" >"$base/qs.sid"
  wait_for 400 grep -q 'Configuration Loaded' "$logs/qs.log" || die "the bar did not load; see $logs/qs.log"
  local t_qs=$(($(now_ms) - t0))
  trap - EXIT
  sleep 1
  local errors
  errors=$(sed 's/\x1b\[[0-9;]*m//g' "$logs/qs.log" | grep -E "$fail_pattern" | grep -vE "$expected_errors" || true)
  echo "shadow: '$name' up from ${src#"$HOME"/} (source ${t_src} ms, host ${t_host} ms, hyprland ${t_hypr} ms, bar ${t_qs} ms)"
  [[ -z $errors ]] || {
    echo "$errors" >&2
    echo "shadow: the bar logged errors (above); full log $logs/qs.log" >&2
  }
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
  local source="main checkout"
  [[ -f $base/branches ]] && source="test bar $(<"$base/test-bar") ($(paste -sd ' ' "$base/branches"))"
  echo "$name: up, ${#pids[@]} processes, $(pss_mb "${pids[@]}") MB PSS, source $source"
  echo "  runtime $runtime, signature $(cat "$base/signature" 2>/dev/null || echo none)"
  local component sid
  for component in qs hypr host bus; do
    sid=$(cat "$base/$component.sid" 2>/dev/null || true)
    if [[ -n $sid ]] && pgrep -s "$sid" >/dev/null; then echo "  $component: running (session $sid)"; else echo "  $component: not running"; fi
  done
  local errors
  errors=$(sed 's/\x1b\[[0-9;]*m//g' "$logs/qs.log" 2>/dev/null | grep -E "$fail_pattern" | grep -cvE "$expected_errors" || true)
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

# Stops whatever of the shadow is running and removes its runtime dir and test bar; logs and shots stay.
teardown() {
  local component pid left
  for component in qs hypr host bus; do kill_session "$component"; done
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
  teardown
  echo "shadow: '$name' down, no process references $runtime"
}

usage="usage: shadow.sh {up <name> [<branch>...]|ipc <name> <ipc call args>|keys <name> <wtype args>|hyprctl <name> <args>|shot <name> [<layer namespace>] [--pad N] [--out PATH]|status [<name>]|down <name>}"
cmd=${1:-}
(($# > 0)) && shift
case $cmd in
up) up "$@" ;;
ipc) ipc "$@" ;;
keys) keys "$@" ;;
hyprctl)
  set_name "${1:-}"
  shift
  shadow_hyprctl "$@"
  ;;
shot) shot "$@" ;;
status) status "$@" ;;
down) down "$@" ;;
*) die "$usage" ;;
esac
