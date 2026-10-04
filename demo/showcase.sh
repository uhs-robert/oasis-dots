#!/usr/bin/env bash
# demo/showcase.sh
# Scripted showcase video: shows each keybind on the overlay, then fires the action.

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(dirname -- "$script_dir")
overlay_dir=$script_dir/overlay
qs_ipc_bin=$HOME/.config/hypr/scripts/qs-ipc
state_dir=${XDG_RUNTIME_DIR:-/tmp}/oasis-demo

DEMO_OUTPUT=${DEMO_OUTPUT:-HDMI-A-1}
DEMO_PASSWORD=${DEMO_PASSWORD:-oasisdemo}
DEMO_FPS=${DEMO_FPS:-60}
DEMO_OUT_DIR=${DEMO_OUT_DIR:-$HOME/Videos/Recordings}
DEMO_LOCATION=${DEMO_LOCATION:-New York, NY}
DEMO_SEARCH_TEXT=${DEMO_SEARCH_TEXT:-uphill}
DEMO_PROTECT_PID=${DEMO_PROTECT_PID:-${KITTY_PID:-}}
DEMO_WEATHER_FILE=${DEMO_WEATHER_FILE:-$HOME/.config/quickshell/weather.local.json}
DEMO_RESET_KILL=${DEMO_RESET_KILL:-0}
DEMO_CLAUDE_CMD=${DEMO_CLAUDE_CMD:-claude --model haiku --disallowedTools Bash}

T_LEAD=${T_LEAD:-0.15}
T_KEY_GAP=${T_KEY_GAP:-0.1}
T_SETTLE=${T_SETTLE:-0.3}
T_TYPE_DELAY_MS=${T_TYPE_DELAY_MS:-70}
T_LOGIN_INTRO=${T_LOGIN_INTRO:-0.5}
T_LOGIN_TITLE_TURN=${T_LOGIN_TITLE_TURN:-2.0}
T_LOGIN_PAGE_TURN=${T_LOGIN_PAGE_TURN:-1.45}
T_LOGIN_HOLD=${T_LOGIN_HOLD:-0.25}
T_LOGIN_CHAR_GAP=${T_LOGIN_CHAR_GAP:-0.1}
T_LOGIN_UNLOCK=${T_LOGIN_UNLOCK:-3.85}
T_LOGIN_UNLOCK_MARGIN=${T_LOGIN_UNLOCK_MARGIN:-0.3}
T_WORK_TIMEOUT=${T_WORK_TIMEOUT:-90}
T_WORK_HOLD=${T_WORK_HOLD:-0.6}
T_OVERVIEW_HOLD=${T_OVERVIEW_HOLD:-1.0}
T_OVERVIEW_STEP=${T_OVERVIEW_STEP:-0.4}
T_OVERVIEW_JUMP=${T_OVERVIEW_JUMP:-0.7}
T_STYLE_HOLD=${T_STYLE_HOLD:-0.4}
T_MOVE_STEP=${T_MOVE_STEP:-0.4}
T_KEYBINDS_HOLD=${T_KEYBINDS_HOLD:-1.0}
T_TMUX_STEP=${T_TMUX_STEP:-0.35}
T_TMUX_HOLD=${T_TMUX_HOLD:-0.7}
T_SHOT_STEP=${T_SHOT_STEP:-0.18}
T_RESIZE_STEP=${T_RESIZE_STEP:-0.3}
T_SPLIT_HOLD=${T_SPLIT_HOLD:-0.6}
T_VOLUME_STEP=${T_VOLUME_STEP:-0.35}
T_SEARCH_HOLD=${T_SEARCH_HOLD:-1.2}
T_KEEPTABS_HOLD=${T_KEEPTABS_HOLD:-2.0}
DEMO_FAST=${DEMO_FAST:-5}
T_KEEPTABS_STEP=${T_KEEPTABS_STEP:-0.35}
T_SETTINGS_HOLD=${T_SETTINGS_HOLD:-0.6}
T_OUTRO_HOLD=${T_OUTRO_HOLD:-4.5}

scenes=(login work overview styles move_window keybinds tmux screenshot to_hdmi keeptabs settings outro)
work_classes=(eu.betterbird.Betterbird org.qutebrowser.qutebrowser firefox kitty-tmux-uphill kitty-tmux-config slack)
work_sessions=(UpHill Config)
declare -A reset_policy=(["firefox"]=kill)
declare -A style_reveal_ms=([oasis]=600 [snes]=450 [ff7]=500 [goldeneye]=500 [neovim]=400 [ps1]=500)

DRY=0
expect_ns=""
recorder_pid=""
rec_t0=""
fast_from=""
fast_ranges=()
weather_created=0
protect_pids=" "
protect_addrs=""

log() { printf '%s\n' "$*" >&2; }
die() {
  log "showcase: $*"
  exit 1
}
emit() { printf '  %-9s %s\n' "$1" "$2"; }

pause() {
  if ((DRY)); then
    emit pause "$1"
  else
    sleep "$1"
  fi
}

now_rel() { awk -v a="$(date +%s.%N)" -v b="$rec_t0" 'BEGIN { printf "%.2f", a - b }'; }

fast_begin() {
  [[ -z $rec_t0 ]] || fast_from=$(now_rel)
}

fast_end() {
  [[ -n $rec_t0 && -n $fast_from ]] || return 0
  fast_ranges+=("$fast_from $(now_rel)")
  fast_from=""
}

### protection ###

add_protected() { protect_pids+="$1 "; }

add_descendants() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null || true); do
    add_protected "$child"
    add_descendants "$child"
  done
}

init_protection() {
  local pid=$$
  while [[ -n $pid && $pid -gt 1 ]]; do
    add_protected "$pid"
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
  done
  add_descendants $$
  if [[ -n $DEMO_PROTECT_PID ]]; then
    add_protected "$DEMO_PROTECT_PID"
    add_descendants "$DEMO_PROTECT_PID"
    protect_addrs=$(hyprctl clients -j 2>/dev/null | jq -r --argjson p "$DEMO_PROTECT_PID" '[.[] | select(.pid == $p and (.class | startswith("kitty-tmux-") | not)) | .address] | join(" ")' || true)
  fi
  [[ -z ${DEMO_PROTECT_ADDR:-} ]] || protect_addrs=$DEMO_PROTECT_ADDR
}

is_protected_pid() { [[ $protect_pids == *" $1 "* ]]; }
is_protected_addr() { [[ -n $1 && " $protect_addrs " == *" $1 "* ]]; }

safe_kill() {
  local sig=$1 pid=$2
  if is_protected_pid "$pid"; then
    log "showcase: refusing to signal protected pid $pid"
    return 1
  fi
  kill "-$sig" "$pid" 2>/dev/null || true
}

### hyprland and quickshell ###

hypr_eval() {
  if ((DRY)); then
    emit eval "$1"
  else
    hyprctl eval "$1" >/dev/null
  fi
}

qs_ipc() {
  if ((DRY)); then
    emit qs-ipc "$*"
  else
    "$qs_ipc_bin" "$@"
  fi
}

qs_query() {
  if ((DRY)); then
    return 0
  fi
  "$qs_ipc_bin" "$@" 2>/dev/null || true
}

overlay_pid() { pgrep -nf "^qs -p $overlay_dir( |\$)" || true; }

overlay_ipc() {
  local pid
  pid=$(overlay_pid)
  [[ -n $pid ]] || return 1
  qs ipc --pid "$pid" call demo "$@" >/dev/null
}

overlay_keys() {
  if ((DRY)); then
    emit overlay "$1"
    return 0
  fi
  overlay_ipc keys "$1" || true
}

overlay_mask() {
  if ((DRY)); then
    emit overlay "mask x$1"
    return 0
  fi
  overlay_ipc mask "$1" || true
}

overlay_card() {
  if ((DRY)); then
    emit overlay "card $1"
    return 0
  fi
  overlay_ipc card "$1" || true
}

ensure_overlay() {
  if ((DRY)); then
    emit overlay "start $overlay_dir on $DEMO_OUTPUT"
    return 0
  fi
  [[ -z $(overlay_pid) ]] || return 0
  hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"env DEMO_OUTPUT=$DEMO_OUTPUT qs -p $overlay_dir\"))" >/dev/null
  mkdir -p "$state_dir"
  : >"$state_dir/overlay_started"
  local i
  for ((i = 0; i < 60; i++)); do
    overlay_ipc clear 2>/dev/null && return 0
    sleep 0.2
  done
  die "overlay did not start"
}

stop_overlay() {
  [[ -f $state_dir/overlay_started ]] || return 0
  local pid
  pid=$(overlay_pid)
  [[ -z $pid ]] || safe_kill TERM "$pid"
  rm -f "$state_dir/overlay_started"
}

layer_open() {
  [[ -n $1 ]] || return 1
  hyprctl layers -j | jq -e --arg o "$DEMO_OUTPUT" --arg ns "$1" '[.[$o].levels[][]? | select(.namespace == $ns)] | length > 0' >/dev/null
}

wait_layer_soft() {
  local ns=$1 timeout=${2:-5} i
  expect_ns=$ns
  if ((DRY)); then
    emit wait "layer $ns"
    return 0
  fi
  for ((i = 0; i < timeout * 10; i++)); do
    if layer_open "$ns"; then
      sleep "$T_SETTLE"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_layer() {
  wait_layer_soft "$@" || die "layer $1 did not open on $DEMO_OUTPUT"
}

wait_layer_gone() {
  local ns=$1 timeout=${2:-5} i
  if ((DRY)); then
    emit wait "layer $ns gone"
    expect_ns=""
    return 0
  fi
  for ((i = 0; i < timeout * 10; i++)); do
    if ! layer_open "$ns"; then
      expect_ns=""
      sleep "$T_SETTLE"
      return 0
    fi
    sleep 0.1
  done
  die "layer $ns did not close"
}

active_addr() { hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty'; }

abort_if_protected_active() {
  ((DRY)) && return 0
  if is_protected_addr "$(active_addr)"; then
    die "protected window is focused; aborting"
  fi
}

### input ###

guard_send() {
  [[ -n $protect_addrs ]] || return 0
  if is_protected_addr "$(active_addr)"; then
    layer_open "$expect_ns" || return 1
  fi
}

send() {
  if ((DRY)); then
    emit wtype "$*"
    return 0
  fi
  guard_send || die "protected window focused and no expected layer open; not typing"
  wtype "$@"
}

send_token() {
  local tok=$1 mods=() args=() m i
  while :; do
    case ${tok:0:1} in
    '+') mods+=(shift) ;;
    '^') mods+=(ctrl) ;;
    *) break ;;
    esac
    tok=${tok:1}
  done
  case $tok in
  x | X | @Delete) die "refusing to send close key '$tok'" ;;
  esac
  if [[ ${tok:0:1} == "@" ]]; then
    args=(-k "${tok:1}")
  else
    args=("$tok")
  fi
  if [[ ${#mods[@]} -gt 0 ]]; then
    local pre=() post=()
    for m in "${mods[@]}"; do
      pre+=(-M "$m")
    done
    for ((i = ${#mods[@]} - 1; i >= 0; i--)); do
      post+=(-m "${mods[i]}")
    done
    args=("${pre[@]}" "${args[@]}" "${post[@]}")
  fi
  send "${args[@]}"
}

# Text typed into a search field: never in a normal-mode overview, where letters are commands.
type_text() {
  if [[ $expect_ns == *overview* && $1 == *[xX]* ]]; then
    die "refusing to type 'x' while an overview is open"
  fi
  if ((${#1} <= 12)); then
    overlay_keys "${1^^}"
    pause "$T_LEAD"
  fi
  send -d "$T_TYPE_DELAY_MS" "$1"
}

press() {
  local label=$1 tok
  shift
  overlay_keys "$label"
  pause "$T_LEAD"
  for tok in "$@"; do
    [[ -n $tok ]] || continue
    send_token "$tok"
    pause "$T_KEY_GAP"
  done
}

bind() {
  overlay_keys "$1"
  pause "$T_LEAD"
  hypr_eval "$2"
}

ipc() {
  local label=$1
  shift
  overlay_keys "$label"
  pause "$T_LEAD"
  qs_ipc "$@"
}

leader_chord() {
  local key=$1
  shift
  overlay_keys "SUPER + SPACE"
  pause "$T_LEAD"
  hypr_eval 'hl.dispatch(hl.dsp.submap("Leader"))'
  pause 0.6
  overlay_keys "$key"
  pause "$T_LEAD"
  "$@"
  hypr_eval 'hl.dispatch(hl.dsp.submap("reset"))'
}

### state queries ###

out_id() { hyprctl monitors -j | jq -r --arg o "$DEMO_OUTPUT" '.[] | select(.name == $o) | .id'; }

out_ws_ids() {
  hyprctl workspaces -j | jq -r --arg o "$DEMO_OUTPUT" '[.[] | select(.monitor == $o and .id > 0) | .id] | sort | .[]'
}

ws_base() {
  local first
  first=$(out_ws_ids | head -n 1)
  printf '%s' $((((${first:-1} - 1) / 5) * 5 + 1))
}

slot_ws() { printf '%s\n' $(($(ws_base) + $1 - 1)); }

empty_slot() {
  local slot id
  for slot in 1 2 3 4 5; do
    id=$(slot_ws "$slot")
    if ! hyprctl clients -j | jq -e --argjson i "$id" 'any(.[]; .workspace.id == $i)' >/dev/null; then
      printf '%s' "$slot"
      return 0
    fi
  done
  return 1
}

go_slot() {
  local slot=$1 id
  id=$(slot_ws "$slot" || true)
  [[ -n $id ]] || id=$slot
  bind "SUPER + $slot" "hl.dispatch(hl.dsp.focus({ workspace = $id }))"
}

focus_output_monitor() {
  hypr_eval "hl.dispatch(hl.dsp.focus({ monitor = \"$DEMO_OUTPUT\" }))"
  ((DRY)) && return 0
  local i
  for ((i = 0; i < 30; i++)); do
    hyprctl monitors -j | jq -e --arg o "$DEMO_OUTPUT" 'any(.[]; .name == $o and .focused)' >/dev/null && return 0
    sleep 0.1
  done
  die "could not focus $DEMO_OUTPUT"
}

focus_output_window() {
  local hint=${1:-} addr i
  if ((DRY)); then
    emit focus "window on $DEMO_OUTPUT ${hint:+matching $hint}"
    return 0
  fi
  addr=$(hyprctl clients -j | jq -r --argjson m "$(out_id)" --arg hint "$hint" --arg prot "$protect_addrs" '
    ($prot | split(" ")) as $p
    | [.[] | select(.monitor == $m and .mapped and .workspace.id > 0 and (.address | IN($p[]) | not))]
    | sort_by(
        (if $hint != "" and ((.class + .title) | ascii_downcase | contains($hint | ascii_downcase)) then 0 else 1 end),
        (if .focusHistoryID == 0 then 0 else 1 end),
        .focusHistoryID)
    | .[0].address // empty')
  [[ -n $addr ]] || die "no unprotected window on $DEMO_OUTPUT to focus"
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"address:$addr\" }))" >/dev/null
  for ((i = 0; i < 30; i++)); do
    [[ $(active_addr) == "$addr" ]] && return 0
    sleep 0.1
  done
  die "could not focus window $addr"
}

focus_ws_window() {
  local addr
  if ((DRY)); then
    emit focus "window on the active workspace of $DEMO_OUTPUT"
    return 0
  fi
  addr=$(hyprctl clients -j | jq -r --argjson ws "$(hyprctl monitors -j | jq --arg o "$DEMO_OUTPUT" '.[] | select(.name == $o) | .activeWorkspace.id')" --arg prot "$protect_addrs" '
    ($prot | split(" ")) as $p
    | [.[] | select(.workspace.id == $ws and .mapped and (.address | IN($p[]) | not))]
    | sort_by(if (.class | test("(^|\\.)firefox$")) then 0 else 1 end) | .[0].address // empty')
  [[ -n $addr ]] || die "no window on the active workspace of $DEMO_OUTPUT"
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"address:$addr\" }))" >/dev/null
  sleep 0.3
}

browse_slot() {
  local base ws
  base=$(ws_base)
  ws=$(hyprctl clients -j | jq -r --argjson m "$(out_id)" '
    ([.[] | select(.class == "kitty-tmux-config") | .workspace.id]) as $busy
    | [.[] | select((.class | test("(^|\\.)firefox$")) and .monitor == $m and (.workspace.id | IN($busy[]) | not)) | .workspace.id] | sort | .[0] // empty')
  printf '%s' $((${ws:-$base} - base + 1))
}

assert_active_on_output() {
  ((DRY)) && return 0
  local addr
  addr=$(active_addr)
  is_protected_addr "$addr" && die "protected window focused"
  hyprctl activewindow -j | jq -e --argjson m "$(out_id)" '.monitor == $m' >/dev/null || die "focus left $DEMO_OUTPUT"
}

wait_style() {
  local name=$1 i
  if ((DRY)); then
    emit wait "style $name (+${style_reveal_ms[$name]:-500} ms reveal)"
    return 0
  fi
  for ((i = 0; i < 50; i++)); do
    [[ $(qs_query call style get) == "$name" ]] && break
    sleep 0.1
  done
  sleep "$(awk -v ms="${style_reveal_ms[$name]:-500}" 'BEGIN { printf "%.2f", ms / 1000 + 0.2 }')"
}

set_style() {
  local name=$1 label=$2
  ipc "Settings > Style > $label" call style set "$name"
  wait_style "$name"
}

wait_clients() {
  local timeout=$1 cls
  shift
  if ((DRY)); then
    emit wait "windows: $*"
    return 0
  fi
  local deadline=$((SECONDS + timeout))
  for cls in "$@"; do
    until hyprctl clients -j | jq -e --arg c "$cls" 'any(.[]; .class == $c or (.class | endswith("." + $c)))' >/dev/null; do
      ((SECONDS < deadline)) || die "window $cls did not appear"
      sleep 0.5
    done
  done
}

wait_browser_loaded() {
  if ((DRY)); then
    emit wait "browser pages loaded"
    return 0
  fi
  local i
  for ((i = 0; i < 40; i++)); do
    hyprctl clients -j | jq -e '[.[] | select(.class | test("(^|\\.)firefox$")) | .title] | length > 0 and all(.[]; test("^(Mozilla Firefox|)$") | not)' >/dev/null && break
    sleep 0.5
  done
  sleep 4
}

start_music() {
  if ((DRY)); then
    emit music "focus the YouTube window and press k"
    return 0
  fi
  local addr i
  addr=$(hyprctl clients -j | jq -r '[.[] | select((.class | test("(^|\\.)firefox$")) and (.title | test("YouTube")))][0].address // empty')
  if [[ -z $addr ]]; then
    log "showcase: no YouTube window; music not started"
    return 0
  fi
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"address:$addr\" }))" >/dev/null
  sleep 0.6
  [[ $(active_addr) == "$addr" ]] || return 0
  send k
  for ((i = 0; i < 30; i++)); do
    [[ $(playerctl status 2>/dev/null) == Playing ]] && return 0
    sleep 0.2
  done
  log "showcase: music did not start"
}

volume_step() {
  bind "$1" "require(\"lib.actions.media\").$2()()"
  pause "$T_VOLUME_STEP"
}

tab_count() {
  hyprctl clients -j | jq -r --argjson ws "$1" --arg c "$2" '
    [.[] | select(.workspace.id == $ws and .mapped)] | sort_by(.at[1], .at[0])
    | (map(.class | ascii_downcase | contains($c | ascii_downcase)) | index(true)) // 0'
}

window_ws() {
  hyprctl clients -j | jq -r --arg c "$1" '[.[] | select(.class | ascii_downcase | contains($c | ascii_downcase))][0].workspace.id // empty'
}

busy_output_ws() {
  hyprctl clients -j | jq -r --argjson m "$(out_id)" --arg prot "$protect_addrs" '
    ($prot | split(" ")) as $p
    | [.[] | select(.monitor == $m and .mapped and .workspace.id > 0 and (.address | IN($p[]) | not)) | .workspace.id] | sort | .[0] // empty'
}

ensure_claude_window() {
  if ((DRY)); then
    emit tmux "ensure window 'claude' in session Config"
    return 0
  fi
  if ! tmux has-session -t Config 2>/dev/null; then
    log "showcase: tmux session Config is not running yet; claude window not created"
    return 1
  fi
  tmux list-windows -t Config -F '#{window_name}' | grep -qx claude ||
    tmux new-window -d -t Config: -n claude -c "${DEMO_CLAUDE_DIR:-$repo_dir}" "$DEMO_CLAUDE_CMD"
}

### stage and restore ###

validate_config() {
  [[ $DEMO_PASSWORD =~ ^[abcdefghijklmnoprstuvwxyzABCDEFGHIJKLMNOPRSTUVWXYZ]+$ ]] || die "DEMO_PASSWORD must be letters only and contain no q"
  [[ $DEMO_FPS =~ ^[0-9]+$ ]] || die "DEMO_FPS must be a number"
}

on_battery() {
  local dir found=0
  for dir in /sys/class/power_supply/*; do
    [[ -r $dir/type && $(<"$dir/type") == Mains ]] || continue
    found=1
    [[ $(<"$dir/online") == 1 ]] && return 1
  done
  ((found))
}

preflight() {
  local t lock tools=(hyprctl jq wtype qs tmux awk)
  [[ ${1:-} == record ]] && tools+=(wf-recorder ffmpeg)
  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null || die "missing tool: $t"
  done
  [[ -x $qs_ipc_bin ]] || die "missing $qs_ipc_bin"
  hyprctl monitors -j | jq -e --arg o "$DEMO_OUTPUT" 'any(.[]; .name == $o)' >/dev/null || die "output $DEMO_OUTPUT not found"
  lock=$(qs_query call lock state)
  [[ $lock == unlocked ]] || die "lock state is '${lock:-unknown}'; unlock first"
  ! on_battery || die "on battery: style transitions are skipped, plug in"
  if [[ -z $protect_addrs ]]; then
    log "showcase: warning: no protected terminal window resolved (set DEMO_PROTECT_PID)"
  fi
}

reset_region_zoom() {
  ipc "Screenshot" call screenshot select false toolbar
  wait_layer quickshell-region
  send_token o
  send_token o
  send_token o
  send_token i
  send_token q
  wait_layer_gone quickshell-region
}

stage_weather() {
  ((DRY)) && {
    emit weather "write {location_name: $DEMO_LOCATION} to $DEMO_WEATHER_FILE"
    return 0
  }
  mkdir -p "$state_dir"
  if [[ -f $DEMO_WEATHER_FILE && ! -f $state_dir/weather_created ]]; then
    cp -- "$DEMO_WEATHER_FILE" "$state_dir/weather.bak"
  fi
  jq -n --arg n "$DEMO_LOCATION" '{location_name: $n}' >"$DEMO_WEATHER_FILE"
  : >"$state_dir/weather_created"
}

restore_weather() {
  [[ -f $state_dir/weather_created ]] || return 0
  if [[ -f $state_dir/weather.bak ]]; then
    mv -- "$state_dir/weather.bak" "$DEMO_WEATHER_FILE"
  else
    rm -f -- "$DEMO_WEATHER_FILE"
  fi
  rm -f "$state_dir/weather_created"
}

stage() {
  validate_config
  ((DRY)) || preflight
  focus_output_monitor
  qs_ipc call style set oasis
  ((DRY)) || wait_style oasis
  stage_weather
  reset_region_zoom
  ensure_claude_window || true
  ((DRY)) || {
    mkdir -p "$state_dir"
    : >"$state_dir/staged"
  }
}

restore_ui() {
  hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))' >/dev/null 2>&1 || true
  "$qs_ipc_bin" call popup close >/dev/null 2>&1 || true
  "$qs_ipc_bin" call overview close >/dev/null 2>&1 || true
  "$qs_ipc_bin" call tmux-overview close >/dev/null 2>&1 || true
  "$qs_ipc_bin" call picker close >/dev/null 2>&1 || true
  "$qs_ipc_bin" call lock preview_close >/dev/null 2>&1 || true
  "$qs_ipc_bin" call screenshot close >/dev/null 2>&1 || true
  "$qs_ipc_bin" call style set oasis >/dev/null 2>&1 || true
  playerctl pause >/dev/null 2>&1 || true
  overlay_ipc card false 2>/dev/null || true
  overlay_ipc clear 2>/dev/null || true
}

stop_recorder() {
  [[ -n $recorder_pid ]] || return 0
  safe_kill INT "$recorder_pid"
  wait "$recorder_pid" 2>/dev/null || true
  recorder_pid=""
}

restore() {
  if ((DRY)); then
    emit restore "submap reset, close popups/overview/picker/preview, style oasis, drop spoofed weather, stop recorder"
    return 0
  fi
  stop_recorder
  restore_ui
  restore_weather
  stop_overlay
}

cleanup() {
  local status=$?
  trap - EXIT
  if ((!DRY)); then
    stop_recorder
    restore_ui
    if ((weather_created)); then restore_weather; fi
    stop_overlay
  fi
  exit "$status"
}

### reset ###

snapshot_windows() {
  if ((DRY)); then
    emit snapshot "window addresses, slack, tmux sessions -> $state_dir/snapshot.json"
    return 0
  fi
  mkdir -p "$state_dir"
  local slack=false sessions="" s
  pgrep -x slack >/dev/null 2>&1 && slack=true
  for s in "${work_sessions[@]}"; do
    tmux has-session -t "=$s" 2>/dev/null && sessions+="$s "
  done
  hyprctl clients -j | jq --argjson slack "$slack" --arg sessions "$sessions" --arg prot "$protect_addrs" '
    {addresses: [.[].address], protected: ($prot | split(" ") | map(select(. != ""))), slack: $slack, sessions: ($sessions | split(" ") | map(select(. != "")))}' >"$state_dir/snapshot.json"
}

closable_windows() {
  local snap=$state_dir/snapshot.json
  if [[ -f $snap ]]; then
    hyprctl clients -j | jq -r --slurpfile s "$snap" --arg prot "$protect_addrs" '
      ($prot | split(" ")) as $p
      | $s[0] as $snap
      | .[] | select((.address | IN($snap.addresses[]) | not) and (.address | IN($snap.protected[]) | not) and (.address | IN($p[]) | not))
      | [.address, (.pid | tostring), .class] | @tsv'
  else
    hyprctl clients -j | jq -r --argjson cls "$(printf '%s\n' "${work_classes[@]}" | jq -R . | jq -s .)" --arg prot "$protect_addrs" '
      ($prot | split(" ")) as $p
      | .[] | select(((.class | IN($cls[])) or (.class | endswith(".firefox"))) and (.address | IN($p[]) | not))
      | [.address, (.pid | tostring), .class] | @tsv'
  fi
}

session_has_protected_pane() {
  local pid
  for pid in $(tmux list-panes -s -t "=$1" -F '#{pane_pid}' 2>/dev/null); do
    is_protected_pid "$pid" && return 0
  done
  return 1
}

inside_tmux() {
  local pid
  [[ -z ${TMUX:-} ]] || return 0
  for pid in $protect_pids; do
    [[ $(cat "/proc/$pid/comm" 2>/dev/null) == tmux* ]] && return 0
  done
  return 1
}

reset_policy_of() {
  [[ $DEMO_RESET_KILL == 1 ]] && {
    printf kill
    return 0
  }
  printf '%s' "${reset_policy[${1##*.}]:-close}"
}

alive() { kill -0 "$1" 2>/dev/null; }

terminate_pid() {
  local pid=$1 i
  safe_kill TERM "$pid" || return 0
  for ((i = 0; i < 50; i++)); do
    alive "$pid" || return 0
    sleep 0.1
  done
  safe_kill KILL "$pid" || true
}

close_window() {
  hyprctl eval "hl.dispatch(hl.dsp.window.close({ window = \"address:$1\" }))" >/dev/null
}

reset_sessions() {
  local snap=$state_dir/snapshot.json s
  [[ -f $snap ]] || return 0
  for s in "${work_sessions[@]}"; do
    jq -e --arg s "$s" '.sessions | index($s) | not' "$snap" >/dev/null || continue
    if ((DRY)); then
      emit tmux "kill-session -t $s (if it exists and holds no protected pane)"
      continue
    fi
    tmux has-session -t "=$s" 2>/dev/null || continue
    session_has_protected_pane "$s" && continue
    tmux kill-session -t "=$s"
  done
}

reset_tmux_server() {
  [[ ${DEMO_RESET_TMUX_SERVER:-0} == 1 ]] || return 0
  if inside_tmux; then
    log "showcase: warning: protected chain is inside tmux; not killing the tmux server"
    return 0
  fi
  if ((DRY)); then
    emit tmux "kill-server (DEMO_RESET_TMUX_SERVER=1), then close leftover kitty-tmux windows"
    return 0
  fi
  tmux kill-server 2>/dev/null || true
  sleep 1
  local row addr
  while IFS=$'\t' read -r addr _ row; do
    [[ $row == kitty-tmux-* ]] && ! is_protected_addr "$addr" && close_window "$addr"
  done < <(closable_windows)
}

reset_work() {
  local snap=$state_dir/snapshot.json row addr pid cls policy slot
  local rows=() kill_pids=()
  if ((DRY)); then
    emit protected "pids:$protect_pids"
    emit protected "windows: ${protect_addrs:-none}"
    emit snapshot "$([[ -f $snap ]] && echo "$snap" || echo "none, falling back to Work classes")"
  fi
  reset_sessions
  ((DRY)) || sleep 1
  mapfile -t rows < <(closable_windows)
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r addr pid cls <<<"$row"
    is_protected_addr "$addr" && continue
    policy=$(reset_policy_of "$cls")
    if ((DRY)); then
      emit "$policy" "$addr ($cls, pid $pid)"
      continue
    fi
    if [[ $policy == kill ]]; then
      kill_pids+=("$pid")
    else
      close_window "$addr"
    fi
  done
  reset_tmux_server
  if ((DRY)); then
    emit restore "then restore and focus an empty workspace on $DEMO_OUTPUT"
    return 0
  fi
  sleep 2
  for pid in "${kill_pids[@]}"; do
    terminate_pid "$pid"
  done
  restore_ui
  slot=$(empty_slot || true)
  if [[ -n $slot ]]; then
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $(slot_ws "$slot") }))" >/dev/null
  fi
  rm -f "$snap"
}

### scenes ###

login_open() {
  expect_ns=quickshell-lock-preview
  if ! ((DRY)) && layer_open quickshell-lock-preview; then return 0; fi
  focus_output_monitor
  qs_ipc call lock preview mgs2
  wait_layer quickshell-lock-preview 10
}

scene_login() {
  local i ch
  login_open
  pause "$T_LOGIN_INTRO"
  press "ENTER" @Return
  pause "$T_LOGIN_TITLE_TURN"
  pause "$T_LOGIN_HOLD"
  press "J" j
  pause "$T_LOGIN_HOLD"
  press "K" k
  pause "$T_LOGIN_HOLD"
  press "ENTER" @Return
  pause "$T_LOGIN_PAGE_TURN"
  pause "$T_LOGIN_HOLD"
  press "ENTER" @Return
  pause "$T_LOGIN_PAGE_TURN"
  pause "$T_LOGIN_HOLD"
  for ((i = 0; i < ${#DEMO_PASSWORD}; i++)); do
    ch=${DEMO_PASSWORD:i:1}
    send "$ch"
    overlay_mask $((i + 1))
    pause "$T_LOGIN_CHAR_GAP"
  done
  pause "$T_LOGIN_HOLD"
  press "ENTER" +@Return
  pause "$T_LOGIN_UNLOCK"
  pause "$T_LOGIN_UNLOCK_MARGIN"
  qs_ipc call lock preview_close
  wait_layer_gone quickshell-lock-preview 5
}

scene_work() {
  snapshot_windows
  focus_output_monitor
  bind "SUPER + SHIFT + O" 'require("extensions.auto_launcher.launcher").show_picker()'
  wait_layer quickshell-popup
  type_text "work"
  pause "$T_MOVE_STEP"
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  pause 1.2
  fast_begin
  wait_clients "$T_WORK_TIMEOUT" "${work_classes[@]}"
  ensure_claude_window || true
  wait_browser_loaded
  start_music
  qs_ipc call style set ps1
  wait_style ps1
  fast_end
  pause "$T_WORK_HOLD"
}

scene_overview() {
  [[ $(qs_query call style get) == ps1 ]] || set_style ps1 PSX
  ipc "SUPER + TAB" call overview open
  wait_layer quickshell-overview
  pause "$T_OVERVIEW_HOLD"
  press "CTRL + L" ^l
  pause "$T_OVERVIEW_JUMP"
  press "CTRL + H" ^h
  pause "$T_OVERVIEW_JUMP"
  press "TAB" @Tab
  pause "$T_OVERVIEW_JUMP"
  press "SHIFT + TAB" +@Tab
  pause "$T_OVERVIEW_JUMP"
  press "ENTER" @Return
  wait_layer_gone quickshell-overview
  assert_active_on_output
}

scene_styles() {
  volume_step "SUPER + ALT + J" volume_down
  volume_step "SUPER + ALT + J" volume_down
  volume_step "SUPER + ALT + K" volume_up
  volume_step "SUPER + ALT + K" volume_up
  pause "$T_TMUX_HOLD"
  leader_chord W qs_ipc call popup open weather
  wait_layer quickshell-popup
  pause "$T_STYLE_HOLD"
  set_style oasis Oasis
  pause "$T_STYLE_HOLD"
  set_style snes SNES
  pause "$T_STYLE_HOLD"
  set_style ff7 FFVII
  pause "$T_STYLE_HOLD"
  set_style goldeneye Goldeneye
  pause "$T_STYLE_HOLD"
  set_style neovim Neovim
  pause "$T_STYLE_HOLD"
  press "Q" q
  wait_layer_gone quickshell-popup
}

scene_move_window() {
  local dest="" cur slot id
  set_style ps1 PSX
  focus_output_window
  ipc "SUPER + T" call overview search
  wait_layer quickshell-overview
  type_text "$DEMO_SEARCH_TEXT"
  pause "$T_SEARCH_HOLD"
  press "ENTER" @Return
  wait_layer_gone quickshell-overview
  pause "$T_SEARCH_HOLD"
  assert_active_on_output
  ipc "SUPER + SHIFT + T" call overview move_follow
  wait_layer quickshell-overview
  pause "$T_SEARCH_HOLD"
  if ((DRY)); then
    dest=11
  else
    cur=$(hyprctl activewindow -j | jq -r '.workspace.id')
    for slot in 1 2 3; do
      id=$(slot_ws "$slot")
      if [[ $id != "$cur" ]]; then
        dest=$id
        break
      fi
    done
  fi
  press "${dest:0:1} ${dest:1}" "$dest"
  pause "$T_SEARCH_HOLD"
  press "ENTER" @Return
  wait_layer_gone quickshell-overview
  pause "$T_SEARCH_HOLD"
}

scene_keybinds() {
  local query="window right" matches
  if ! ((DRY)); then
    matches=$(hyprctl binds -j | jq -r --arg q "$query" '[.[] | select(.has_description and .submap == "" and (.description | ascii_downcase | contains($q))) | .description] | join("|")')
    [[ $matches == "Move Window Right" ]] || die "keybind finder query '$query' no longer maps to one safe bind ($matches)"
  fi
  focus_output_window
  bind "SUPER + /" 'require("lib.actions.menu").keybinds()()'
  wait_layer quickshell-popup
  type_text "$query"
  pause "$T_SEARCH_HOLD"
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  pause "$T_KEYBINDS_HOLD"
}

scene_tmux() {
  local ch
  ensure_claude_window || true
  focus_output_window
  ipc "ALT + GRAVE" call tmux-overview open
  wait_layer quickshell-tmux-overview
  pause "$T_TMUX_HOLD"
  for ch in l j; do
    press "${ch^^}" "$ch"
    pause "$T_TMUX_STEP"
  done
  press "/" /
  type_text "claude"
  pause "$T_TMUX_HOLD"
  press "ENTER" @Return
  wait_layer_gone quickshell-tmux-overview
  pause "$T_TMUX_HOLD"
  assert_active_on_output
  type_text "What do you think of my dotfiles?"
  pause "$T_TMUX_STEP"
  press "ENTER" @Return
  if ((DRY)); then go_slot 1; else go_slot "$(browse_slot)"; fi
}

scene_screenshot() {
  focus_ws_window
  overlay_keys "PRINT"
  pause "$T_LEAD"
  ipc "R" call screenshot select false toolbar
  wait_layer quickshell-region
  pause "$T_SHOT_STEP"
  local tok key
  for key in h h k k; do
    press "SHIFT + ${key^^}" "+$key"
    pause "$T_SHOT_STEP"
  done
  press "V" v
  for key in l l l j j; do
    press "SHIFT + ${key^^}" "+$key"
    pause "$T_SHOT_STEP"
  done
  press "I" i
  pause "$T_TMUX_STEP"
  press "O" o
  pause "$T_SHOT_STEP"
  press "SHIFT + O" +o
  pause "$T_SHOT_STEP"
  for tok in h k; do
    press "${tok^^}" "$tok"
    pause "$T_SHOT_STEP"
  done
  pause "$T_TMUX_STEP"
  press "Q" q
  wait_layer_gone quickshell-region
}

move_marked_windows() {
  local src=$1 dest=$2 n
  if ! ((DRY)); then
    hyprctl clients -j | jq -e --argjson ws "$src" --arg prot "$protect_addrs" '
      ($prot | split(" ")) as $p | [.[] | select(.workspace.id == $ws)] | length >= 2 and all(.[]; .address | IN($p[]) | not)' >/dev/null ||
      die "workspace $src does not hold the windows to move"
  fi
  ipc "SUPER + TAB" call overview open
  wait_layer quickshell-overview
  pause "$T_OVERVIEW_STEP"
  press "${src:0:1} ${src:1}" "$src"
  pause "$T_OVERVIEW_JUMP"
  press "SHIFT + V" +v
  pause "$T_OVERVIEW_JUMP"
  press "M" m
  pause "$T_OVERVIEW_JUMP"
  press "${dest:0:1} ${dest:1}" "$dest"
  pause "$T_OVERVIEW_JUMP"
  press "M" m
  pause "$T_OVERVIEW_JUMP"
  if ((DRY)); then n=1; else n=$(tab_count "$dest" slack || echo 0); fi
  while ((n > 0)); do
    press "TAB" @Tab
    pause "$T_OVERVIEW_STEP"
    n=$((n - 1))
  done
}

resize_step() {
  local label=$1 x=$2 y=$3
  bind "$label" "hl.dispatch(hl.dsp.window.resize({ x = $x, y = $y, relative = true }))"
  pause "$T_RESIZE_STEP"
}

scene_to_hdmi() {
  focus_output_monitor
  local src
  src=$(window_ws slack || true)
  move_marked_windows "${src:-16}" "$(slot_ws 4)"
  press "ENTER" @Return
  wait_layer_gone quickshell-overview
  pause "$T_MOVE_STEP"
  assert_active_on_output
  hypr_eval 'hl.dispatch(hl.dsp.layout("togglesplit"))'
  pause "$T_SPLIT_HOLD"
  bind "SUPER + R" 'hl.dispatch(hl.dsp.submap("Resize"))'
  wait_layer_soft quickshell-whichkey || log "showcase: which-key did not show"
  pause "$T_TMUX_HOLD"
  abort_if_protected_active
  resize_step "SHIFT + J" 0 100
  resize_step "SHIFT + J" 0 100
  resize_step "SHIFT + J" 0 100
  resize_step "SHIFT + K" 0 -100
  bind "ESC" 'hl.dispatch(hl.dsp.submap("reset"))'
  expect_ns=""
  pause "$T_MOVE_STEP"
}

keeptabs_steps() {
  local pane
  pane=$(tmux list-panes -t Config:claude -F '#{pane_id}' 2>/dev/null | head -n 1 || true)
  [[ -n $pane ]] || {
    printf '0'
    return 0
  }
  "$HOME/.local/bin/keeptabs-pick" --json 2>/dev/null | jq -r --arg p "$pane" '[.[].tmux_pane] | index($p) // 0'
}

scene_keeptabs() {
  local n=0
  ((DRY)) || n=$(keeptabs_steps)
  ipc "SUPER + CTRL + A" call popup open keeptabs
  wait_layer quickshell-popup
  pause "$T_KEEPTABS_HOLD"
  while ((n > 0)); do
    press "J" j
    pause "$T_KEEPTABS_STEP"
    n=$((n - 1))
  done
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  pause "$T_KEEPTABS_HOLD"
  assert_active_on_output
}

scene_settings() {
  local pair
  leader_chord S qs_ipc call popup open settings
  wait_layer quickshell-popup
  pause "$T_SETTINGS_HOLD"
  for pair in "1:Style" "2:Colors" "3:Theme options" "4:Bar modules" "9:Lock screen"; do
    press "${pair%%:*}" "${pair%%:*}"
    pause "$T_SETTINGS_HOLD"
  done
  press "J" j
  pause "$T_SETTINGS_HOLD"
  press "Q" q
  wait_layer_gone quickshell-popup
}

scene_outro() {
  local slot
  qs_ipc call popup close
  qs_ipc call overview close
  qs_ipc call tmux-overview close
  set_style oasis Oasis
  if ((DRY)); then
    emit focus "an empty workspace on $DEMO_OUTPUT"
  else
    slot=$(empty_slot || true)
    [[ -z $slot ]] || go_slot "$slot"
  fi
  pause "$T_SETTLE"
  overlay_card true
  pause "$T_OUTRO_HOLD"
}

### recording ###

start_recorder() {
  local raw=$1
  if ((DRY)); then
    emit record "wf-recorder -o $DEMO_OUTPUT -r $DEMO_FPS -f $raw"
    return 0
  fi
  rec_t0=$(date +%s.%N)
  wf-recorder -o "$DEMO_OUTPUT" -r "$DEMO_FPS" -f "$raw" >/dev/null 2>&1 &
  recorder_pid=$!
  sleep 0.6
  kill -0 "$recorder_pid" 2>/dev/null || die "wf-recorder failed to start"
}

encode() {
  local raw=$1 out=$2
  if ((DRY)); then
    emit encode "ffmpeg $raw -> $out (H.264 yuv420p 1920x1080 ${DEMO_FPS} fps)"
    return 0
  fi
  local filter="" labels="" prev=0 n=0 r from to
  for r in "${fast_ranges[@]}"; do
    read -r from to <<<"$r"
    filter+="[0:v]trim=$prev:$from,setpts=PTS-STARTPTS[s$n];"
    filter+="[0:v]trim=$from:$to,setpts=(PTS-STARTPTS)/${DEMO_FAST}[s$((n + 1))];"
    labels+="[s$n][s$((n + 1))]"
    n=$((n + 2))
    prev=$to
  done
  filter+="[0:v]trim=start=$prev,setpts=PTS-STARTPTS[s$n];"
  labels+="[s$n]"
  filter+="${labels}concat=n=$((n + 1)):v=1,scale=1920:1080:flags=lanczos,format=yuv420p,fps=${DEMO_FPS}[v]"
  printf '%s\n' "${fast_ranges[@]}" >"$raw.fast"
  ffmpeg -y -loglevel error -i "$raw" -filter_complex "$filter" -map "[v]" \
    -c:v libx264 -preset slow -crf 18 -movflags +faststart "$out"
  log "showcase: wrote $out"
}

run_scene() {
  local name=$1
  declare -F "scene_$name" >/dev/null || die "unknown scene '$name' (try: list)"
  printf '== scene %s\n' "$name"
  "scene_$name"
}

run_all() {
  local name
  for name in "${scenes[@]}"; do
    run_scene "$name"
  done
}

record() {
  local stamp raw out
  stamp=$(date +%Y-%m-%d_%Hh%Mm%Ss)
  raw=$DEMO_OUT_DIR/showcase-$stamp.raw.mp4
  out=$DEMO_OUT_DIR/showcase-$stamp.mp4
  ((DRY)) || mkdir -p "$DEMO_OUT_DIR"
  stage
  weather_created=1
  ensure_overlay
  login_open
  start_recorder "$raw"
  run_all
  stop_recorder
  encode "$raw" "$out"
  restore
}

usage() {
  cat <<EOF
usage: showcase.sh [--dry-run] <command>

  stage          prepare the desktop (focus, style, weather, tmux claude window, zoom)
  scene <name>   run one scene; see: list
  all            run every scene in order
  record         stage, record $DEMO_OUTPUT, run all scenes, encode, restore
  restore        undo stage and close everything the scenes open
  reset          close the windows Work opened and restore
  list           print scene names
EOF
}

main() {
  local args=() a cmd
  for a in "$@"; do
    if [[ $a == --dry-run ]]; then
      DRY=1
    else
      args+=("$a")
    fi
  done
  cmd=${args[0]:-}
  case $cmd in
  list)
    printf '%s\n' "${scenes[@]}"
    return 0
    ;;
  "" | -h | --help | help)
    usage
    return 0
    ;;
  esac
  command -v hyprctl >/dev/null || die "missing tool: hyprctl"
  init_protection
  if ((DRY)); then
    printf 'protected window: %s\n' "${protect_addrs:-none}"
  else
    trap cleanup EXIT
    trap 'exit 130' INT TERM
  fi
  case $cmd in
  stage) stage ;;
  scene)
    [[ -n ${args[1]:-} ]] || die "usage: showcase.sh scene <name>"
    validate_config
    ((DRY)) || preflight
    ensure_overlay
    run_scene "${args[1]}"
    ;;
  all)
    validate_config
    ((DRY)) || preflight
    ensure_overlay
    run_all
    ;;
  record)
    validate_config
    ((DRY)) || preflight record
    record
    ;;
  restore) restore ;;
  reset) reset_work ;;
  *) die "unknown command '$cmd'" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
