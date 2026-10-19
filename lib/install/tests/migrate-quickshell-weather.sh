#!/usr/bin/env bash
# Tests migrate_quickshell_weather on scratch dirs, never on the real ones.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'chmod -R u+rwX "$scratch" 2>/dev/null; rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/migrate.sh"

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

# No trailing newline, like the file the bar writes.
content='{"unit":"fahrenheit"}'

# Makes $scratch/$1/{qs,state}; sets q and s to them.
fresh() {
  q=$scratch/$1/qs
  s=$scratch/$1/state
  mkdir -p "$q"
}

case_name='no old file is a silent no-op that creates nothing'
fresh a
output=$(migrate_quickshell_weather "$q" "$s" 2>&1)
check test -z "$output"
check test ! -e "$s"

case_name='old only: moved byte for byte with its mtime, old deleted'
fresh b
printf '%s' "$content" >"$q/weather.local.json"
touch -d '5 days ago' "$q/weather.local.json"
want_mtime=$(stat -c %Y "$q/weather.local.json")
output=$(migrate_quickshell_weather "$q" "$s" 2>&1)
check test "$(cat "$s/weather.local.json")" = "$content"
check test "$(stat -c %Y "$s/weather.local.json")" = "$want_mtime"
check test ! -e "$q/weather.local.json"
check grep -q 'Moved' <<<"$output"

case_name='is idempotent'
before=$(find "$scratch/b" | sort)
output=$(migrate_quickshell_weather "$q" "$s" 2>&1)
check test "$(find "$scratch/b" | sort)" = "$before"
check test -z "$output"

case_name='both, identical: old deleted, new untouched'
fresh c
mkdir -p "$s"
printf '%s' "$content" >"$q/weather.local.json"
printf '%s' "$content" >"$s/weather.local.json"
migrate_quickshell_weather "$q" "$s" >/dev/null 2>&1
check test ! -e "$q/weather.local.json"
check test "$(cat "$s/weather.local.json")" = "$content"

case_name='both, different: both kept, warns, returns 0'
fresh d
mkdir -p "$s"
printf old >"$q/weather.local.json"
printf mine >"$s/weather.local.json"
output=$(
  set -e
  migrate_quickshell_weather "$q" "$s" 2>&1
)
check test "$?" -eq 0
check grep -q 'exist and differ' <<<"$output"
check test "$(cat "$q/weather.local.json")" = old
check test "$(cat "$s/weather.local.json")" = mine

case_name='dry run changes nothing, with old only and with both identical'
fresh e
printf '%s' "$content" >"$q/weather.local.json"
before=$(find "$scratch/e" | sort)
MIGRATE_DRY_RUN=1 migrate_quickshell_weather "$q" "$s" >/dev/null 2>&1
check test "$(find "$scratch/e" | sort)" = "$before"
mkdir -p "$s"
printf '%s' "$content" >"$s/weather.local.json"
before=$(find "$scratch/e" | sort)
MIGRATE_DRY_RUN=1 migrate_quickshell_weather "$q" "$s" >/dev/null 2>&1
check test "$(find "$scratch/e" | sort)" = "$before"
check test -f "$q/weather.local.json"

case_name='an old symlink is copied as a regular file; the link goes, its target stays'
fresh f
printf '%s' "$content" >"$scratch/f/elsewhere.json"
ln -s "$scratch/f/elsewhere.json" "$q/weather.local.json"
migrate_quickshell_weather "$q" "$s" >/dev/null 2>&1
check test -f "$s/weather.local.json"
check test ! -L "$s/weather.local.json"
check test "$(cat "$s/weather.local.json")" = "$content"
check test ! -L "$q/weather.local.json"
check test ! -e "$q/weather.local.json"
check test -f "$scratch/f/elsewhere.json"

case_name='a dangling old symlink is a no-op'
fresh g
ln -s "$scratch/g/missing" "$q/weather.local.json"
output=$(migrate_quickshell_weather "$q" "$s" 2>&1)
check test -z "$output"
check test ! -e "$s"
check test -L "$q/weather.local.json"

case_name='a dangling new symlink is left alone, its target is not created, old is kept'
fresh h
mkdir -p "$s"
printf '%s' "$content" >"$q/weather.local.json"
ln -s "$scratch/h/target" "$s/weather.local.json"
migrate_quickshell_weather "$q" "$s" >/dev/null 2>&1
check test ! -e "$scratch/h/target"
check test -L "$s/weather.local.json"
check test -f "$q/weather.local.json"

case_name='an unreadable old file warns and returns 0, keeps old, leaves no new file'
fresh i
printf '%s' "$content" >"$q/weather.local.json"
chmod 000 "$q/weather.local.json"
if [[ -r "$q/weather.local.json" ]]; then
  echo "skip: $case_name (file is readable, running as root?)"
else
  output=$(
    set -e
    migrate_quickshell_weather "$q" "$s" 2>&1
  )
  check test "$?" -eq 0
  check grep -q 'Could not move' <<<"$output"
  check test -e "$q/weather.local.json"
  check test ! -e "$s/weather.local.json"
fi

case_name='a state dir that cannot be created warns and returns 0, keeps old'
fresh j
printf '%s' "$content" >"$q/weather.local.json"
printf x >"$scratch/j/state"
output=$(
  set -e
  migrate_quickshell_weather "$q" "$s" 2>&1
)
check test "$?" -eq 0
check grep -q 'Could not move' <<<"$output"
check test "$(cat "$q/weather.local.json")" = "$content"

case_name='a failed verify removes the new file and keeps the old one'
fresh k
printf '%s' "$content" >"$q/weather.local.json"
output=$(
  cmp() { return 1; }
  migrate_quickshell_weather "$q" "$s" 2>&1
)
check grep -q 'Could not move' <<<"$output"
check test ! -e "$s/weather.local.json"
check test "$(cat "$q/weather.local.json")" = "$content"

case_name='handles a space in the path'
q="$scratch/with space/qs"
s="$scratch/with space/state"
mkdir -p "$q"
printf '%s' "$content" >"$q/weather.local.json"
migrate_quickshell_weather "$q" "$s" >/dev/null 2>&1
check test "$(cat "$s/weather.local.json")" = "$content"

case_name='defaults follow DOTFILES_DIR and XDG_STATE_HOME, and HOME when XDG_STATE_HOME is empty'
d=$scratch/dots
dq=$d/home/quickshell/.config/quickshell
mkdir -p "$dq"
printf '%s' "$content" >"$dq/weather.local.json"
x=$scratch/xdg
DOTFILES_DIR=$d XDG_STATE_HOME=$x migrate_quickshell_weather >/dev/null 2>&1
check test "$(cat "$x/quickshell/weather.local.json")" = "$content"
check test ! -e "$dq/weather.local.json"
h=$scratch/home
printf '%s' "$content" >"$dq/weather.local.json"
DOTFILES_DIR=$d HOME=$h XDG_STATE_HOME='' migrate_quickshell_weather >/dev/null 2>&1
check test "$(cat "$h/.local/state/quickshell/weather.local.json")" = "$content"

[[ $failures -eq 0 ]] && echo "migrate-quickshell-weather: all passed"
exit $((failures > 0))
