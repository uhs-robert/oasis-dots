#!/usr/bin/env bash
# Tests migrate_quickshell_state on scratch state dirs, never on the real one.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/migrate.sh"

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

# pgrep stand-in: succeeds only while $scratch/bar-running exists.
mkdir "$scratch/bin"
printf '#!/bin/sh\n[ -e "%s/bar-running" ]\n' "$scratch" >"$scratch/bin/pgrep"
chmod +x "$scratch/bin/pgrep"
PATH="$scratch/bin:$PATH"

# put <state> <id> <name> <content> <days old>
put() {
  mkdir -p "$1/by-shell/$2"
  printf '%s' "$4" >"$1/by-shell/$2/$3"
  touch -d "$5 days ago" "$1/by-shell/$2/$3"
}

case_name='no by-shell dir is a silent no-op that creates nothing'
output=$(migrate_quickshell_state "$scratch/none/quickshell" 2>&1)
check test -z "$output"
check test ! -e "$scratch/none"

case_name='copies the newest copy of each file independently and deletes by-shell'
s=$scratch/a/quickshell
put "$s" old notifications.json '{"dnd":false}' 5
put "$s" new notifications.json '{"dnd":true}' 1
put "$s" old claude_usage_warned.json '{"w":1}' 3
put "$s" other unrelated.json x 1
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = '{"dnd":true}'
check test "$(cat "$s/claude_usage_warned.json")" = '{"w":1}'
check test ! -e "$s/by-shell"

case_name='is idempotent'
before=$(find "$scratch/a" | sort)
output=$(migrate_quickshell_state "$s" 2>&1)
check test "$(find "$scratch/a" | sort)" = "$before"
check test -z "$output"

case_name='an older by-shell file does not overwrite a newer target, and by-shell is still deleted'
s=$scratch/b/quickshell
mkdir -p "$s"
printf mine >"$s/notifications.json"
put "$s" x notifications.json theirs 1
touch -d '0 days ago' "$s/notifications.json"
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = mine
check test ! -e "$s/by-shell"

case_name='a newer by-shell file overwrites an older target'
s=$scratch/b2/quickshell
mkdir -p "$s"
printf mine >"$s/notifications.json"
touch -d '5 days ago' "$s/notifications.json"
put "$s" x notifications.json theirs 1
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = theirs
check test ! -e "$s/by-shell"

case_name='ignores a newer empty file for an older non-empty one'
s=$scratch/c/quickshell
put "$s" old notifications.json '{"dnd":true}' 5
put "$s" new notifications.json '' 1
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = '{"dnd":true}'

case_name='only empty files: nothing copied, by-shell deleted'
s=$scratch/d/quickshell
put "$s" x notifications.json '' 1
mkdir -p "$s/by-shell/emptydir"
migrate_quickshell_state "$s" >/dev/null 2>&1
check test ! -e "$s/notifications.json"
check test ! -e "$s/by-shell"

case_name='a running bar: copies but keeps by-shell and warns; a rerun picks up later writes; a run with no bar deletes it'
s=$scratch/e/quickshell
put "$s" x notifications.json '{"dnd":true}' 2
touch "$scratch/bar-running"
output=$(migrate_quickshell_state "$s" 2>&1)
check test "$(cat "$s/notifications.json")" = '{"dnd":true}'
check test -d "$s/by-shell"
check grep -q 'bar is running' <<<"$output"
put "$s" x notifications.json '{"dnd":false}' 0
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = '{"dnd":false}'
check test -d "$s/by-shell"
rm "$scratch/bar-running"
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = '{"dnd":false}'
check test ! -e "$s/by-shell"
output=$(migrate_quickshell_state "$s" 2>&1)
check test -z "$output"

case_name='a large by-shell survives pipefail'
s=$scratch/h/quickshell
for i in $(seq 1 3000); do
  mkdir -p "$s/by-shell/id-with-a-fairly-long-name-to-fill-the-pipe-buffer-$i"
  printf x >"$s/by-shell/id-with-a-fairly-long-name-to-fill-the-pipe-buffer-$i/notifications.json"
done
put "$s" newest notifications.json '{"dnd":true}' 0
touch -d '1 day ago' "$s"/by-shell/id-with-*/notifications.json
(
  set -euo pipefail
  migrate_quickshell_state "$s" >/dev/null 2>&1
)
check test "$(cat "$s/notifications.json")" = '{"dnd":true}'
check test ! -e "$s/by-shell"

case_name='dry run changes nothing'
s=$scratch/f/quickshell
put "$s" x notifications.json '{"dnd":true}' 1
before=$(find "$scratch/f" | sort)
MIGRATE_DRY_RUN=1 migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(find "$scratch/f" | sort)" = "$before"

case_name='handles a space in the path'
s="$scratch/with space/quickshell"
put "$s" x notifications.json '{"dnd":true}' 1
migrate_quickshell_state "$s" >/dev/null 2>&1
check test "$(cat "$s/notifications.json")" = '{"dnd":true}'
check test ! -e "$s/by-shell"

case_name='default dir follows XDG_STATE_HOME, and falls back to HOME when empty'
x=$scratch/xdg
put "$x/quickshell" x notifications.json '{"dnd":true}' 1
XDG_STATE_HOME=$x migrate_quickshell_state >/dev/null 2>&1
check test "$(cat "$x/quickshell/notifications.json")" = '{"dnd":true}'
check test ! -e "$x/quickshell/by-shell"
h=$scratch/home
put "$h/.local/state/quickshell" x notifications.json '{"dnd":true}' 1
HOME=$h XDG_STATE_HOME='' migrate_quickshell_state >/dev/null 2>&1
check test "$(cat "$h/.local/state/quickshell/notifications.json")" = '{"dnd":true}'

case_name='refuses to delete a by-shell outside a quickshell dir'
s=$scratch/g/other
put "$s" x notifications.json '{"dnd":true}' 1
migrate_quickshell_state "$s" >/dev/null 2>&1
check test -d "$s/by-shell"

[[ $failures -eq 0 ]] && echo "migrate-quickshell-state: all passed"
exit $((failures > 0))
