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
#                                     SANDBOX_BINDS_JSON, SANDBOX_CLIENTS_JSON, ... (the JSON itself)
#   pw-dump                           SANDBOX_PW_DUMP_JSON
#   keeptabs-pick --json              SANDBOX_AGENTS_JSON
#   systemctl list-timers|list-units  SANDBOX_TIMERS_JSON
#   tmux list-sessions|has-session    SANDBOX_TMUX_SESSIONS (one name per line)
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

cp "$package_dir"/.config/voxcmd/integrations.d/*.sh "$config_home/voxcmd/integrations.d/"
cp "$package_dir"/.config/voxcmd/replacements.d/* "$config_home/voxcmd/replacements.d/"
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
  binds | clients | monitors | activewindow | activeworkspace | version)
    printenv "SANDBOX_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_JSON" || pass_through "$@"
    ;;
  dispatch | eval | keyword) log "$@" && echo ok ;;
  *) log "$@" ;;
  esac
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

# Called by name from PATH. hyprctl, pw-dump, keeptabs-pick, systemctl and tmux also answer read-only queries.
stubbed_commands=(
  hyprctl pw-dump keeptabs-pick systemctl tmux
  systemd-run notify-send pamixer wpctl bluetoothctl playerctl brightnessctl powerprofilesctl
  wlrctl wtype wl-copy voxtype wf-recorder xdg-open setsid rofi qs-ipc
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
