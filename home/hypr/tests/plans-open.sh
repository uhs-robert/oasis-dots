#!/usr/bin/env bash
# Tests scripts/plans-open.sh against stubbed systemctl, xdg-open, xdg-mime, hyprctl and notify-send, on a spare port:
# an open port opens the URL without starting the service, a closed port is started and then opened, and a port that
# never opens sends a notification and exits non-zero. The stubs keep the owner's service, browser and desktop out of it.
set -u

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
  python3 -I -c 'import socket,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", '"$PLANS_PORT"')); s.listen(); time.sleep(20)' >/dev/null 2>&1 &
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
echo testbrowser.desktop
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
chmod +x "$work"/bin/*

# run <start binds the port: 1|0>; sets $out (the log) and $code
run() {
  : >"$work/log"
  HOME="$work/home" PATH="$work/bin:$PATH" LOG="$work/log" WORK="$work" PLANS_PORT=$port START_BINDS=$1 bash "$script" >/dev/null 2>&1
  code=$?
  sleep 0.3
  out=$(cat "$work/log")
}

expect() { # <name> <condition result>
  if ! eval "$2"; then
    failures=$((failures + 1))
    echo "FAIL $1: code=$code log='$out'" >&2
  fi
}

# Port open: no start, URL opened, browser focused.
python3 -I -c 'import socket,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", '"$port"')); s.listen(); time.sleep(20)' &
listener=$!
sleep 0.5
run 0
expect "port open: no start" '[[ $out != *systemctl* ]]'
expect "port open: opens url" '[[ $out == *"xdg-open http://127.0.0.1:$port"* ]]'
expect "port open: focuses browser" '[[ $out == *"address:0xB"* && $code -eq 0 ]]'
kill "$listener"
wait "$listener" 2>/dev/null
listener=

# Port closed, the start opens it.
run 1
expect "closed then started: start called" '[[ $out == *"systemctl --user start plans-serve"* ]]'
expect "closed then started: opens url" '[[ $out == *"xdg-open http://127.0.0.1:$port"* && $code -eq 0 ]]'
kill "$(cat "$work/started.pid")" 2>/dev/null
sleep 0.5

# Port never opens.
start=$SECONDS
run 0
expect "never opens: notifies" '[[ $out == *"notify"* ]]'
expect "never opens: exits non-zero without opening" '[[ $code -ne 0 && $out != *xdg-open* ]]'
expect "never opens: gives up in about 5 seconds" '(( SECONDS - start >= 4 && SECONDS - start <= 8 ))'

echo "$((7 - failures))/7 passed"
exit $((failures ? 1 : 0))
