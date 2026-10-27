#!/usr/bin/env bash
# Tests `shadow.sh action`: an ipc-kind id resolves headlessly and reaches `ipc` as the call `shadow.sh ipc` would make,
# a command- or lua-kind id is refused, an unknown id or a bad param fails with exit 5, and none of the refusals calls
# `ipc`. `ipc` is a recording stub, so no shadow, Hyprland or app is involved. Runs from a temp dir and fails if the
# repo's `git status` differs afterwards.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1
failures=0

before=$(git -C "$checkout_root" status --porcelain)

# shellcheck source=/dev/null # the shadow script, sourced for its functions only
source "$checkout_root/.claude/skills/shadow/shadow.sh"
set +e +o pipefail

calls=$work/calls
ipc() {
  printf '[%s]' "$@" >>"$calls"
  echo >>"$calls"
}

fail() {
  failures=$((failures + 1))
  echo "FAIL $*" >&2
}

# expect_call <expected ipc words, one string> <action words...>
expect_call() {
  local expected=$1
  shift
  : >"$calls"
  action x "$@" 2>"$work/err"
  local status=$?
  [[ $status == 0 ]] || fail "action $*: exit $status, wanted 0: $(<"$work/err")"
  [[ $(<"$calls") == "$expected" ]] || fail "action $*: ipc got '$(<"$calls")', wanted '$expected'"
}

# expect_refused <message fragment> <action words...>
expect_refused() {
  local fragment=$1
  shift
  : >"$calls"
  action x "$@" 2>"$work/err"
  local status=$?
  [[ $status == 5 ]] || fail "action $*: exit $status, wanted 5"
  grep -qF -- "$fragment" "$work/err" || fail "action $*: message '$(<"$work/err")' lacks '$fragment'"
  [[ ! -s $calls ]] || fail "action $*: ipc was called: $(<"$calls")"
}

# The recorder brackets each ipc word, so a split or merged word shows in the expected string.
expect_call "[x][popup][open][weather]" popup.open weather
expect_call "[x][zoom][step][-2]" zoom.step -2
expect_call "[x][notifications][toggle_dnd]" notifications.toggle_dnd
expect_call "[x][popup][open][a b'c \"d\"]" popup.open "a b'c \"d\""
expect_call "[x][popup][open][two
lines]" popup.open $'two\nlines'

expect_refused "unknown action 'no.such.id'" no.such.id
expect_refused "needs at least 1" popup.open
expect_refused "expects an int" zoom.step abc
expect_refused "param 1 (name)" picker.open nonsense
expect_refused "runs a command" delete.clear_clipboard
expect_refused "needs a live Hyprland" window.close

# Usage errors exit 2 like hypr-act, apart from the refusals' 5.
action x 2>/dev/null
[[ $? == 2 ]] || fail "action with no id did not exit 2"

[[ $(git -C "$checkout_root" status --porcelain) == "$before" ]] || fail "the test changed the repo"
((failures == 0)) || exit 1
echo "shadow-action: ok"
