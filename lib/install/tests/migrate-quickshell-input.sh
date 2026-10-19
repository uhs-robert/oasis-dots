#!/usr/bin/env bash
# Tests migrate_quickshell_input on scratch state dirs, never on the real one.
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
old='{"start_mode":"normal"}'

case_name='no state dir is a silent no-op that creates nothing'
output=$(migrate_quickshell_input "$scratch/none/quickshell" 2>&1)
check test -z "$output"
check test ! -e "$scratch/none"

case_name='a state dir without input.json creates nothing'
s=$scratch/empty/quickshell
mkdir -p "$s"
output=$(migrate_quickshell_input "$s" 2>&1)
check test -z "$output"
check test ! -e "$s/typing.json"

case_name='copies input.json to typing.json byte for byte, keeping mtime and the old file'
s=$scratch/a/quickshell
mkdir -p "$s"
printf '%s' "$old" >"$s/input.json"
touch -d '5 days ago' "$s/input.json"
migrate_quickshell_input "$s" >/dev/null 2>&1
check cmp -s "$s/input.json" "$s/typing.json"
check test "$(stat -c %Y "$s/input.json")" = "$(stat -c %Y "$s/typing.json")"
check test "$(cat "$s/input.json")" = "$old"

case_name='is idempotent'
before=$(find "$scratch/a" | sort)
output=$(migrate_quickshell_input "$s" 2>&1)
check test "$(find "$scratch/a" | sort)" = "$before"
check test -z "$output"

case_name='an existing typing.json wins and input.json is untouched'
s=$scratch/b/quickshell
mkdir -p "$s"
printf old >"$s/input.json"
printf mine >"$s/typing.json"
output=$(migrate_quickshell_input "$s" 2>&1)
check test "$(cat "$s/typing.json")" = mine
check test "$(cat "$s/input.json")" = old
check test -z "$output"

case_name='dry run changes nothing'
s=$scratch/c/quickshell
mkdir -p "$s"
printf '%s' "$old" >"$s/input.json"
before=$(find "$scratch/c" | sort)
MIGRATE_DRY_RUN=1 migrate_quickshell_input "$s" >/dev/null 2>&1
check test "$(find "$scratch/c" | sort)" = "$before"

case_name='an input.json symlink is copied as a regular file'
s=$scratch/d/quickshell
mkdir -p "$s"
printf '%s' "$old" >"$scratch/d/elsewhere.json"
ln -s "$scratch/d/elsewhere.json" "$s/input.json"
migrate_quickshell_input "$s" >/dev/null 2>&1
check test -f "$s/typing.json"
check test ! -L "$s/typing.json"
check test "$(cat "$s/typing.json")" = "$old"

case_name='a dangling input.json symlink is a no-op'
s=$scratch/d2/quickshell
mkdir -p "$s"
ln -s "$scratch/d2/missing" "$s/input.json"
migrate_quickshell_input "$s" >/dev/null 2>&1
check test ! -e "$s/typing.json"
check test ! -L "$s/typing.json"

case_name='a dangling typing.json symlink is left alone and its target is not created'
s=$scratch/e/quickshell
mkdir -p "$s"
printf '%s' "$old" >"$s/input.json"
ln -s "$scratch/e/target" "$s/typing.json"
migrate_quickshell_input "$s" >/dev/null 2>&1
check test ! -e "$scratch/e/target"
check test -L "$s/typing.json"

case_name='an unreadable input.json warns and returns 0 without typing.json'
s=$scratch/f/quickshell
mkdir -p "$s"
printf '%s' "$old" >"$s/input.json"
chmod 000 "$s/input.json"
if [[ -r "$s/input.json" ]]; then
  echo "skip: $case_name (file is readable, running as root?)"
else
  output=$(
    set -e
    migrate_quickshell_input "$s" 2>&1
  )
  check test "$?" -eq 0
  check grep -q 'Could not copy' <<<"$output"
  check test ! -e "$s/typing.json"
fi

case_name='handles a space in the path'
s="$scratch/with space/quickshell"
mkdir -p "$s"
printf '%s' "$old" >"$s/input.json"
migrate_quickshell_input "$s" >/dev/null 2>&1
check test "$(cat "$s/typing.json")" = "$old"

case_name='default dir follows XDG_STATE_HOME, and falls back to HOME when empty'
x=$scratch/xdg
mkdir -p "$x/quickshell"
printf '%s' "$old" >"$x/quickshell/input.json"
XDG_STATE_HOME=$x migrate_quickshell_input >/dev/null 2>&1
check test "$(cat "$x/quickshell/typing.json")" = "$old"
h=$scratch/home
mkdir -p "$h/.local/state/quickshell"
printf '%s' "$old" >"$h/.local/state/quickshell/input.json"
HOME=$h XDG_STATE_HOME='' migrate_quickshell_input >/dev/null 2>&1
check test "$(cat "$h/.local/state/quickshell/typing.json")" = "$old"

[[ $failures -eq 0 ]] && echo "migrate-quickshell-input: all passed"
exit $((failures > 0))
