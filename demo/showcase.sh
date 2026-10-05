#!/usr/bin/env bash
# demo/showcase.sh
# Scripted showcase video: each beat shows its keys on the overlay, then fires the action; `record` films one
# clip per beat and `edit` cuts them into the video.

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
overlay_dir=$script_dir/overlay
stage_tmux=$script_dir/stage-tmux.sh
qs_ipc_bin=$HOME/.config/hypr/scripts/qs-ipc
hypr_state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/hypr
state_dir=${XDG_RUNTIME_DIR:-/tmp}/oasis-demo

# Connector names change when a dock re-enumerates (DP-8 came back as DP-7), so by default pick the output by
# shape: the landscape 1920x1080 one.
DEMO_OUTPUT=${DEMO_OUTPUT:-$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | select(.width == 1920 and .height == 1080 and .transform % 2 == 0)][0].name // "DP-8"' 2>/dev/null || echo DP-8)}
DEMO_PASSWORD=${DEMO_PASSWORD:-oasisdemo}
DEMO_FPS=${DEMO_FPS:-60}
DEMO_OUT_DIR=${DEMO_OUT_DIR:-$HOME/Videos/Recordings}
DEMO_AUDIO=${DEMO_AUDIO:-default}
DEMO_LOCATION=${DEMO_LOCATION:-Kokiri Forest}
DEMO_SESSION_QUERY=${DEMO_SESSION_QUERY:-demo}
DEMO_SEARCH_TEXT=${DEMO_SEARCH_TEXT:-dotfiles}
DEMO_AGENT_PROMPT=${DEMO_AGENT_PROMPT:-summarize the dotfiles readme in three bullets}
DEMO_START_STYLE=${DEMO_START_STYLE:-neovim}
DEMO_PALETTES=${DEMO_PALETTES:-lagoon mirage sol moonlight}
# Style id and the name typed into Settings > Style's filter, in the order the styles beat switches them.
DEMO_STYLES=${DEMO_STYLES:-ff7:ffvii goldeneye:goldeneye gameboy:gameboy metroid:metroid tie:tie ps1:psx}
# One image for the whole take; empty keeps whatever the output shows when `stage` runs.
DEMO_WALLPAPER=${DEMO_WALLPAPER:-}
DEMO_PROTECT_PID=${DEMO_PROTECT_PID:-${KITTY_PID:-}}
DEMO_WEATHER_FILE=${DEMO_WEATHER_FILE:-$HOME/.config/quickshell/weather.local.json}
DEMO_FAST=${DEMO_FAST:-5}
# A sped-up stretch never plays longer than this; slow app start-up is mostly an unchanging screen.
DEMO_FAST_MAX=${DEMO_FAST_MAX:-1.5}

T_LEAD=${T_LEAD:-0.15}
T_KEY_GAP=${T_KEY_GAP:-0.1}
T_SETTLE=${T_SETTLE:-0.3}
T_TYPE_DELAY_MS=${T_TYPE_DELAY_MS:-70}
T_CLIP_TAIL=${T_CLIP_TAIL:-0.3}
T_LOGIN_INTRO=${T_LOGIN_INTRO:-0.5}
T_LOGIN_TITLE_TURN=${T_LOGIN_TITLE_TURN:-2.0}
T_LOGIN_PAGE_TURN=${T_LOGIN_PAGE_TURN:-1.45}
T_LOGIN_HOLD=${T_LOGIN_HOLD:-0.25}
T_LOGIN_CHAR_GAP=${T_LOGIN_CHAR_GAP:-0.1}
T_LOGIN_UNLOCK=${T_LOGIN_UNLOCK:-3.85}
T_EMPTY_HOLD=${T_EMPTY_HOLD:-0.5}
T_SESSION_TIMEOUT=${T_SESSION_TIMEOUT:-60}
T_SESSION_HOLD=${T_SESSION_HOLD:-1.5}
T_RESIZE_STEP=${T_RESIZE_STEP:-0.35}
T_RESIZE_HOLD=${T_RESIZE_HOLD:-1.0}
T_SETTINGS_HOLD=${T_SETTINGS_HOLD:-0.6}
T_PALETTE_HOLD=${T_PALETTE_HOLD:-1.2}
T_TURN_HOLD=${T_TURN_HOLD:-1.5}
T_MOVE_HOLD=${T_MOVE_HOLD:-0.8}
T_STYLE_HOLD=${T_STYLE_HOLD:-1.2}
T_SURFACE_HOLD=${T_SURFACE_HOLD:-1.4}
T_KICKOFF_HOLD=${T_KICKOFF_HOLD:-1.0}
T_OVERVIEW_STEP=${T_OVERVIEW_STEP:-0.6}
T_SEARCH_HOLD=${T_SEARCH_HOLD:-1.0}
T_PROMPT_HOLD=${T_PROMPT_HOLD:-1.4}
T_LAYOUT_HOLD=${T_LAYOUT_HOLD:-2.0}
T_SHOT_STEP=${T_SHOT_STEP:-0.12}
T_SHOT_KEY_GAP=${T_SHOT_KEY_GAP:-0.04}
T_TOAST_HOLD=${T_TOAST_HOLD:-1.8}
T_AGENT_TIMEOUT=${T_AGENT_TIMEOUT:-180}
T_PULSE_HOLD=${T_PULSE_HOLD:-2.0}
T_KEEPTABS_HOLD=${T_KEEPTABS_HOLD:-1.2}
T_ANSWER_HOLD=${T_ANSWER_HOLD:-3.0}
T_OUTRO_HOLD=${T_OUTRO_HOLD:-4.5}

beats=(unlock session resize palettes turn move styles kickoff overview region prompt keeptabs outro)
# The README hero is cut from these.
hero_beats=(palettes turn styles)
stage_classes=(kitty-tmux-dotfiles firefox kitty-tmux-agent kitty-tmux-monitor kitty-tmux-git kitty-tmux-readme)
declare -A style_reveal_ms=([neovim]=400 [ps1]=500 [ff7]=500 [goldeneye]=500 [gameboy]=500 [metroid]=500 [tie]=500)

DRY=0
# Set while a stage is live but not yet restored, so a failing take puts the owner's settings back on exit.
restore_on_exit=0
expect_ns=""
recorder_pid=""
rec_t0=""
fast_from=""
fast_ranges=()
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

# Marks a stretch of the current clip for `edit` to play DEMO_FAST times faster, such as apps starting.
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

# kitty shares one pid across its windows, so the stage's own terminals are told apart by class; every other
# window of the protected kitty, including the owner's other kitty-tmux-* sessions, stays protected.
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
    protect_addrs=$(hyprctl clients -j 2>/dev/null | jq -r --argjson p "$DEMO_PROTECT_PID" --argjson stage "$(printf '%s\n' "${stage_classes[@]}" | jq -R . | jq -s .)" '[.[] | select(.pid == $p and (.class | IN($stage[]) | not)) | .address] | join(" ")' || true)
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
  ((DRY)) && return 0
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

wait_layer() {
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
  die "layer $ns did not open on $DEMO_OUTPUT"
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

### input ###

# Typing is allowed into the protected terminal only while an expected layer holds the keyboard.
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

# A token is a key with `+` (shift) and `^` (ctrl) prefixes; `@Name` sends a keysym.
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

# wtype cannot hold a Hyprland submap, so the Leader submap is entered with eval under its key caption.
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

go_slot() {
  focus_output_monitor
  if ((DRY)); then
    emit focus "workspace slot $1 on $DEMO_OUTPUT"
    return 0
  fi
  hypr_eval "hl.dispatch(hl.dsp.focus({ workspace = $(slot_ws "$1") }))"
}

# Only the output's own windows: the owner's other Firefox windows share the class.
class_addr() { hyprctl clients -j | jq -r --arg c "$1" --argjson m "$(out_id)" '[.[] | select(.class == $c and .monitor == $m)][0].address // empty'; }

focus_class() {
  local cls=$1 addr i
  if ((DRY)); then
    emit focus "window $cls"
    return 0
  fi
  addr=$(class_addr "$cls")
  [[ -n $addr ]] || die "no $cls window"
  is_protected_addr "$addr" && die "refusing to focus protected window $addr"
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"address:$addr\" }))" >/dev/null
  for ((i = 0; i < 30; i++)); do
    [[ $(active_addr) == "$addr" ]] && return 0
    sleep 0.1
  done
  die "could not focus $cls"
}

assert_active_class() {
  ((DRY)) && return 0
  local cls
  cls=$(hyprctl activewindow -j | jq -r '.class // empty')
  [[ $cls == "$1" ]] || die "expected $1 focused, found '${cls:-nothing}'"
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

current_palette() { cat "$hypr_state_dir/theme" 2>/dev/null || true; }

wait_palette() {
  local name=$1 i
  if ((DRY)); then
    emit wait "palette $name"
    return 0
  fi
  for ((i = 0; i < 50; i++)); do
    if [[ $(current_palette) == "$name" ]]; then
      apply_wallpaper
      return 0
    fi
    sleep 0.1
  done
  die "palette $name was not applied"
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
    until hyprctl clients -j | jq -e --arg c "$cls" 'any(.[]; .class == $c)' >/dev/null; do
      ((SECONDS < deadline)) || die "window $cls did not appear"
      sleep 0.5
    done
  done
}

wait_browser_loaded() {
  ((DRY)) && return 0
  local i
  for ((i = 0; i < 40; i++)); do
    hyprctl clients -j | jq -e '[.[] | select(.class == "firefox") | .title] | length > 0 and all(.[]; test("GitHub"))' >/dev/null && return 0
    sleep 0.5
  done
}

agent_pane() { tmux list-panes -t =agent -F '#{pane_id}' 2>/dev/null | head -n 1 || true; }

agent_state() {
  local pane
  pane=$(agent_pane)
  [[ -n $pane ]] || return 0
  "$HOME/.local/bin/keeptabs-pick" --json 2>/dev/null | jq -r --arg p "$pane" '[.[] | select(.tmux_pane == $p)][0].state // empty'
}

# Rows above the agent in the keeptabs popup, so `j` can walk the cursor to it.
agent_row() {
  local pane
  pane=$(agent_pane)
  if [[ -z $pane ]]; then
    printf '0'
    return 0
  fi
  "$HOME/.local/bin/keeptabs-pick" --json 2>/dev/null | jq -r --arg p "$pane" '[.[].tmux_pane] | index($p) // 0'
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

audio_source() {
  case $DEMO_AUDIO in
  none) ;;
  default) printf '%s.monitor' "$(pactl get-default-sink)" ;;
  *) printf '%s' "$DEMO_AUDIO" ;;
  esac
}

preflight() {
  local t lock busy tools=(hyprctl jq wtype qs tmux awk grim python3)
  [[ ${1:-} == record ]] && tools+=(wf-recorder ffmpeg ffprobe)
  [[ ${1:-} == record && $DEMO_AUDIO == default ]] && tools+=(pactl)
  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null || die "missing tool: $t"
  done
  [[ -x $qs_ipc_bin ]] || die "missing $qs_ipc_bin"
  hyprctl monitors -j | jq -e --arg o "$DEMO_OUTPUT" 'any(.[]; .name == $o)' >/dev/null || die "output $DEMO_OUTPUT not found"
  lock=$(qs_query call lock state)
  [[ $lock == unlocked ]] || die "lock state is '${lock:-unknown}'; unlock first"
  ! on_battery || die "on battery: style transitions and the keeptabs pulse are skipped, plug in"
  [[ -n $protect_addrs ]] || die "no protected terminal window resolved (set DEMO_PROTECT_PID or DEMO_PROTECT_ADDR)"
  if hyprctl clients -j | jq -e --argjson m "$(out_id)" --arg prot "$protect_addrs" '($prot | split(" ")) as $p | any(.[]; .monitor == $m and (.address | IN($p[])))' >/dev/null; then
    die "the protected terminal is on $DEMO_OUTPUT; move it to another output first"
  fi
  busy=$(hyprctl clients -j | jq -r --argjson m "$(out_id)" '[.[] | select(.monitor == $m and .workspace.id > 0) | .class] | join(", ")')
  [[ -z $busy ]] || die "$DEMO_OUTPUT must start empty; close or move: $busy"
}

dnd_on() { [[ $(qs_query call notifications get_dnd) == true ]]; }

save_state() {
  ((DRY)) && return 0
  mkdir -p "$state_dir"
  [[ -f $state_dir/saved.json ]] && return 0
  local dnd=false
  dnd_on && dnd=true
  jq -n --arg style "$(qs_query call style get)" --arg palette "$(current_palette)" \
    --arg sync "$(cat "$hypr_state_dir/nvim_sync" 2>/dev/null || echo off)" --argjson dnd "$dnd" \
    --arg pack "$(qs_query call style get_effects_pack)" \
    '{style: $style, palette: $palette, sync: $sync, dnd: $dnd, pack: $pack}' >"$state_dir/saved.json"
}

# NotificationsIpc only toggles, so compare with the current state first.
set_dnd() {
  if ((DRY)); then
    emit dnd "$1"
    return 0
  fi
  if { [[ $1 == true ]] && ! dnd_on; } || { [[ $1 == false ]] && dnd_on; }; then
    qs_ipc call notifications toggle_dnd >/dev/null
  fi
}

# Sync Neovim and the palette both apply through the switcher, which reloads Hyprland and reruns the generators.
apply_theme() {
  local palette=$1 sync=$2
  if ((DRY)); then
    emit theme "palette $palette, Sync Neovim $sync"
    return 0
  fi
  printf '%s\n' "$sync" >"$hypr_state_dir/nvim_sync"
  "$HOME/.config/hypr/theme/switch.lua" --set "$palette"
  wait_palette "$palette"
  sleep 1
}

rotator_pid() { pgrep -f 'hypr/extensions/wallpaper/init.lua' | head -n 1 || true; }

# The rotator would swap images mid-take (and a palette reload can make it), so it is paused with SIGSTOP and one
# image is set on the output; `restore` resumes it.
pin_wallpaper() {
  if ((DRY)); then
    emit wallpaper "pause the rotator, pin ${DEMO_WALLPAPER:-the current image} on $DEMO_OUTPUT"
    return 0
  fi
  local pid image
  pid=$(rotator_pid)
  if [[ -n $pid ]]; then
    kill -STOP "$pid"
    printf '%s\n' "$pid" >"$state_dir/rotator_paused"
  fi
  image=${DEMO_WALLPAPER:-$(hyprctl hyprpaper listactive 2>/dev/null | awk -v o="$DEMO_OUTPUT: " 'index($0, o) == 1 { print substr($0, length(o) + 1) }')}
  [[ -n $image ]] || return 0
  printf '%s\n' "$image" >"$state_dir/wallpaper"
  apply_wallpaper
}

apply_wallpaper() {
  [[ -f $state_dir/wallpaper ]] || return 0
  hyprctl hyprpaper wallpaper "$DEMO_OUTPUT, $(<"$state_dir/wallpaper")" >/dev/null 2>&1 || true
}

unpin_wallpaper() {
  if [[ -f $state_dir/rotator_paused ]]; then
    kill -CONT "$(<"$state_dir/rotator_paused")" 2>/dev/null || true
    rm -f "$state_dir/rotator_paused"
  fi
  rm -f "$state_dir/wallpaper"
}

stage_weather() {
  if ((DRY)); then
    emit weather "write {location_name: $DEMO_LOCATION} to $DEMO_WEATHER_FILE"
    return 0
  fi
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

# The loupe's zoom persists between opens; walk it down so the region beat starts from the same step.
reset_region_zoom() {
  qs_ipc call screenshot select false toolbar
  wait_layer quickshell-region
  pause 1
  send_token o
  send_token o
  send_token o
  send_token o
  send_token q
  wait_layer_gone quickshell-region
}

stage() {
  restore_on_exit=1
  validate_config
  ((DRY)) || preflight "${1:-}"
  save_state
  stage_weather
  set_dnd true
  # Each style's own sounds, whatever pack the owner normally uses.
  qs_ipc call style set_effects_pack "" >/dev/null
  apply_theme oasis_moonlight on
  qs_ipc call style set "$DEMO_START_STYLE"
  wait_style "$DEMO_START_STYLE"
  go_slot 1
  pin_wallpaper
  reset_region_zoom
  ensure_overlay
  ((DRY)) || : >"$state_dir/staged"
  # A standalone stage stays up for rehearsal; only `record` restores it.
  [[ ${1:-} == record ]] || restore_on_exit=0
}

restore_ui() {
  hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))' >/dev/null 2>&1 || true
  local call
  for call in "popup close" "overview close" "tmux-overview close" "picker close" "lock preview_close" "screenshot close"; do
    # shellcheck disable=SC2086 # each entry is a target and a function, split on purpose
    "$qs_ipc_bin" call $call >/dev/null 2>&1 || true
  done
  overlay_ipc card false 2>/dev/null || true
  overlay_ipc clear 2>/dev/null || true
}

# wf-recorder finishes its file on SIGINT, but ignores it once its output is gone (a dock reset mid-take), and an
# unbounded wait then hangs the exit handler before it restores anything.
stop_recorder() {
  [[ -n $recorder_pid ]] || return 0
  local i
  safe_kill INT "$recorder_pid"
  for ((i = 0; i < 50; i++)); do
    kill -0 "$recorder_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$recorder_pid" 2>/dev/null; then
    log "showcase: wf-recorder ignored SIGINT; terminating it"
    safe_kill TERM "$recorder_pid"
    sleep 1
    kill -0 "$recorder_pid" 2>/dev/null && safe_kill KILL "$recorder_pid"
  fi
  wait "$recorder_pid" 2>/dev/null || true
  recorder_pid=""
}

# Puts back the owner's style, palette, Sync Neovim and DND. The palette switch reloads Hyprland, which also
# undoes the `:layout` beat.
restore() {
  if ((DRY)); then
    emit restore "close surfaces, saved style/palette/sync/DND, weather, reload Hyprland, stop overlay"
    return 0
  fi
  stop_recorder
  restore_ui
  restore_weather
  if [[ -f $state_dir/saved.json ]]; then
    local style palette sync dnd
    style=$(jq -r .style "$state_dir/saved.json")
    palette=$(jq -r .palette "$state_dir/saved.json")
    sync=$(jq -r .sync "$state_dir/saved.json")
    dnd=$(jq -r .dnd "$state_dir/saved.json")
    "$qs_ipc_bin" call style set_effects_pack "$(jq -r '.pack // ""' "$state_dir/saved.json")" >/dev/null 2>&1 || true
    [[ -z $style ]] || "$qs_ipc_bin" call style set "$style" >/dev/null 2>&1 || true
    set_dnd "$dnd"
    if [[ -n $palette ]]; then apply_theme "$palette" "$sync"; else hyprctl reload >/dev/null; fi
    rm -f "$state_dir/saved.json"
  else
    hyprctl reload >/dev/null
  fi
  stop_overlay
  unpin_wallpaper
  rm -f "$state_dir/staged"
  restore_on_exit=0
}

cleanup() {
  local status=$?
  trap - EXIT
  if ((! DRY)); then
    if ((restore_on_exit)); then
      restore
    else
      stop_recorder
      restore_ui
    fi
  fi
  exit "$status"
}

### reset ###

# Ends the stage sessions (their kitty windows close with them) and closes the repo page the Demo session opened.
reset_stage() {
  if ((DRY)); then
    emit reset "kill the stage's tmux sessions, close firefox windows on $DEMO_OUTPUT"
    return 0
  fi
  "$stage_tmux" kill
  sleep 1
  local addr
  for addr in $(hyprctl clients -j | jq -r --argjson m "$(out_id)" --arg prot "$protect_addrs" '
    ($prot | split(" ")) as $p | .[] | select(.monitor == $m and .class == "firefox" and (.address | IN($p[]) | not)) | .address'); do
    hyprctl eval "hl.dispatch(hl.dsp.window.close({ window = \"address:$addr\" }))" >/dev/null
  done
}

### beats ###
# A beat may have pre_<beat> and post_<beat>, which run off camera around its clip.

pre_unlock() {
  go_slot 1
  expect_ns=quickshell-lock-preview
  if ! ((DRY)) && layer_open quickshell-lock-preview; then return 0; fi
  qs_ipc call lock preview mgs2
  wait_layer quickshell-lock-preview 10
}

# MGS2: title, LOAD GAME (the default), the user's DATA LOAD row, then the password. Every animation plays out.
beat_unlock() {
  local i
  pause "$T_LOGIN_INTRO"
  press "ENTER" @Return
  pause "$T_LOGIN_TITLE_TURN"
  press "ENTER" @Return
  pause "$T_LOGIN_PAGE_TURN"
  press "ENTER" @Return
  pause "$T_LOGIN_PAGE_TURN"
  for ((i = 0; i < ${#DEMO_PASSWORD}; i++)); do
    send "${DEMO_PASSWORD:i:1}"
    overlay_mask $((i + 1))
    pause "$T_LOGIN_CHAR_GAP"
  done
  pause "$T_LOGIN_HOLD"
  # Shift+Enter is the preview's stand-in for a correct password.
  press "ENTER" +@Return
  pause "$T_LOGIN_UNLOCK"
  qs_ipc call lock preview_close
  wait_layer_gone quickshell-lock-preview 5
  pause "$T_EMPTY_HOLD"
}

# The picker opens on the focused monitor; the unlock beat leaves focus there, a standalone rehearsal may not.
pre_session() { go_slot 1; }

beat_session() {
  bind "SUPER + SHIFT + O" 'require("extensions.auto_launcher.launcher").show_picker()'
  wait_layer quickshell-popup
  type_text "$DEMO_SESSION_QUERY"
  pause "$T_SETTINGS_HOLD"
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  fast_begin
  wait_clients "$T_SESSION_TIMEOUT" "${stage_classes[@]}"
  wait_browser_loaded
  pause 1.5
  fast_end
  pause "$T_SESSION_HOLD"
}

pre_resize() { focus_class kitty-tmux-dotfiles; }

# SUPER+R's Resize submap and its which-key, widening the editor. wtype would drop Hyprland out of the submap, so
# each step runs the bind's own resize under its key caption.
beat_resize() {
  local i
  bind "SUPER + R" 'hl.dispatch(hl.dsp.submap("Resize"))'
  wait_layer quickshell-whichkey
  pause "$T_RESIZE_HOLD"
  for ((i = 0; i < 3; i++)); do
    bind "SHIFT + L" 'hl.dispatch(hl.dsp.window.resize({ x = 100, y = 0, relative = true }))'
    pause "$T_RESIZE_STEP"
  done
  bind "ESC" 'hl.dispatch(hl.dsp.submap("reset"))'
  wait_layer_gone quickshell-whichkey
  pause "$T_RESIZE_HOLD"
}

# Settings > Colors: Enter opens the palette list, typing filters it, Enter applies (and reloads Hyprland).
beat_palettes() {
  local name
  leader_chord S qs_ipc call popup open settings
  wait_layer quickshell-popup
  pause "$T_SETTINGS_HOLD"
  press "2" 2
  press "ENTER" @Return
  pause "$T_SETTINGS_HOLD"
  for name in $DEMO_PALETTES; do
    press "ENTER" @Return
    type_text "$name"
    press "ENTER" @Return
    wait_palette "oasis_$name"
    pause "$T_PALETTE_HOLD"
  done
}

# Rehearsed alone, the turn needs Settings open in the Colors pane, where the palettes beat leaves it.
pre_turn() {
  if ((DRY)) || layer_open quickshell-popup; then return 0; fi
  # Opening on a section already focuses its pane, which is where the palettes beat leaves Settings.
  qs_ipc call settings open colors
  wait_layer quickshell-popup
}

beat_turn() {
  press "ESC" @Escape
  press "1" 1
  press "ENTER" @Return
  press "ENTER" @Return
  type_text psx
  press "ENTER" @Return
  wait_style ps1
  pause "$T_TURN_HOLD"
}

post_turn() { qs_ipc call popup close; }

# Firefox leaves for slot 3 (focus follows it), then an empty slot 4 gives the styles beat a bare desktop: the bar
# and popups are the whole picture.
pre_move() { focus_class firefox; }

beat_move() {
  bind "SUPER + SHIFT + 3" 'require("lib.actions.workspace").move_local(3)()'
  pause "$T_MOVE_HOLD"
  bind "SUPER + 4" 'require("lib.actions.workspace").focus_local(4)()'
  pause "$T_MOVE_HOLD"
}

# Switch one style from Settings > Style: Enter opens the list, typing filters it, Enter applies.
switch_style() {
  local id=$1 query=$2
  leader_chord S qs_ipc call settings open style
  wait_layer quickshell-popup
  press "ENTER" @Return
  type_text "$query"
  press "ENTER" @Return
  wait_style "$id"
  pause "$T_STYLE_HOLD"
  press "Q" q
  wait_layer_gone quickshell-popup
}

show_volume() {
  bind "SUPER + ALT + K" 'require("lib.actions.media").volume_up()()'
  pause "$T_SURFACE_HOLD"
  # Back down off screen, so the take ends at the owner's volume.
  hypr_eval 'require("lib.actions.media").volume_down()()'
}

show_calendar() {
  leader_chord C qs_ipc call popup open clock
  wait_layer quickshell-popup
  pause "$T_SURFACE_HOLD"
  press "Q" q
  wait_layer_gone quickshell-popup
}

# One continuous clip on the bare desktop: each style is switched in Settings, then the volume OSD and the
# calendar show what it changes, with the style's own sounds.
beat_styles() {
  local pair
  for pair in $DEMO_STYLES; do
    switch_style "${pair%%:*}" "${pair#*:}"
    show_volume
    show_calendar
  done
}

pre_kickoff() { focus_class kitty-tmux-agent; }

# Starts the agent's task; it runs while the next beats play, and keeptabs reports it done at the end.
beat_kickoff() {
  assert_active_class kitty-tmux-agent
  send -d 40 "$DEMO_AGENT_PROMPT"
  press "ENTER" @Return
  pause "$T_KICKOFF_HOLD"
}

beat_overview() {
  ipc "SUPER + TAB" call overview open
  wait_layer quickshell-overview
  pause "$T_OVERVIEW_STEP"
  press "CTRL + L" ^l
  pause "$T_OVERVIEW_STEP"
  press "CTRL + H" ^h
  pause "$T_OVERVIEW_STEP"
  press "L" l
  pause "$T_OVERVIEW_STEP"
  press "/" /
  type_text "$DEMO_SEARCH_TEXT"
  pause "$T_SEARCH_HOLD"
  press "ENTER" @Return
  wait_layer_gone quickshell-overview
  assert_active_class kitty-tmux-dotfiles
}

# HyprVim's `:` prompt, drawn by Quickshell: Enter on `layout` takes the command and lists its layouts, then
# scrolling re-tiles the workspace live.
# Slot 5 holds three windows from the Demo session; two half-width columns would look the same in scrolling as in
# the split layout, three overflow and scroll.
beat_prompt() {
  bind "SUPER + 5" 'require("lib.actions.workspace").focus_local(5)()'
  pause "$T_MOVE_HOLD"
  overlay_keys ":"
  pause "$T_LEAD"
  hypr_eval 'require("hyprvim.vim").command.prompt()'
  wait_layer quickshell-popup
  type_text "layout"
  press "ENTER" @Return
  pause "$T_PROMPT_HOLD"
  type_text "scrolling"
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  pause "$T_LAYOUT_HOLD"
}

# The dashboard logo's rectangle on the output, monitor-local "x y w h", found off camera from a screenshot:
# the first block of non-background rows in the Neovim pane. DEMO_REGION_RECT ("x y w h") overrides it.
logo_rect() {
  if [[ -n ${DEMO_REGION_RECT:-} ]]; then
    printf '%s\n' "$DEMO_REGION_RECT"
    return 0
  fi
  local shot=$state_dir/region-detect.png win pane
  mkdir -p "$state_dir"
  grim -o "$DEMO_OUTPUT" "$shot"
  win=$(hyprctl clients -j | jq -r --argjson m "$(out_id)" --argjson mx "$(hyprctl monitors -j | jq --arg o "$DEMO_OUTPUT" '.[] | select(.name == $o) | .x')" --argjson my "$(hyprctl monitors -j | jq --arg o "$DEMO_OUTPUT" '.[] | select(.name == $o) | .y')" \
    '[.[] | select(.class == "kitty-tmux-dotfiles" and .monitor == $m)][0] | "\(.at[0] - $mx) \(.at[1] - $my) \(.size[0]) \(.size[1])"')
  [[ $win != "null" && -n $win ]] || die "no kitty-tmux-dotfiles window on $DEMO_OUTPUT"
  # Neovim is the left pane; pane-base-index varies between tmux configs, so find it by position.
  pane=$(tmux list-panes -t =dotfiles:editor -F '#{pane_left} #{pane_width} #{window_width}' | awk '$1 == 0' | head -n 1)
  python3 - "$shot" "$win" "$pane" <<'PY'
import sys
from PIL import Image
shot, win, pane = sys.argv[1], [int(v) for v in sys.argv[2].split()], [int(v) for v in sys.argv[3].split()]
wx, wy, ww, wh = win
left, width, cols = pane
# The Neovim pane's columns of the window, inset past the tmux status rows and the window border.
x0 = wx + round(ww * left / cols) + 4
x1 = wx + round(ww * (left + width) / cols) - 4
y0, y1 = wy + round(wh * 0.06), wy + wh - round(wh * 0.06)
im = Image.open(shot).convert("RGB").crop((x0, y0, x1, y1))
px = im.load()
w, h = im.size
counts = {}
for y in range(0, h, 4):
    for x in range(0, w, 4):
        counts[px[x, y]] = counts.get(px[x, y], 0) + 1
bg = max(counts, key=counts.get)
def busy(c):
    return sum(abs(a - b) for a, b in zip(c, bg)) > 40
rows = [any(busy(px[x, y]) for x in range(w)) for y in range(h)]
top = next((y for y in range(h) if rows[y]), None)
if top is None:
    sys.exit("no logo found in the Neovim pane")
# The logo ends at the first gap of more than 10 empty rows (the line before the dashboard's text).
bottom, gap = top, 0
for y in range(top, h):
    if rows[y]:
        bottom, gap = y, 0
    else:
        gap += 1
        if gap > 10:
            break
cols_busy = [x for x in range(w) if any(busy(px[x, y]) for y in range(top, bottom + 1))]
lx, rx = cols_busy[0], cols_busy[-1]
print(x0 + lx, y0 + top, rx - lx + 1, bottom - top + 1)
PY
}

# Key plan from the selector's start point to the logo: SHIFT steps of 100 px, plain 10, CTRL 1. Prints
# "label token count" lines: to the top-left corner, anchor, zoom, then to the bottom-right corner.
region_plan() {
  local rect=$1 start=$2
  python3 - "$rect" "$start" <<'PY'
import sys
x, y, w, h = [int(v) for v in sys.argv[1].split()]
cx, cy = [int(float(v)) for v in sys.argv[2].split()]
def steps(d, pos, neg):
    key = pos if d >= 0 else neg
    d = abs(d)
    out = []
    for size, mod, prefix in ((100, "SHIFT + ", "+"), (10, "", ""), (1, "CTRL + ", "^")):
        n, d = divmod(d, size)
        if n:
            out.append(f"{mod}{key.upper()}|{prefix}{key}|{n}")
    return out
plan = steps(x - cx, "l", "h") + steps(y - cy, "j", "k")
plan += ["V|v|1", "I|i|2"]
plan += steps(w - 1, "l", "h") + steps(h - 1, "j", "k")
print("\n".join(plan))
PY
}

# The selector starts at the pointer when it is on the output, else at the output's centre.
region_start() {
  hyprctl cursorpos -j | jq -r --argjson m "$(hyprctl monitors -j | jq -c --arg o "$DEMO_OUTPUT" '.[] | select(.name == $o)')" '
    if .x >= $m.x and .y >= $m.y and .x < $m.x + $m.width and .y < $m.y + $m.height
    then "\(.x - $m.x) \(.y - $m.y)" else "\($m.width / 2) \($m.height / 2)" end'
}

# Runs before the prompt beat: `:layout scrolling` narrows the editor and would crop the logo.
region_steps=()

pre_region() {
  focus_class kitty-tmux-dotfiles
  if ((DRY)); then
    region_steps=("SHIFT + H|+h|3" "V|v|1" "I|i|2" "SHIFT + L|+l|4" "CTRL + L|^l|3")
    return 0
  fi
  # Unfocused windows are translucent; wait out the fade so the screenshot shows the pane's own background.
  pause 1
  local rect
  rect=$(logo_rect) || die "could not find the dashboard logo; set DEMO_REGION_RECT=\"x y w h\""
  log "showcase: logo at $rect"
  mapfile -t region_steps < <(region_plan "$rect" "$(region_start)")
}

# Steer to the logo's top-left corner, anchor, zoom the loupe, extend to the bottom-right corner ending on
# single-pixel nudges, confirm, then copy for the toast.
beat_region() {
  local step label token count tokens
  # The plan runs to dozens of key presses; repeats of one key go quicker than the rest of the take.
  local T_KEY_GAP=$T_SHOT_KEY_GAP
  ipc "PRINT" call screenshot select false toolbar
  wait_layer quickshell-region
  pause 1
  for step in "${region_steps[@]}"; do
    IFS='|' read -r label token count <<<"$step"
    tokens=()
    while ((count-- > 0)); do tokens+=("$token"); done
    press "$label" "${tokens[@]}"
    pause "$T_SHOT_STEP"
  done
  pause 0.6
  press "SPACE" @space
  pause 0.6
  press "C" c
  wait_layer_gone quickshell-region
  pause "$T_TOAST_HOLD"
}

pre_keeptabs() {
  ((DRY)) && return 0
  local deadline=$((SECONDS + T_AGENT_TIMEOUT))
  until [[ $(agent_state) == "done" ]]; do
    ((SECONDS < deadline)) || die "the agent did not finish within ${T_AGENT_TIMEOUT}s"
    sleep 1
  done
}

beat_keeptabs() {
  local n=0
  pause "$T_PULSE_HOLD"
  ((DRY)) || n=$(agent_row)
  ipc "SUPER + CTRL + A" call popup open keeptabs
  wait_layer quickshell-popup
  pause "$T_KEEPTABS_HOLD"
  while ((n > 0)); do
    press "J" j
    pause 0.35
    n=$((n - 1))
  done
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  assert_active_class kitty-tmux-agent
  pause "$T_ANSWER_HOLD"
}

# Slot 2 holds the agent and slot 3 Firefox; the styles beat left slot 4 empty for the end card.
pre_outro() { go_slot 4; }

beat_outro() {
  pause 0.4
  overlay_card true
  pause "$T_OUTRO_HOLD"
}

post_outro() { overlay_card false; }

### recording ###

clip_path() { printf '%s/%02d-%s.mkv' "$1" "$2" "$3"; }

start_recorder() {
  local file=$1 source args=()
  source=$(audio_source)
  [[ -z $source ]] || args+=("--audio=$source")
  if ((DRY)); then
    emit record "wf-recorder -o $DEMO_OUTPUT -r $DEMO_FPS ${args[*]} -f $file"
    return 0
  fi
  rec_t0=$(date +%s.%N)
  fast_ranges=()
  wf-recorder -o "$DEMO_OUTPUT" -r "$DEMO_FPS" "${args[@]}" -f "$file" >/dev/null 2>&1 &
  recorder_pid=$!
  sleep 0.6
  kill -0 "$recorder_pid" 2>/dev/null || die "wf-recorder failed to start"
}

run_hook() { if declare -F "$1" >/dev/null; then "$1"; fi; }

# Rehearses one beat without the recorder.
run_beat() {
  local name=$1
  declare -F "beat_$name" >/dev/null || die "unknown beat '$name' (try: list)"
  printf '== beat %s\n' "$name"
  run_hook "pre_$name"
  "beat_$name"
  run_hook "post_$name"
}

record_beat() {
  local dir=$1 index=$2 name=$3 file
  file=$(clip_path "$dir" "$index" "$name")
  printf '== record %s -> %s\n' "$name" "$file"
  run_hook "pre_$name"
  start_recorder "$file"
  "beat_$name"
  pause "$T_CLIP_TAIL"
  stop_recorder
  if ! ((DRY)) && ((${#fast_ranges[@]})); then printf '%s\n' "${fast_ranges[@]}" >"$file.fast"; fi
  fast_ranges=()
  rec_t0=""
  run_hook "post_$name"
}

record() {
  local dir i
  dir=$DEMO_OUT_DIR/showcase-$(date +%Y-%m-%d_%Hh%Mm%Ss)
  ((DRY)) || mkdir -p "$dir"
  stage record
  for i in "${!beats[@]}"; do
    record_beat "$dir" "$i" "${beats[i]}"
  done
  restore
  edit "$dir"
}

# One clip to a normalised mp4: its fast ranges sped up with silence over them, the rest at normal speed with
# its own audio, and a stereo track always present, so the concat step can join the clips without re-encoding.
normalise_clip() {
  local raw=$1 out=$2 filter="" pairs="" prev=0 n=0 r from to has_audio=0 a_out=""
  local -a ranges=()
  if [[ -s $raw.fast ]]; then mapfile -t ranges <"$raw.fast"; fi
  if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$raw" | grep -q .; then has_audio=1; fi
  segment() {
    local from=$1 to=$2 fast=$3 trim atrim
    if [[ -n $to ]]; then
      trim="trim=$from:$to"
      atrim="atrim=$from:$to"
    else
      trim="trim=start=$from"
      atrim="atrim=start=$from"
    fi
    if ((fast)); then
      local factor
      factor=$(awk -v a="$from" -v b="$to" -v f="$DEMO_FAST" -v m="$DEMO_FAST_MAX" 'BEGIN { x = (b - a) / m; printf "%.3f", (x > f ? x : f) }')
      filter+="[0:v]$trim,setpts=(PTS-STARTPTS)/${factor}[v$n];"
      ((has_audio)) && filter+="aevalsrc=0:c=stereo:s=48000:d=$(awk -v a="$from" -v b="$to" -v f="$factor" 'BEGIN { printf "%.3f", (b - a) / f }')[a$n];"
    else
      filter+="[0:v]$trim,setpts=PTS-STARTPTS[v$n];"
      ((has_audio)) && filter+="[0:a]$atrim,asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo[a$n];"
    fi
    pairs+="[v$n]"
    ((has_audio)) && pairs+="[a$n]"
    n=$((n + 1))
  }
  for r in "${ranges[@]}"; do
    [[ -n $r ]] || continue
    read -r from to <<<"$r"
    segment "$prev" "$from" 0
    segment "$from" "$to" 1
    prev=$to
  done
  segment "$prev" "" 0
  if ((has_audio)); then
    filter+="${pairs}concat=n=$n:v=1:a=1[vc][a];[vc]fps=${DEMO_FPS},format=yuv420p[v]"
    a_out="[a]"
    ffmpeg -y -loglevel error -i "$raw" -filter_complex "$filter" -map "[v]" -map "$a_out" \
      -c:v libx264 -preset slow -crf 18 -c:a aac -b:a 192k "$out"
  else
    filter+="${pairs}concat=n=$n:v=1[vc];[vc]fps=${DEMO_FPS},format=yuv420p[v]"
    ffmpeg -y -loglevel error -i "$raw" -f lavfi -i anullsrc=r=48000:cl=stereo -filter_complex "$filter" \
      -map "[v]" -map 1:a -c:v libx264 -preset slow -crf 18 -c:a aac -b:a 192k -shortest "$out"
  fi
}

# Joins a recording folder's clips, in beat order, into showcase.mp4 beside them.
edit() {
  local dir=${1:?usage: showcase.sh edit <recording dir>} raw cut list
  if ((DRY)); then
    emit edit "normalise each clip in $dir, concat to $dir/showcase.mp4"
    return 0
  fi
  [[ -d $dir ]] || die "no such recording dir: $dir"
  mkdir -p "$dir/cut"
  list=$dir/cut/list.txt
  : >"$list"
  for raw in "$dir"/[0-9][0-9]-*.mkv; do
    cut=$dir/cut/$(basename "${raw%.mkv}").mp4
    normalise_clip "$raw" "$cut"
    printf "file '%s'\n" "$cut" >>"$list"
  done
  # The UI sounds and lock music arrive quiet (both play at 0.7, music is normalised to -18 LUFS); lift the
  # whole track to a normal listening level.
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -c:v copy -af loudnorm=I=-16:TP=-1.5:LRA=11 \
    -c:a aac -b:a 192k -movflags +faststart "$dir/showcase.mp4"
  log "showcase: wrote $dir/showcase.mp4"
}

# The README hero: the palette, turn and montage cuts as a looping animated WebP.
hero() {
  local dir=${1:?usage: showcase.sh hero <recording dir>} name list clip
  if ((DRY)); then
    emit hero "${hero_beats[*]} from $dir/cut -> $dir/hero.webp"
    return 0
  fi
  [[ -d $dir/cut ]] || die "run edit first: no $dir/cut"
  list=$dir/cut/hero.txt
  : >"$list"
  for name in "${hero_beats[@]}"; do
    clip=$(compgen -G "$dir/cut/[0-9][0-9]-$name.mp4" | head -n 1 || true)
    [[ -n $clip ]] || die "missing clip for $name"
    printf "file '%s'\n" "$clip" >>"$list"
  done
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -an -vf "fps=12,scale=1000:-1:flags=lanczos" \
    -c:v libwebp -quality 45 -compression_level 6 -loop 0 "$dir/hero.webp"
  log "showcase: wrote $dir/hero.webp"
}

usage() {
  cat <<EOF
usage: showcase.sh [--dry-run] <command>

  stage            prepare $DEMO_OUTPUT: weather, DND, Moonlight with Sync Neovim, $DEMO_START_STYLE style, overlay
  beat <name>      rehearse one beat (with its off-camera setup); see: list
  all              rehearse every beat in order, no recording
  record           stage, film one clip per beat, restore, then edit
  edit <dir>       cut a recording folder's clips into showcase.mp4
  hero <dir>       cut the README hero from an edited recording folder
  restore          undo stage: style, palette, Sync Neovim, DND, weather, layout
  reset            end the Demo session's tmux sessions and close its windows
  list             print beat names
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
    printf '%s\n' "${beats[@]}"
    return 0
    ;;
  "" | -h | --help | help)
    usage
    return 0
    ;;
  edit)
    edit "${args[1]:-}"
    return 0
    ;;
  hero)
    hero "${args[1]:-}"
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
  beat)
    [[ -n ${args[1]:-} ]] || die "usage: showcase.sh beat <name>"
    validate_config
    ensure_overlay
    run_beat "${args[1]}"
    ;;
  all)
    validate_config
    ensure_overlay
    for a in "${beats[@]}"; do
      run_beat "$a"
    done
    ;;
  record) record ;;
  restore) restore ;;
  reset) reset_stage ;;
  *)
    usage
    return 1
    ;;
  esac
}

main "$@"
