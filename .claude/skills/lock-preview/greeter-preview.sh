#!/usr/bin/env bash
# Run the staged login greeter through the real-hardware path (a PanelWindow per screen) in a shadow, with no user fonts, and screenshot it.
# The default `just greeter-preview` window skips that path, which hid the G3b font-order bug (#1028).
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
shadow="$repo/.claude/skills/shadow/shadow.sh"
name=greeter
layer=qs-greeter
usage="usage: greeter-preview.sh [--scale N] [--size WxH] [--out PATH]   # prints the log line and the PNG path"
scale=1.6 size=2560x1600 out=

die() {
  echo "greeter-preview: $*" >&2
  exit 1
}

while (($# > 0)); do
  case $1 in
  --scale) scale=${2:?$usage} && shift 2 ;;
  --size) size=${2:?$usage} && shift 2 ;;
  --out) out=${2:?$usage} && shift 2 ;;
  *) die "$usage" ;;
  esac
done

work=$(mktemp -d)
qs_pid=
cleanup() {
  [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null || true
  "$shadow" down "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

# Under bash, as the installer runs it: zsh does not glob the font list the way stage_greeter expects.
export DOTFILES_DIR=$repo
# shellcheck source=/dev/null
source "$repo/lib/install/load.sh"
stage_greeter "$work/stage" "$repo" >/dev/null

"$shadow" down "$name" >/dev/null 2>&1 || true
"$shadow" up "$name" --size "$size" >&2
# The shadow output is created at scale 1, and Hyprland rejects scales that do not divide the size (1.5 at 2560x1600); this changes it before the greeter maps.
"$shadow" hyprctl "$name" eval "hl.monitor({ output = 'WAYLAND-1', mode = '${size}@60', position = '0x0', scale = '$scale' })" >/dev/null

runtime=/tmp/shadow-$UID-$name
signature=$(<"${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow/$name/signature")
wl_socket=$(<"${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow/$name/wl-socket")
log=$work/qs.log
mkdir -p "$work"/{home,state,cache,data}

# env -i with a fake HOME and no FONTCONFIG_FILE: the owner's user fonts are invisible, as on the greeter user, so only the bundled fonts can supply Barlow.
# GREETD_SOCK is absent, so this is a preview; QS_GREETER_SCREENS makes it build the per-screen windows anyway.
env -i HOME="$work/home" USER="$USER" PATH=/usr/bin LANG=C.UTF-8 XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY="$wl_socket" \
  HYPRLAND_INSTANCE_SIGNATURE="$signature" XDG_CACHE_HOME="$work/cache" XDG_STATE_HOME="$work/state" XDG_DATA_HOME="$work/data" \
  QS_DISABLE_CRASH_HANDLER=1 QS_GREETER_STATE="$work/state" QS_GREETER_SCREENS=1 qs -p "$work/stage" >"$log" 2>&1 &
qs_pid=$!

for _ in $(seq 100); do
  "$shadow" hyprctl "$name" layers -j | jq -e --arg ns "$layer" 'any(.[].levels[][]; .namespace == $ns)' >/dev/null && break
  sleep 0.1
done
sleep 2
if [[ -z $out ]]; then out=$(mktemp --suffix=.png "${TMPDIR:-/tmp}/greeter-preview-XXXXXX"); fi
"$shadow" shot "$name" "$layer" --out "$out" >/dev/null || true

grep -m1 'greeter: fonts_ready=' "$log" || { echo "greeter-preview: no fonts_ready line; qs log tail:" >&2 && tail -n 15 "$log" >&2; }
echo "$out"
