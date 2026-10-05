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
qs_state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/quickshell
state_dir=${XDG_RUNTIME_DIR:-/tmp}/oasis-demo

DEMO_OUTPUT=${DEMO_OUTPUT:-DP-8}
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
DEMO_PROTECT_PID=${DEMO_PROTECT_PID:-${KITTY_PID:-}}
DEMO_WEATHER_FILE=${DEMO_WEATHER_FILE:-$HOME/.config/quickshell/weather.local.json}
DEMO_FAST=${DEMO_FAST:-5}

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
T_EMPTY_HOLD=${T_EMPTY_HOLD:-2.0}
T_SESSION_TIMEOUT=${T_SESSION_TIMEOUT:-60}
T_SESSION_HOLD=${T_SESSION_HOLD:-1.5}
T_SETTINGS_HOLD=${T_SETTINGS_HOLD:-0.6}
T_PALETTE_HOLD=${T_PALETTE_HOLD:-1.2}
T_TURN_HOLD=${T_TURN_HOLD:-1.5}
T_MONTAGE_HOLD=${T_MONTAGE_HOLD:-1.8}
T_KICKOFF_HOLD=${T_KICKOFF_HOLD:-1.0}
T_OVERVIEW_STEP=${T_OVERVIEW_STEP:-0.6}
T_SEARCH_HOLD=${T_SEARCH_HOLD:-1.0}
T_PROMPT_HOLD=${T_PROMPT_HOLD:-1.4}
T_LAYOUT_HOLD=${T_LAYOUT_HOLD:-2.0}
T_SHOT_STEP=${T_SHOT_STEP:-0.18}
T_TOAST_HOLD=${T_TOAST_HOLD:-1.8}
T_AGENT_TIMEOUT=${T_AGENT_TIMEOUT:-180}
T_PULSE_HOLD=${T_PULSE_HOLD:-2.0}
T_KEEPTABS_HOLD=${T_KEEPTABS_HOLD:-1.2}
T_ANSWER_HOLD=${T_ANSWER_HOLD:-3.0}
T_OUTRO_HOLD=${T_OUTRO_HOLD:-4.5}

beats=(unlock session palettes turn
  montage_ps1 montage_ff7 montage_goldeneye montage_gameboy montage_metroid montage_tie montage_back
  kickoff overview prompt region keeptabs outro)
# The README hero is cut from these.
hero_beats=(palettes turn montage_ps1 montage_ff7 montage_goldeneye montage_gameboy montage_metroid montage_tie montage_back)
stage_classes=(kitty-tmux-dotfiles firefox kitty-tmux-agent)
declare -A style_reveal_ms=([neovim]=400 [ps1]=500 [ff7]=500 [goldeneye]=500 [gameboy]=500 [metroid]=500 [tie]=500)

DRY=0
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

# kitty shares one pid across its windows, so the demo terminals (kitty-tmux-*) are told apart by address.
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

class_addr() { hyprctl clients -j | jq -r --arg c "$1" '[.[] | select(.class == $c)][0].address // empty'; }

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
    [[ $(current_palette) == "$name" ]] && return 0
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
  local t lock busy tools=(hyprctl jq wtype qs tmux awk)
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

dnd_on() { jq -e '.dnd == true' "$qs_state_dir/notifications.json" >/dev/null 2>&1; }

save_state() {
  ((DRY)) && return 0
  mkdir -p "$state_dir"
  [[ -f $state_dir/saved.json ]] && return 0
  local dnd=false
  dnd_on && dnd=true
  jq -n --arg style "$(qs_query call style get)" --arg palette "$(current_palette)" \
    --arg sync "$(cat "$hypr_state_dir/nvim_sync" 2>/dev/null || echo off)" --argjson dnd "$dnd" \
    '{style: $style, palette: $palette, sync: $sync, dnd: $dnd}' >"$state_dir/saved.json"
}

# NotificationsIpc only toggles, so compare with the saved state first.
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
  validate_config
  ((DRY)) || preflight "${1:-}"
  save_state
  stage_weather
  set_dnd true
  apply_theme oasis_moonlight on
  qs_ipc call style set "$DEMO_START_STYLE"
  wait_style "$DEMO_START_STYLE"
  go_slot 1
  reset_region_zoom
  ensure_overlay
  ((DRY)) || : >"$state_dir/staged"
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

stop_recorder() {
  [[ -n $recorder_pid ]] || return 0
  safe_kill INT "$recorder_pid"
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
    [[ -z $style ]] || "$qs_ipc_bin" call style set "$style" >/dev/null 2>&1 || true
    set_dnd "$dnd"
    if [[ -n $palette ]]; then apply_theme "$palette" "$sync"; else hyprctl reload >/dev/null; fi
    rm -f "$state_dir/saved.json"
  else
    hyprctl reload >/dev/null
  fi
  stop_overlay
  rm -f "$state_dir/staged"
}

cleanup() {
  local status=$?
  trap - EXIT
  if ((! DRY)); then
    stop_recorder
    restore_ui
  fi
  exit "$status"
}

### reset ###

# Ends the stage sessions (their kitty windows close with them) and closes the repo page the Demo session opened.
reset_stage() {
  if ((DRY)); then
    emit reset "kill tmux sessions dotfiles and agent, close firefox windows on $DEMO_OUTPUT"
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

# One montage cut: the style is set off camera, then the clip shows its caption and one signature surface.
montage_pre() {
  qs_ipc call style set "$1"
  wait_style "$1"
}

montage_caption() {
  overlay_keys "$1"
  pause 0.5
}

beat_montage_ps1() {
  montage_caption "PSX"
  ipc "SUPER + TAB" call overview open
  wait_layer quickshell-overview
  pause "$T_MONTAGE_HOLD"
}
post_montage_ps1() { qs_ipc call overview close; }

pre_montage_ff7() { montage_pre ff7; }
beat_montage_ff7() {
  montage_caption "FFVII"
  leader_chord W qs_ipc call popup open weather
  wait_layer quickshell-popup
  pause "$T_MONTAGE_HOLD"
}
post_montage_ff7() { qs_ipc call popup close; }

pre_montage_goldeneye() { montage_pre goldeneye; }
beat_montage_goldeneye() {
  montage_caption "GOLDENEYE"
  leader_chord C qs_ipc call popup open clock
  wait_layer quickshell-popup
  pause "$T_MONTAGE_HOLD"
}
post_montage_goldeneye() { qs_ipc call popup close; }

pre_montage_gameboy() { montage_pre gameboy; }
beat_montage_gameboy() {
  montage_caption "GAME BOY"
  leader_chord C qs_ipc call popup open clock
  wait_layer quickshell-popup
  pause "$T_MONTAGE_HOLD"
}
post_montage_gameboy() { qs_ipc call popup close; }

pre_montage_metroid() { montage_pre metroid; }
beat_montage_metroid() {
  montage_caption "METROID"
  bind "SUPER + ALT + K" 'require("lib.actions.media").volume_up()()'
  pause "$T_MONTAGE_HOLD"
}
post_montage_metroid() { hypr_eval 'require("lib.actions.media").volume_down()()'; }

pre_montage_tie() { montage_pre tie; }
beat_montage_tie() {
  montage_caption "TIE FIGHTER"
  overlay_keys "SUPER + SPACE"
  pause "$T_LEAD"
  hypr_eval 'hl.dispatch(hl.dsp.submap("Leader"))'
  wait_layer quickshell-whichkey
  pause "$T_MONTAGE_HOLD"
}
post_montage_tie() { hypr_eval 'hl.dispatch(hl.dsp.submap("reset"))'; }

beat_montage_back() {
  montage_caption "PSX"
  qs_ipc call style set ps1
  wait_style ps1
  pause 0.8
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

# HyprVim's `:` prompt, drawn by Quickshell: complete `layout`, pick scrolling, and the workspace re-tiles live.
beat_prompt() {
  overlay_keys ":"
  pause "$T_LEAD"
  hypr_eval 'require("hyprvim.vim").command.prompt()'
  wait_layer quickshell-popup
  type_text "layout "
  press "TAB" @Tab
  pause "$T_PROMPT_HOLD"
  type_text "scrolling"
  press "ENTER" @Return
  wait_layer_gone quickshell-popup
  pause "$T_LAYOUT_HOLD"
}

# Steer, anchor, extend, zoom in, nudge one pixel at a time, confirm, then copy for the toast.
beat_region() {
  local key
  ipc "PRINT" call screenshot select false toolbar
  wait_layer quickshell-region
  pause 1
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
  pause "$T_SHOT_STEP"
  press "I" i
  pause 0.6
  for key in l l l; do
    press "CTRL + L" "^$key"
    pause 0.35
  done
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

pre_outro() { go_slot 2; }

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

# One clip to a normalised mp4: its fast ranges sped up (their audio dropped) and a stereo track always present,
# so the concat step can join the clips without re-encoding.
normalise_clip() {
  local raw=$1 out=$2 filter="" labels="" prev=0 n=0 r from to has_audio=0
  local -a ranges=()
  if [[ -s $raw.fast ]]; then mapfile -t ranges <"$raw.fast"; fi
  if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$raw" | grep -q .; then has_audio=1; fi
  for r in "${ranges[@]}"; do
    [[ -n $r ]] || continue
    read -r from to <<<"$r"
    filter+="[0:v]trim=$prev:$from,setpts=PTS-STARTPTS[s$n];"
    filter+="[0:v]trim=$from:$to,setpts=(PTS-STARTPTS)/${DEMO_FAST}[s$((n + 1))];"
    labels+="[s$n][s$((n + 1))]"
    n=$((n + 2))
    prev=$to
  done
  filter+="[0:v]trim=start=$prev,setpts=PTS-STARTPTS[s$n];${labels}[s$n]concat=n=$((n + 1)):v=1,fps=${DEMO_FPS},format=yuv420p[v]"
  if ((has_audio && ${#ranges[@]} == 0)); then
    ffmpeg -y -loglevel error -i "$raw" -filter_complex "$filter;[0:a]aresample=48000,aformat=channel_layouts=stereo[a]" \
      -map "[v]" -map "[a]" -c:v libx264 -preset slow -crf 18 -c:a aac -b:a 192k -shortest "$out"
  else
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
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -c copy -movflags +faststart "$dir/showcase.mp4"
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
