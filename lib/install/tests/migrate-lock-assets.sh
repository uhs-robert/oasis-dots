#!/usr/bin/env bash
# Tests migrate_quickshell_lock_assets on scratch Quickshell trees, never on a real checkout.
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

old_layout() {
  qs=$1
  mkdir -p "$qs/lock/skins/ff7/audio/sub" "$qs/lock/skins/goldeneye/frames" "$qs/lock/skins/mgs2" "$qs/features/lock/skins/ff7"
  printf one >"$qs/lock/skins/ff7/audio/a.ogg"
  printf two >"$qs/lock/skins/ff7/audio/sub/b.ogg"
  printf frame >"$qs/lock/skins/goldeneye/frames/f1.png"
  printf qml >"$qs/lock/skins/mgs2/Keep.qml"
}

case_name='moves old assets and drops emptied dirs'
old_layout "$scratch/a"
migrate_quickshell_lock_assets "$scratch/a" >/dev/null 2>&1
check test "$(cat "$scratch/a/features/lock/skins/ff7/audio/a.ogg")" = one
check test "$(cat "$scratch/a/features/lock/skins/ff7/audio/sub/b.ogg")" = two
check test "$(cat "$scratch/a/features/lock/skins/goldeneye/frames/f1.png")" = frame
check test ! -e "$scratch/a/lock/skins/ff7"
check test ! -e "$scratch/a/lock/skins/goldeneye"
check test -f "$scratch/a/lock/skins/mgs2/Keep.qml"

case_name='is idempotent'
before=$(find "$scratch/a" | sort)
output=$(migrate_quickshell_lock_assets "$scratch/a" 2>&1)
check test "$(find "$scratch/a" | sort)" = "$before"
check test -z "$output"

case_name='removes lock/ once nothing else is in it'
old_layout "$scratch/e"
rm -r "$scratch/e/lock/skins/mgs2"
migrate_quickshell_lock_assets "$scratch/e" >/dev/null 2>&1
check test ! -e "$scratch/e/lock"

case_name='never overwrites and reports the conflict'
old_layout "$scratch/c"
mkdir -p "$scratch/c/features/lock/skins/ff7/audio"
printf mine >"$scratch/c/features/lock/skins/ff7/audio/a.ogg"
output=$(migrate_quickshell_lock_assets "$scratch/c" 2>&1)
check test "$(cat "$scratch/c/features/lock/skins/ff7/audio/a.ogg")" = mine
check test "$(cat "$scratch/c/lock/skins/ff7/audio/a.ogg")" = one
check grep -q 'already exists' <<<"$output"
check test "$(cat "$scratch/c/features/lock/skins/ff7/audio/sub/b.ogg")" = two

case_name='moves a symlinked asset dir as a link and survives under set -e'
old_layout "$scratch/s"
mkdir -p "$scratch/target/audio"
printf real >"$scratch/target/audio/x.ogg"
rm -r "$scratch/s/lock/skins/ff7/audio"
ln -s "$scratch/target/audio" "$scratch/s/lock/skins/ff7/audio"
check bash -ec "source $repo_dir/lib/common/output.sh; source $repo_dir/lib/install/migrate.sh; migrate_quickshell_lock_assets $scratch/s" >/dev/null 2>&1
check test -L "$scratch/s/features/lock/skins/ff7/audio"
check test "$(cat "$scratch/s/features/lock/skins/ff7/audio/x.ogg")" = real
check test ! -L "$scratch/s/lock/skins/ff7/audio"
check test -f "$scratch/target/audio/x.ogg"

case_name='moves a symlinked file inside a real dir without following it'
old_layout "$scratch/l"
printf real >"$scratch/target/file.ogg"
ln -s "$scratch/target/file.ogg" "$scratch/l/lock/skins/ff7/audio/link.ogg"
migrate_quickshell_lock_assets "$scratch/l" >/dev/null 2>&1
check test -L "$scratch/l/features/lock/skins/ff7/audio/link.ogg"
check test -f "$scratch/target/file.ogg"
check test ! -e "$scratch/l/lock/skins/ff7"

case_name='dry run changes nothing'
old_layout "$scratch/d"
before=$(find "$scratch/d" | sort)
MIGRATE_DRY_RUN=1 migrate_quickshell_lock_assets "$scratch/d" >/dev/null 2>&1
check test "$(find "$scratch/d" | sort)" = "$before"

[[ $failures -eq 0 ]] && echo "migrate-lock-assets: all passed"
exit $((failures > 0))
