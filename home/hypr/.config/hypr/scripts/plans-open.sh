#!/usr/bin/env bash
# hypr/.config/hypr/scripts/plans-open.sh
# Open the plans board in the browser and focus the browser, starting the plans-serve user service when the port is closed.
# Opens https://<host>/ instead when the private remote.json (the file the board reads for the phone) names a host that
# answers, so the laptop and the phone share one address. On that address only the laptop key, which plans serve keeps in
# $XDG_STATE_HOME/plans/laptop-key, lets the board open the editor and cancel. PLANS_PORT picks another port, for tests.

port=${PLANS_PORT:-8765}
url=http://127.0.0.1:$port

# True when the listener serves the board page: a 200 with the page title. Another program on the port must not pass for
# the board. The server answers 403 to a request without a local Host header, so the probe sends one.
port_open() (
  exec 3<>"/dev/tcp/127.0.0.1/$port" 2>/dev/null || exit 1
  # One write: the server may read the request in a single recv.
  request=$(printf 'GET / HTTP/1.0\r\nHost: 127.0.0.1:%s\r\n\r\n.' "$port")
  printf '%s' "${request%.}" >&3
  response=$(timeout 1 cat <&3)
  [[ $response == "HTTP/1."*" 200 "* && $response == *"<title>plans</title>"* ]]
)

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

# The tailnet host, or nothing: no file, a broken file or a name that is not a plain host all mean local. The board reads
# the same file and refuses to serve the phone host without it.
remote_host() {
  local file=${XDG_CONFIG_HOME:-$HOME/.config}/plans/remote.json host
  [ -f "$file" ] && command -v jq >/dev/null || return 1
  host=$(jq -r 'if type == "object" and (.host | type) == "string" then .host else empty end' "$file" 2>/dev/null) || return 1
  host=${host%.}
  [[ $host =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
  printf '%s' "${host,,}"
}

# The board still opens locally when the tailnet is down, so a short timeout keeps the shortcut quick offline.
if host=$(remote_host) && curl -fsS -o /dev/null --max-time 2 "https://$host/" 2>/dev/null; then
  url=https://$host/
  # The fragment never reaches the server or a log, and the page strips it on load and keeps the key. $(<file) is a
  # bash read, so the key appears in no argv but xdg-open's and the browser's. Without a key the board opens anyway and
  # refuses only e and cancel.
  key_file=${XDG_STATE_HOME:-$HOME/.local/state}/plans/laptop-key
  if [ -r "$key_file" ]; then
    key=$(<"$key_file")
    [[ $key =~ ^[A-Za-z0-9_-]{43}$ ]] && open_url=$url#laptop-key=$key
    unset key
  fi
fi

xdg-open "${open_url:-$url}" >/dev/null 2>&1 &
unset open_url
command -v hyprctl >/dev/null && command -v jq >/dev/null || exit 0

# The default browser names the window class to focus: its desktop entry's StartupWMClass, else the entry's name. Same
# approach as the clock popup's open_and_focus_script.
id=$(xdg-mime query default x-scheme-handler/"${url%%:*}" 2>/dev/null)
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
