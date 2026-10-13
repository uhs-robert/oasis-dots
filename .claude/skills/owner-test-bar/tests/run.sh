#!/usr/bin/env bash
# Checks the test bar ownership claim, the branch status and the Codex review requests (with the fake gh) against a
# temp cache dir; touches no bar, link or qs.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export XDG_CACHE_HOME=$root/cache
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
show() { while IFS= read -r line; do printf '   | %s\n' "$line"; done <<<"$1"; }
# as <session> <socket> <function> <args>...: runs one function of the sourced script as that session.
as() {
  local session=$1 socket=$2
  shift 2
  # shellcheck disable=SC1091
  CLAUDE_CODE_SESSION_ID=$session CLAUDE_CODE_MESSAGING_SOCKET=$socket CLAUDE_CODE_MESSAGING_TOKEN=secret-token \
    bash -c 'source "$1"; shift; "$@"' _ "$here/../owner-test-bar.sh" "$@" 2>&1
}
owner_file=$XDG_CACHE_HOME/dotfiles/test-bars/.owner
sock_a=$root/a.sock
touch "$sock_a"

echo "== no claim"
out=$(as b "$root/b.sock" guard_owner 0)
code=$?
check "passes" "[[ $code == 0 && -z \$out ]]"

echo "== a live claim by another session"
as a "$sock_a" record_owner clicks feat/x fix/y >/dev/null
check "records the address, session and branches" "jq -e '.address == \"uds:$sock_a\" and .session == \"a\" and .branches == [\"feat/x\", \"fix/y\"] and .bar == \"clicks\"' '$owner_file' >/dev/null"
check "never records the token" "! grep -q secret-token '$owner_file'"
out=$(as b "$root/b.sock" guard_owner 0)
code=$?
show "$out"
check "refuses" "[[ $code != 0 ]]"
check "says whom to message" "grep -qF \"test bar 'clicks' (feat/x fix/y) is owned by another session since\" <<<\"\$out\" && grep -qF 'SendMessage to uds:$sock_a to coordinate, or pass --take' <<<\"\$out\""
as a "$sock_a" guard_owner 0 >/dev/null
check "lets the owner session through" "[[ $? == 0 ]]"
as "" "$sock_a" guard_owner 0 >/dev/null
check "matches by socket without a session id" "[[ $? == 0 ]]"
out=$(as b "$root/b.sock" guard_owner 1)
code=$?
show "$out"
check "--take overrides" "[[ $code == 0 ]] && grep -q 'taking test bar' <<<\"\$out\""
out=$(as b "$root/b.sock" owner_status)
check "status says live" "grep -qF \"owner: session a at uds:$sock_a, test bar 'clicks' since\" <<<\"\$out\" && grep -q 'live$' <<<\"\$out\""

echo "== a stale claim"
rm "$sock_a"
out=$(as b "$root/b.sock" guard_owner 0)
code=$?
show "$out"
check "proceeds" "[[ $code == 0 ]]"
check "says it is stale" "grep -q 'is stale' <<<\"\$out\""
out=$(as b "$root/b.sock" owner_status)
check "status says stale" "grep -q 'stale$' <<<\"\$out\""

echo "== branch status"
repo=$root/repo
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g commit -q --allow-empty -m A
g branch kept
g branch moved
g branch gone
g worktree add -q --detach "$root/bar" main
printf '%s\n' kept moved gone >"$root/bar.branches"
out=$(as "" "" branches_state "$root/bar")
check "current while every branch is merged in" "[[ \$out == current ]]"
g switch -q moved
g commit -q --allow-empty -m B
g switch -q main
g branch -q -D gone
out=$(as "" "" branches_state "$root/bar")
show "$out"
check "names the moved and deleted branches" "[[ \$out == 'stale (moved has new commits), branch gone deleted' ]]"

echo "== codex review requests"
export FAKE_GH=$root/gh
mkdir "$FAKE_GH"
echo 7 >"$FAKE_GH/pr-feat-unreviewed"
echo 8 >"$FAKE_GH/pr-feat-reviewed"
echo 9 >"$FAKE_GH/pr-feat-asked"
commits='"commits": [{"committedDate": "2026-10-01T10:00:00Z"}]'
# shellcheck disable=SC2016 # Codex's comment, backticks and all
summary='<!-- codex-pull-request-review-summary --> **Completed** | `abc1234` |'
printf '{"headRefOid": "def5678", %s, "comments": [{"body": "%s", "createdAt": "2026-10-01T11:00:00Z"}]}' \
  "$commits" "$summary" >"$FAKE_GH/view-7.json"
printf '{"headRefOid": "abc1234ff", %s, "comments": [{"body": "%s", "createdAt": "2026-10-01T11:00:00Z"}]}' \
  "$commits" "$summary" >"$FAKE_GH/view-8.json"
printf '{"headRefOid": "aaa", %s, "comments": [{"body": "@codex review", "createdAt": "2026-10-01T11:00:00Z"}]}' \
  "$commits" >"$FAKE_GH/view-9.json"
out=$(PATH="$here:$PATH" as "" "" request_codex_reviews origin/feat-unreviewed feat-reviewed feat-asked feat-no-pr)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "requests a review only of the head nobody reviewed or asked about" "[[ \$(cat '$FAKE_GH/commented') == '7 @codex review' ]]"
check "says what it requested" "[[ \$out == 'codex: requested a review of #7 (feat-unreviewed)' ]]"
out=$(FAKE_GH_DOWN=1 PATH="$here:$PATH" as "" "" request_codex_reviews feat-unreviewed)
code=$?
check "is silent when gh fails" "[[ $code == 0 && -z \$out ]]"

echo "$pass passed, $fail failed"
((fail == 0))
