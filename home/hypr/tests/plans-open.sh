#!/usr/bin/env bash
# Tests scripts/plans-open.sh against stubbed systemctl, xdg-open, xdg-mime, hyprctl and notify-send, on a spare port:
# an open port opens the URL without starting the service, a closed port is started and then opened, and a port that
# never opens sends a notification and exits non-zero. A fake remote.json and curl stub cover the tailnet link: it opens
# when the host answers, and no file, a dead host, a bad host or a broken file open the local URL. The stubs keep the
# owner's service, browser and desktop out of it.
set -u

command -v jq >/dev/null || {
  echo "skip: plans-open test needs jq"
  exit 0
}

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.config/hypr/scripts/plans-open.sh
work=$(mktemp -d)
listener=
trap '[ -n "$listener" ] && kill "$listener" 2>/dev/null; [ -f "$work/started.pid" ] && kill "$(cat "$work/started.pid")" 2>/dev/null; rm -rf "$work"' EXIT
failures=0
port=${PLANS_TEST_PORT:-48765}

mkdir "$work/bin" "$work/home"
cat >"$work/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >>"$LOG"
# START_BINDS=1 stands in for a service that binds the port once started.
if [ "${START_BINDS:-}" = 1 ]; then
  python3 -I -c 'import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); PORT='"$PLANS_PORT"'; s.bind(("127.0.0.1", PORT)); s.listen()
end=time.time()+20
s.settimeout(1)
while time.time()<end:
    try: c,_=s.accept()
    except OSError: continue
    d=b""
    while b"\r\n\r\n" not in d:
        m=c.recv(2048)
        if not m: break
        d+=m
    ok=b"\r\nHost: 127.0.0.1:"+str(PORT).encode()+b"\r\n" in d
    c.sendall(b"HTTP/1.0 "+(sys.argv[1] if ok else "403 Forbidden").encode()+b"\r\n\r\n<title>plans</title>"); c.close()' "${REPLY_STATUS:-200 OK}" >/dev/null 2>&1 &
  echo $! >"$WORK/started.pid"
fi
exit 0
STUB
cat >"$work/bin/xdg-open" <<'STUB'
#!/usr/bin/env bash
echo "xdg-open $*" >>"$LOG"
STUB
cat >"$work/bin/xdg-mime" <<'STUB'
#!/usr/bin/env bash
# Only the two web schemes have a handler, so a wrong scheme query leaves the browser unfocused.
case "$*" in
*x-scheme-handler/http | *x-scheme-handler/https) echo testbrowser.desktop ;;
esac
STUB
cat >"$work/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
-j) echo '[{"class":"testbrowser","initialClass":"testbrowser","address":"0xB","focusHistoryID":0}]' ;;
dispatch) echo "focus $2" >>"$LOG" ;;
esac
STUB
cat >"$work/bin/notify-send" <<'STUB'
#!/usr/bin/env bash
echo "notify $*" >>"$LOG"
STUB
cat >"$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >>"$LOG"
[ "${TAILNET_UP:-}" = 1 ]
STUB
chmod +x "$work"/bin/*

# run <start binds the port: 1|0>; sets $out (the log) and $code
run() {
  : >"$work/log"
  HOME="$work/home" XDG_CONFIG_HOME="$work/config" TAILNET_UP=${TAILNET_UP:-0} PATH="$work/bin:$PATH" LOG="$work/log" WORK="$work" PLANS_PORT=$port START_BINDS=$1 bash "$script" >/dev/null 2>&1
  code=$?
  sleep 0.3
  out=$(cat "$work/log")
}

fail() {
  failures=$((failures + 1))
  echo "FAIL $1: code=$code log='$out'" >&2
}

# serve <status line>: a listener on $port that answers every request with that status, as $listener.
serve() {
  python3 -I -c 'import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); PORT='"$port"'; s.bind(("127.0.0.1", PORT)); s.listen()
end=time.time()+20
s.settimeout(1)
while time.time()<end:
    try: c,_=s.accept()
    except OSError: continue
    d=b""
    while b"\r\n\r\n" not in d:
        m=c.recv(2048)
        if not m: break
        d+=m
    ok=b"\r\nHost: 127.0.0.1:"+str(PORT).encode()+b"\r\n" in d
    c.sendall(b"HTTP/1.0 "+(sys.argv[1] if ok else "403 Forbidden").encode()+b"\r\n\r\n<title>plans</title>"); c.close()' "$1" >/dev/null 2>&1 &
  listener=$!
  sleep 0.5
}
stop_listener() {
  kill "$listener"
  wait "$listener" 2>/dev/null
  listener=
}

# Port open: no start, URL opened, browser focused.
serve "200 OK"
run 0
[[ $out != *systemctl* ]] || fail "port open: no start"
[[ $out == *"xdg-open http://127.0.0.1:$port"* ]] || fail "port open: opens url"
[[ $out == *"address:0xB"* && $code -eq 0 ]] || fail "port open: focuses browser"
stop_listener

# Port closed, the start opens it.
run 1
[[ $out == *"systemctl --user start plans-serve"* ]] || fail "closed then started: start called"
[[ $out == *"xdg-open http://127.0.0.1:$port"* && $code -eq 0 ]] || fail "closed then started: opens url"
kill "$(cat "$work/started.pid")" 2>/dev/null
sleep 0.5

# Port never opens.
start=$SECONDS
run 0
elapsed=$((SECONDS - start))
[[ $out == *notify* ]] || fail "never opens: notifies"
[[ $code -ne 0 && $out != *xdg-open* ]] || fail "never opens: exits non-zero without opening"
[[ $elapsed -ge 4 && $elapsed -le 8 ]] || fail "never opens: gives up in about 5 seconds"

# Another program owns the port: it does not count as the board.
serve "404 Not Found"
run 0
[[ $code -ne 0 && $out != *xdg-open* ]] || fail "foreign listener: not opened"
stop_listener

# Tailnet link: the fake host answers, then does not, then remote.json is broken, then absent.
mkdir -p "$work/config/plans"
serve "200 OK"
echo '{"host": "board.example.ts.net.", "login": "me@example"}' >"$work/config/plans/remote.json"
TAILNET_UP=1 run 0
[[ $out == *"curl "*"https://board.example.ts.net/"* && $out == *"xdg-open https://board.example.ts.net/"* ]] || fail "tailnet up: opens https url"
[[ $out != *"xdg-open http://127"* && $code -eq 0 ]] || fail "tailnet up: no local open"
[[ $out == *"--max-time "* ]] || fail "tailnet up: probe has a timeout"
[[ $out == *"address:0xB"* ]] || fail "tailnet up: focuses browser"
TAILNET_UP=0 run 0
[[ $out == *"xdg-open http://127.0.0.1:$port"* && $out != *"xdg-open https"* ]] || fail "tailnet down: opens local"
echo '{not json' >"$work/config/plans/remote.json"
TAILNET_UP=1 run 0
[[ $out == *"xdg-open http://127.0.0.1:$port"* && $out != *curl* ]] || fail "broken file: opens local"
for bad in 'a/b.example' 'a b.example'; do
  printf '{"host": "%s", "login": "me@example"}' "$bad" >"$work/config/plans/remote.json"
  TAILNET_UP=1 run 0
  [[ $out == *"xdg-open http://127.0.0.1:$port"* && $out != *curl* ]] || fail "bad host '$bad': opens local"
done
rm "$work/config/plans/remote.json"
TAILNET_UP=1 run 0
[[ $out == *"xdg-open http://127.0.0.1:$port"* && $out != *curl* ]] || fail "no file: opens local"
stop_listener

echo "$((14 + 2 + 1 - failures))/17 passed"
exit $((failures ? 1 : 0))
