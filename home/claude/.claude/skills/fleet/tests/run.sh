#!/usr/bin/env bash
# Replays watch.sh against a temp repo with fake tmux, plans, ps and gh on PATH: the stuck rule for each piece status,
# the HUNG rule (cwd, command line, runner list, once per pid) and the CI_RED rule (once per sha, quiet without gh).
# shellcheck disable=SC2016,SC2034 # The check strings are single-quoted on purpose (eval'd later); out is read only inside them.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../watch.sh}
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

suite=$(mktemp -d)
trap 'cd /; rm -rf "$suite"' EXIT
stubs=$suite/stubs tools=$suite/tools
mkdir -p "$stubs" "$tools"
# Only these real tools are visible, so the real gh never runs and "gh missing" is a PATH without a stub.
for tool in bash git jq flock awk sed grep cut cksum stat find date sort tail head readlink mkdir mv cat timeout dirname printf env sleep tr mktemp rm; do
  ln -s "$(command -v "$tool")" "$tools/$tool"
done

cat >"$stubs/tmux" <<'STUB'
#!/usr/bin/env bash
case $1 in
list-windows) echo "%1|win|0|4242" ;;
capture-pane) cat "$FAKE_PANE" ;;
esac
STUB
cat >"$stubs/plans" <<'STUB'
#!/usr/bin/env bash
cat "$FAKE_DOCS"
STUB
cat >"$stubs/ps" <<'STUB'
#!/usr/bin/env bash
case $* in
*comm=*) echo claude ;;
*) cat "$FAKE_PS" ;;
esac
STUB
cat >"$stubs/gh" <<'STUB'
#!/usr/bin/env bash
[[ -z ${FAKE_GH_OFFLINE-} ]] || exit 1
case $* in
"repo view"*) echo '{"nameWithOwner":"me/repo","defaultBranchRef":{"name":"main"}}' ;;
"run list --branch main"*) cat "$FAKE_GH_RUN" ;;
*) exit 1 ;;
esac
STUB
chmod +x "$stubs"/*

main=$suite/main
git init -q -b main "$main"
cd "$main" || exit 1
g commit -q --allow-empty -m A
g worktree add -q "$suite/wt-mine" -b mine
g worktree add -q "$suite/wt-other" -b other
wt=$suite/wt-mine
other=$suite/wt-other

export FAKE_PANE=$suite/pane FAKE_DOCS=$suite/docs FAKE_PS=$suite/ps FAKE_GH_RUN=$suite/ghrun FLEET_PROC_DIR=$suite/proc
printf 'working\n❯\xc2\xa0\n' >"$FAKE_PANE"
: >"$FAKE_PS"
echo '[]' >"$FAKE_GH_RUN"
mkdir -p "$FLEET_PROC_DIR"

doc() { # <status> <waiting_on> [branch]
  printf '[{"id":"p1","branch":"%s","path":"%s/p1.md","project":"proj","status":"%s","waiting_on":"%s"}]\n' "${3:-mine}" "$suite" "$1" "$2" >"$FAKE_DOCS"
}
fresh() { rm -rf "$main/.logs" "$FLEET_PROC_DIR"; mkdir -p "$FLEET_PROC_DIR"; : >"$FAKE_PS"; echo '[]' >"$FAKE_GH_RUN"; }
# run [env...]: stdout in $out
run() { out=$(env PATH="$stubs:$tools" "$@" bash "$script" fl proj 2>&1); }
# cwd_of <pid> <dir>: the fake /proc link
cwd_of() { mkdir -p "$FLEET_PROC_DIR/$1" && ln -sfn "$2" "$FLEET_PROC_DIR/$1/cwd"; }

echo "== STUCK covers building, review and approved"
for status in building review approved; do
  fresh
  doc "$status" ""
  run FLEET_STUCK_SECONDS=0
  check "$status with waiting_on empty is STUCK" '[[ $out == "STUCK win: idle 0m with an unfinished piece: p1" ]]'
done
fresh
doc review "a reviewer"
run FLEET_STUCK_SECONDS=0
check "review with waiting_on set is exempt" '[[ $out != STUCK* ]]'
fresh
doc review ""
run FLEET_STUCK_SECONDS=3600
check "review under the stuck time is ok" '[[ $out == ok ]]'
fresh
doc review ""
run FLEET_STUCK_SECONDS=0
run FLEET_STUCK_SECONDS=0
check "STUCK is reported once" '[[ $out == ok ]]'
fresh
doc merged ""
run FLEET_STUCK_SECONDS=0
check "a merged piece is not STUCK" '[[ $out == "all finished" ]]'

echo "== HUNG"
fresh
doc review "waiting"
{
  echo "100 36000 node --test test/a.test.js"
  echo "101 36000 node --test test/b.test.js"
  echo "102 36000 node --test $wt/test/c.test.js"
  echo "103 60 node --test test/d.test.js"
  echo "104 36000 /usr/lib/firefox/firefox"
  echo "105 36000 /usr/bin/betterbird"
  echo "106 36000 /usr/bin/betterbird -profile /tmp/bb-profile"
  echo "107 36000 bash -c sleep 99999"
  echo "108 36000 npm run e2e"
  echo "109 36000 node --test test/e.test.js"
  echo "110 8000 just test"
  echo "111 36000 /usr/bin/betterbird --profile /home/me/.betterbird"
  echo "112 7200 labwc"
} >"$FAKE_PS"
cwd_of 100 "$wt"
cwd_of 101 "$suite"
cwd_of 104 "$wt"
cwd_of 105 "$wt"
cwd_of 106 "$wt/sub"
cwd_of 107 "$wt"
cwd_of 108 "$wt"
cwd_of 109 "$other"
cwd_of 110 "$wt"
cwd_of 111 "$wt"
cwd_of 112 "$wt"
run
check "node --test by cwd, 10h" '[[ $out == *"HUNG win 100 10h00m"* ]]'
check "a runner outside the worktree is not flagged" '[[ $out != *" 101 "* ]]'
check "a worktree path on the command line is flagged" '[[ $out == *"HUNG win 102 10h00m"* ]]'
check "a young runner is not flagged" '[[ $out != *" 103 "* ]]'
check "Firefox is never flagged" '[[ $out != *" 104 "* ]]'
check "the owner's Betterbird without a /tmp profile is not flagged" '[[ $out != *" 105 "* && $out != *" 111 "* ]]'
check "Betterbird on a /tmp profile is flagged" '[[ $out == *"HUNG win 106 "* ]]'
check "a non-runner is not flagged" '[[ $out != *" 107 "* ]]'
check "npm run e2e is flagged" '[[ $out == *"HUNG win 108 "* ]]'
check "another session's worktree is not flagged" '[[ $out != *" 109 "* ]]'
check "just test at 8000s is flagged as 2h13m" '[[ $out == *"HUNG win 110 2h13m"* ]]'
check "exactly the hung time is not flagged" '[[ $out != *" 112 "* ]]'
run
check "a reported pid is quiet on the next check" '[[ $out != *HUNG* ]]'
check "the state file keeps reported pids" 'grep -q "^@hung.100.win" "$main/.logs/proj/fleet-watch-fl.state"'
sed -i '/^100 /d' "$FAKE_PS"
run
check "a pid that ended is forgotten" '! grep -q "^@hung.100" "$main/.logs/proj/fleet-watch-fl.state"'
echo "100 36000 node --test test/a.test.js" >>"$FAKE_PS"
run
check "a reused pid is reported again" '[[ $out == *"HUNG win 100 "* ]]'
run FLEET_HUNG_SECONDS=40000
check "FLEET_HUNG_SECONDS raises the limit" '[[ $out != *HUNG* ]]'

echo "== CI_RED"
fresh
doc review "waiting"
echo '[{"conclusion":"failure","url":"https://github.com/me/repo/actions/runs/9","headSha":"abc"}]' >"$FAKE_GH_RUN"
run
check "a failed run on the default branch is CI_RED" '[[ $out == "CI_RED me/repo https://github.com/me/repo/actions/runs/9" ]]'
run
check "the same head sha is quiet" '[[ $out != *CI_RED* ]]'
echo '[{"conclusion":"failure","url":"https://github.com/me/repo/actions/runs/10","headSha":"def"}]' >"$FAKE_GH_RUN"
run
check "a new head sha reports again" '[[ $out == *"CI_RED me/repo https://github.com/me/repo/actions/runs/10"* ]]'
echo '[{"conclusion":"success","url":"u","headSha":"ghi"}]' >"$FAKE_GH_RUN"
run
check "a green run is quiet" '[[ $out != *CI_RED* ]]'
echo '[]' >"$FAKE_GH_RUN"
run
check "no run is quiet" '[[ $out != *CI_RED* ]]'
echo '[{"conclusion":"failure","url":"u","headSha":"jkl"}]' >"$FAKE_GH_RUN"
run FAKE_GH_OFFLINE=1
check "offline gh is skipped quietly" '[[ $out != *CI_RED* && $out != *gh* ]]'
rm "$stubs/gh"
run
check "missing gh is skipped quietly" '[[ $out != *CI_RED* && $out != *gh* ]]'

echo
echo "$pass passed, $fail failed"
((fail == 0))
