#!/usr/bin/env bash
# hypr/.config/hypr/scripts/plans-open.sh
# Open the plans board in the browser and focus the browser, starting the plans-serve user service when the port is closed.
# PLANS_PORT picks another port, for tests.

port=${PLANS_PORT:-8765}
url=http://127.0.0.1:$port

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; }

if ! port_open; then
  systemctl --user start plans-serve
  # Ten polls of half a second: up to 5 seconds for the server to bind.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    port_open && break
    sleep 0.5
  done
  if ! port_open; then
    notify-send -u critical "Plans board" "plans-serve did not open port $port"
    exit 1
  fi
fi

xdg-open "$url" >/dev/null 2>&1 &
command -v hyprctl >/dev/null && command -v jq >/dev/null || exit 0

# The default browser names the window class to focus: its desktop entry's StartupWMClass, else the entry's name. Same
# approach as the clock popup's open_and_focus_script.
id=$(xdg-mime query default x-scheme-handler/https 2>/dev/null)
[ -n "$id" ] || exit 0
class=
old_ifs=$IFS
IFS=:
# shellcheck disable=SC2086 # IFS=: splits the search path on purpose.
for dir in ${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
  [ -f "$dir/applications/$id" ] || continue
  class=$(sed -n 's/^StartupWMClass=//p' "$dir/applications/$id" | head -n 1)
  break
done
IFS=$old_ifs
[ -n "$class" ] || class=${id%.desktop}
for _ in $(seq 20); do
  addr=$(hyprctl -j clients | jq -r --arg c "$class" '[.[] | select([.class, .initialClass] | map(ascii_downcase) | index($c | ascii_downcase))] | sort_by(.focusHistoryID) | .[0].address // empty')
  [ -n "$addr" ] && break
  sleep 0.25
done
[ -n "$addr" ] && hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })"
exit 0
