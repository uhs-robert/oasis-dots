#!/usr/bin/env bash
# Runs a command with voxcmd cut off from the live desktop: its own runtime dir, a config dir holding this checkout's
# integrations and replacements, this checkout's voxcmd first on PATH, and stubs in place of everything that acts.
#
#   home/voxcmd/tests/sandbox.sh <command...>
#   home/voxcmd/tests/sandbox.sh voxcmd --dry-run "close firefox"
#   SANDBOX_SHOW_CALLS=1 home/voxcmd/tests/sandbox.sh voxcmd "close firefox"
#
# Stubs log each call and succeed, printing nothing or a plausible answer (wpctl get-volume, qs-ipc get_dnd,
# hyprctl dispatch's "ok"). Read-only queries still reach the real tool unless a fixture replaces them:
#
#   hyprctl binds|clients|monitors|activewindow|activeworkspace|version -j
#                                     SANDBOX_BINDS_JSON, SANDBOX_CLIENTS_JSON, ... (the JSON itself); activewindow
#                                     is {} (no focused window) without its fixture, never the live window
#   tesseract                         SANDBOX_TESSERACT_TSV (the tsv itself; no words without it)
#   grim, magick                      never real: grim writes a blank image the size of the activewindow fixture
#                                     times SANDBOX_GRIM_SCALE (default 1), or SANDBOX_GRIM_SIZE ("W H"), and fails
#                                     -T when SANDBOX_GRIM_NO_TOPLEVEL is set; magick cuts empty strips and reports
#                                     a light image (SANDBOX_IMAGE_MEAN, default 1)
#   pw-dump                           SANDBOX_PW_DUMP_JSON
#   keeptabs-pick --json              SANDBOX_AGENTS_JSON
#   systemctl list-timers|list-units  SANDBOX_TIMERS_JSON
#   tmux list-sessions|has-session    SANDBOX_TMUX_SESSIONS (one name per line)
#   qs-ipc call clickhints open|dismiss|state
#                                     the bar's numbered overlay. open logs a "clickhints-open" line holding the
#                                     pending-pick.json it finds and the spec file's JSON, then answers through the
#                                     spec's result FIFO as the bar would. state prints open between open and dismiss.
#                                       SANDBOX_CLICKHINTS_ANSWER  the line written to the FIFO (a number or a label;
#                                                                  empty is a cancel)
#                                       SANDBOX_CLICKHINTS_OPEN    what open prints, "ok" by default; anything else
#                                                                  is a bar that refused the overlay
#                                       SANDBOX_CLICKHINTS_HOLD=1  open prints ok and nobody answers, as a bar
#                                                                  waiting on the user does
#   voxcmd-pick, voxcmd-autostop      voxcmd finds these beside itself, not on PATH, so a test copies the package and
#                                     symlinks its two onto $SANDBOX_DIR/bin's. voxcmd-pick logs and "picks" the first
#                                     choice's id; voxcmd-autostop exits 1 (no verdict)
#   setsid                            logs "setsid owner=$VOXCMD_RECORDING_OWNER_FILE <args>" and starts nothing
#
# Hyprland's dispatch, eval and keyword are logged and never sent.
#
#   VOXCMD_EXTRA_INTEGRATIONS  colon-separated integration files to load too, e.g. a private one
#   SANDBOX_EXTRA_STUBS        space-separated commands to stub as well, such as the ones an extra integration calls
#   SANDBOX_SHOW_CALLS=1       print the stub call log to stderr when the command ends
#   SANDBOX_DIR                set for the command: the sandbox root, with the call log at $SANDBOX_DIR/calls.log
#
# HOME, XDG_STATE_HOME and XDG_CACHE_HOME are empty dirs in the sandbox, so the caller's tmuxifier layouts, timers
# and state never change a route.
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(dirname "$tests_dir")
[ "$#" -gt 0 ] || {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0" >&2
  exit 2
}

sandbox_dir=$(mktemp -d "${TMPDIR:-/tmp}/voxcmd-sandbox.XXXXXX")
trap 'rm -rf "$sandbox_dir"' EXIT
stub_dir="$sandbox_dir/bin"
config_home="$sandbox_dir/config"
mkdir -p "$stub_dir" "$config_home/voxcmd/integrations.d" "$config_home/voxcmd/replacements.d" \
  "$config_home/hypr/scripts" "$sandbox_dir/runtime" "$sandbox_dir/home"
chmod 700 "$sandbox_dir/runtime"
: >"$sandbox_dir/calls.log"

# Regular files only: a private dotfiles repo links its own integrations and replacements in here per file, and those
# would change the routes. VOXCMD_EXTRA_INTEGRATIONS loads one on purpose.
find "$package_dir"/.config/voxcmd/integrations.d -maxdepth 1 -type f -name '*.sh' -exec cp -t "$config_home/voxcmd/integrations.d/" {} +
find "$package_dir"/.config/voxcmd/replacements.d -maxdepth 1 -type f ! -name '.*' -exec cp -t "$config_home/voxcmd/replacements.d/" {} +
if [ -n "${VOXCMD_EXTRA_INTEGRATIONS:-}" ]; then
  IFS=: read -ra extra_integrations <<<"$VOXCMD_EXTRA_INTEGRATIONS"
  cp -L "${extra_integrations[@]}" "$config_home/voxcmd/integrations.d/"
fi

# One stub for every command, dispatched on the name it is called by. Passing through restores the real PATH and
# runtime dir, which Hyprland's and PipeWire's sockets live under, and the real HOME.
cat >"$stub_dir/.stub" <<'EOF'
#!/bin/sh
name=${0##*/}
log() { printf '%s\n' "$name $*" >>"$SANDBOX_DIR/calls.log"; }
pass_through() {
  PATH=$SANDBOX_REAL_PATH XDG_RUNTIME_DIR=$SANDBOX_REAL_XDG_RUNTIME_DIR HOME=$SANDBOX_REAL_HOME
  export PATH XDG_RUNTIME_DIR HOME
  command -v "$name" >/dev/null 2>&1 || exit 1
  exec "$name" "$@"
}
case "$name" in
hyprctl)
  case "${1-}" in
  activewindow) printenv SANDBOX_ACTIVEWINDOW_JSON || echo '{}' ;;
  binds | clients | monitors | activeworkspace | version)
    printenv "SANDBOX_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_JSON" || pass_through "$@"
    ;;
  dispatch | eval | keyword) log "$@" && echo ok ;;
  *) log "$@" ;;
  esac
  ;;
grim)
  log "$@"
  for out; do :; done
  # SANDBOX_GRIM_NO_TOPLEVEL fails the per-window capture (-T), as on a compositor without it.
  for arg; do [ "$arg" != -T ] || [ -z "${SANDBOX_GRIM_NO_TOPLEVEL-}" ] || exit 1; done
  scale=${SANDBOX_GRIM_SCALE:-1}
  size=${SANDBOX_GRIM_SIZE-}
  [ -n "$size" ] || size=$(printenv SANDBOX_ACTIVEWINDOW_JSON | jq -r --argjson scale "$scale" 'if .size then "\(.size[0] * $scale | round) \(.size[1] * $scale | round)" else empty end') || exit 1
  [ -n "$size" ] || exit 1
  set -- $size
  { printf 'P6\n%s %s\n255\n' "$1" "$2"; head -c $(($1 * $2 * 3)) /dev/zero; } >"$out"
  ;;
tesseract)
  # An image piped in is drained, so the inverting magick upstream never sees a broken pipe.
  [ "${1-}" != - ] || cat >/dev/null
  printenv SANDBOX_TESSERACT_TSV || :
  ;;
magick)
  # The strips are named by -write; the one -write to info:- is the mean luminance.
  previous=
  for arg; do
    if [ "$previous" = -write ]; then
      case "$arg" in
      info:-) echo "${SANDBOX_IMAGE_MEAN:-1}" ;;
      *) : >"$arg" ;;
      esac
    fi
    previous=$arg
  done
  ;;
pw-dump) printenv SANDBOX_PW_DUMP_JSON || pass_through "$@" ;;
keeptabs-pick)
  case "$*" in
  *--json*) printenv SANDBOX_AGENTS_JSON || pass_through "$@" ;;
  *) log "$@" ;;
  esac
  ;;
systemctl)
  case "$*" in
  *list-timers* | *list-units*) printenv SANDBOX_TIMERS_JSON || pass_through "$@" ;;
  *) log "$@" ;;
  esac
  ;;
tmux)
  case "${1-}" in
  list-sessions) printenv SANDBOX_TMUX_SESSIONS || pass_through "$@" ;;
  has-session)
    [ -n "${SANDBOX_TMUX_SESSIONS+set}" ] || pass_through "$@"
    eval "session=\${$#}"
    printf '%s\n' "$SANDBOX_TMUX_SESSIONS" | grep -qxF -- "${session#=}"
    ;;
  *) log "$@" ;;
  esac
  ;;
qs-ipc)
  log "$@"
  case "$*" in
  *get_dnd*) echo false ;;
  *"call clickhints open"*)
    if [ "${SANDBOX_CLICKHINTS_OPEN:-ok}" != ok ]; then
      echo "$SANDBOX_CLICKHINTS_OPEN"
      exit 0
    fi
    printf 'clickhints-open %s\n' "$(jq -c '{pending_kind: ., spec: input}' "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json" "$4")" >>"$SANDBOX_DIR/calls.log"
    : >"$SANDBOX_DIR/clickhints-open"
    if [ -z "${SANDBOX_CLICKHINTS_HOLD-}" ]; then
      fifo=$(jq -r .result_path "$4")
      (printf '%s\n' "${SANDBOX_CLICKHINTS_ANSWER-}" >"$fifo") >/dev/null 2>&1 &
    fi
    echo ok
    ;;
  *"call clickhints dismiss"*) rm -f "$SANDBOX_DIR/clickhints-open" ;;
  *"call clickhints state"*) if [ -e "$SANDBOX_DIR/clickhints-open" ]; then echo open; else echo closed; fi ;;
  *"confirm ask"* | *"sound play"*) echo ok ;;
  esac
  ;;
wpctl)
  log "$@"
  [ "${1-}" != get-volume ] || echo 'Volume: 0.50'
  ;;
pamixer)
  log "$@"
  case "$*" in
  *--get-volume*) echo 50 ;;
  *--get-mute*) echo false ;;
  esac
  ;;
brightnessctl)
  log "$@"
  [ "${1-}" != -m ] || echo 'sandbox,backlight,50,50%,100'
  ;;
voxcmd-pick)
  log "$@"
  for last; do :; done
  printf '%s\n' "$last" | jq -r '.[0].id'
  ;;
voxcmd-autostop) exit 1 ;;
setsid) log "owner=${VOXCMD_RECORDING_OWNER_FILE-} $*" ;;
powerprofilesctl)
  log "$@"
  case "${1-}" in
  list) printf '  performance:\n* balanced:\n  power-saver:\n' ;;
  get) echo balanced ;;
  esac
  ;;
*) log "$@" ;;
esac
EOF
chmod +x "$stub_dir/.stub"

# Called by name from PATH. hyprctl, pw-dump, keeptabs-pick, systemctl and tmux also answer read-only queries; grim,
# tesseract and magick answer from the fixtures above and never touch the screen.
stubbed_commands=(
  hyprctl pw-dump keeptabs-pick systemctl tmux
  systemd-run notify-send pamixer wpctl bluetoothctl playerctl brightnessctl powerprofilesctl
  grim tesseract magick wlrctl wl-kbptr wtype wl-copy voxtype wf-recorder xdg-open setsid rofi qs-ipc
  voxcmd-pick voxcmd-autostop
)
read -ra extra_stubs <<<"${SANDBOX_EXTRA_STUBS:-}"
for command_name in "${stubbed_commands[@]}" "${extra_stubs[@]}"; do ln -s .stub "$stub_dir/$command_name"; done
# Called by path, under $XDG_CONFIG_HOME/hypr/scripts.
for script_name in qs-ipc qs-picker screenshot.sh toggle-autolock.sh rofi-tmux.sh; do
  ln -s "$stub_dir/.stub" "$config_home/hypr/scripts/$script_name"
done

export SANDBOX_DIR="$sandbox_dir"
export SANDBOX_REAL_PATH="$PATH"
export SANDBOX_REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export SANDBOX_REAL_HOME="$HOME"
export HOME="$sandbox_dir/home"
export XDG_STATE_HOME="$sandbox_dir/home/.local/state"
export XDG_CACHE_HOME="$sandbox_dir/home/.cache"
export PATH="$stub_dir:$package_dir/.local/bin:$PATH"
export XDG_RUNTIME_DIR="$sandbox_dir/runtime"
export XDG_CONFIG_HOME="$config_home"
export VOXCMD_CONFIG_DIR="$config_home/voxcmd"
# A picker or confirm card has no bar to answer it here, so it gives up quickly.
export VOXCMD_PICK_TIMEOUT="${VOXCMD_PICK_TIMEOUT:-2}"
export VOXCMD_CONFIRM_TIMEOUT="${VOXCMD_CONFIRM_TIMEOUT:-2}"
unset VOXCMD_LLM_CMD

status=0
"$@" || status=$?
if [ "${SANDBOX_SHOW_CALLS:-}" = 1 ]; then
  printf '\n== stub calls\n' >&2
  cat "$sandbox_dir/calls.log" >&2
fi
exit "$status"
