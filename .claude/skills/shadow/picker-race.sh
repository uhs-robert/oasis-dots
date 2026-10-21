#!/usr/bin/env bash
# Repro for #1067 on a shadow bar: a second `choices` picker opened before the first has read its spec file
# must still answer the first caller. Fails on a bar without the ChoicesProvider load queue, passes with it.
# Usage: picker-race.sh [--name SHADOW] [<branch>...]   (branches as for `shadow.sh up`; none tests the main checkout)
set -euo pipefail

shadow="$(dirname "$0")/shadow.sh"
name=pkrace
if [[ ${1:-} == --name ]]; then
  name=${2:?--name needs a shadow name}
  shift 2
fi

work=$(mktemp -d)
failures=0
cleanup() {
  "$shadow" down "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}

ipc() { "$shadow" ipc "$name" picker "$@" >/dev/null; }

# make_spec <n> <label>: spec n with its own id and result file; labels are "<label>-one" and "<label>-two".
make_spec() {
  printf '{"id":"cb%s","label":"Title %s","choices":["%s-one","%s-two"],"result_path":"%s/r%s"}\n' \
    "$1" "$1" "$2" "$2" "$work" "$1" >"$work/s$1.json"
}

# Settled means long enough for the bar to have written a result it was going to write.
settle() { sleep 1; }

expect() { # <description> <result n> <expected content, or ABSENT>
  local file="$work/r$2" got
  if [[ ! -e $file ]]; then
    got=ABSENT
  else
    got=$(<"$file")
  fi
  if [[ $got == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 (r$2: want '$3', got '$got')"
    failures=$((failures + 1))
  fi
}

reset_run() {
  rm -f "$work"/r* "$work"/fifo*
  ipc close
  settle
  rm -f "$work"/r*
}

# Feed a blocked FIFO load after the later opens; bounded, since a bar that killed its reader leaves no one to open it.
# shellcheck disable=SC2016 # the inner shell expands its own arguments
release_fifo() { timeout 3 sh -c 'cat "$1" >"$2"' sh "$work/s$1.json" "$work/fifo$1" || true; }

# Armed only after `up` succeeds, so a name already in use is never torn down by this script.
"$shadow" up "$name" "$@"
trap cleanup EXIT
for n in 1 2 3; do make_spec "$n" "p$n"; done

echo "== single open"
ipc open_with choices "$work/s1.json"
settle
"$shadow" keys "$name" -k Return
settle
expect "single open: Enter answers its caller" 1 p1-one

echo "== race: second open before the first spec is read"
reset_run
mkfifo "$work/fifo1"
ipc open_with choices "$work/fifo1"
ipc open_with choices "$work/s2.json"
release_fifo 1
settle
expect "first caller answered empty" 1 ""
expect "second caller not answered before a pick" 2 ABSENT
"$shadow" keys "$name" -k Return
settle
expect "second picker answers its own caller" 2 p2-one

echo "== race: Escape on the second picker"
reset_run
mkfifo "$work/fifo1"
ipc open_with choices "$work/fifo1"
ipc open_with choices "$work/s2.json"
release_fifo 1
settle
# The first Escape leaves insert mode; the second closes the picker.
"$shadow" keys "$name" -k Escape
sleep 0.3
"$shadow" keys "$name" -k Escape
settle
expect "first caller answered empty" 1 ""
expect "Escape writes the second caller's empty result" 2 ""

echo "== three rapid opens"
reset_run
mkfifo "$work/fifo1" "$work/fifo2"
ipc open_with choices "$work/fifo1"
ipc open_with choices "$work/fifo2"
ipc open_with choices "$work/s3.json"
release_fifo 1
release_fifo 2
settle
expect "first caller answered empty" 1 ""
expect "middle caller answered empty" 2 ""
expect "last caller not answered before a pick" 3 ABSENT
"$shadow" keys "$name" -k Return
settle
expect "last picker answers its own caller" 3 p3-one

echo "== shell caller (no id) in a superseded load"
reset_run
mkfifo "$work/fifo1"
printf '{"label":"Title 1","choices":["p1-one"],"result_path":"%s/r1"}\n' "$work" >"$work/s1.json"
ipc open_with choices "$work/fifo1"
ipc open_with choices "$work/s2.json"
release_fifo 1
settle
expect "shell caller left to its own timeout" 1 ABSENT
"$shadow" keys "$name" -k Return
settle
expect "second picker still open and answers its own caller" 2 p2-one
make_spec 1 p1

echo "== picker closed while a second open is queued"
reset_run
mkfifo "$work/fifo1"
ipc open_with choices "$work/fifo1"
ipc open_with choices "$work/s2.json"
ipc close
settle
release_fifo 1
settle
expect "first caller answered empty" 1 ""
expect "queued caller answered empty, not left hanging" 2 ""

# The Lua callback runs after the result is written; the shadow has no HyprVim, so a callback that opens the
# next picker is stood in for by opening it right after the pick.
echo "== open from inside a callback"
reset_run
ipc open_with choices "$work/s1.json"
settle
"$shadow" keys "$name" -k Return
ipc open_with choices "$work/s2.json"
settle
expect "first pick kept" 1 p1-one
expect "second caller not answered before a pick" 2 ABSENT
"$shadow" keys "$name" -k Return
settle
expect "second picker answers its own caller" 2 p2-one

if ((failures > 0)); then
  echo "picker-race: $failures failed"
  exit 1
fi
echo "picker-race: all passed"
