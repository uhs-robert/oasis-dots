#!/usr/bin/env bash
# Tests scripts/focus-topgrade.sh against stubbed pgrep, ps, tmux and hyprctl: it must focus the window titled with the
# topgrade pane's session, and a window of a longer session whose name starts with it ("Config tools zsh" for session
# "Config") is not that window. The stubs keep the owner's tmux server and Hyprland out of it.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.config/hypr/scripts/focus-topgrade.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

mkdir "$work/bin"
cat >"$work/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
echo 4242
STUB
# One process, its parent is init, so the ancestor walk ends at once.
cat >"$work/bin/ps" <<'STUB'
#!/usr/bin/env bash
echo 1
STUB
cat >"$work/bin/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
list-panes) echo "4242 %1" ;;
list-sessions) printf '%s\n' "$SESSIONS" ;;
display) echo "$PANE_SESSION" ;;
esac
STUB
cat >"$work/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
clients) printf '%s' "$CLIENTS" ;;
dispatch) echo "$2" >>"$FOCUS_LOG" ;;
esac
STUB
cat >"$work/bin/qs-ipc" <<'STUB'
#!/usr/bin/env bash
echo "popup" >>"$FOCUS_LOG"
STUB
chmod +x "$work"/bin/*
mkdir -p "$work/home/.config/hypr/scripts"
cp "$work/bin/qs-ipc" "$work/home/.config/hypr/scripts/qs-ipc"

# check <name> <pane session> <sessions> <clients JSON> <wanted log line>
check() {
  local name=$1 got
  : >"$work/log"
  got=$(
    HOME="$work/home" PATH="$work/bin:$PATH" PANE_SESSION=$2 SESSIONS=$3 CLIENTS=$4 FOCUS_LOG="$work/log" bash "$script" >/dev/null 2>&1
    cat "$work/log"
  )
  if [[ $got != *"$5"* ]]; then
    failures=$((failures + 1))
    echo "FAIL $name: want '$5', got '$got'" >&2
  fi
}

clients='[{"title":"Config tools zsh","class":"kitty","address":"0xTOOLS"},{"title":"Config topgrade","class":"kitty","address":"0xCONFIG"}]'
check "the session's own window" Config $'Config\nConfig tools' "$clients" "0xCONFIG"
check "a longer session's window is skipped" Config $'Config\nConfig tools' '[{"title":"Config tools zsh","class":"kitty","address":"0xTOOLS"}]' "popup"
check "a longer session still finds its own window" "Config tools" $'Config\nConfig tools' "$clients" "0xTOOLS"
check "the layout prefix" Config Config '[{"title":"Tmux Config topgrade","class":"kitty","address":"0xLAYOUT"}]' "0xLAYOUT"
check "a plain title" UpHill UpHill '[{"title":"UpHill","class":"kitty","address":"0xPLAIN"}]' "0xPLAIN"

echo "$((5 - failures))/5 passed"
exit $((failures ? 1 : 0))
