#!/usr/bin/env bash
# Feeds PreToolUse inputs to guard-masked-checks.sh and checks which it refuses, against a throwaway repo.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../guard-masked-checks.sh
pass=0 fail=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# Built at runtime so this file holds no line that lib/check-conflicts.sh would read as a conflict marker.
printf -v ours '%*s' 7 ''
ours=${ours// /<}
printf -v theirs '%*s' 7 ''
theirs=${theirs// />}
printf -v split '%*s' 7 ''
split=${split// /=}

# run <cwd> <command>: prints the deny reason, or nothing when the hook allows the command.
run() {
  jq -n --arg c "$2" --arg d "$1" '{tool_input: {command: $c}, cwd: $d}' | "$hook" |
    jq -r '.hookSpecificOutput.permissionDecisionReason // empty'
}
expect() {
  local verdict=$1 want=$2 dir=$3 command=$4 reason
  reason=$(run "$dir" "$command")
  if [[ $verdict == deny && $reason == *"$want"* ]] || [[ $verdict == allow && -z $reason ]]; then
    echo "ok   $verdict: ${command//$'\n'/\\n}"
    pass=$((pass + 1))
  else
    echo "FAIL $verdict: ${command//$'\n'/\\n} (got: ${reason:-allowed})"
    fail=$((fail + 1))
  fi
}
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
fresh_repo() {
  repo=$root/repo$((++repos))
  git init -q "$repo"
  echo a >"$repo/a"
  g add a
  g commit -qm A
}
repos=0

echo "== synthetic CPU load"
load="synthetic CPU load"
expect deny "$load" "$root" 'yes > /dev/null &'
expect deny "$load" "$root" 'for i in 1 2 3 4; do yes >/dev/null & done'
expect deny "$load" "$root" 'yes | cat > /dev/null'
expect deny "$load" "$root" 'timeout 60 stress-ng --cpu 8'
expect deny "$load" "$root" 'stress --cpu 4 & just check'
expect deny "$load" "$root" 'while true; do :; done &'
expect deny "$load" "$root" $'while :\ndo\n  true\ndone'
expect allow "" "$root" 'yes | head -n 3'
expect allow "" "$root" 'grep -rn stress-ng . && echo yes > /dev/null'
expect allow "" "$root" $'cat >notes <<\'EOF\'\nyes > /dev/null\nstress-ng --cpu 8\nwhile true; do :; done\nEOF'

echo "== kills by name or pattern"
kill_msg="other sessions' processes"
expect deny "$kill_msg" "$root" 'pkill -f tests/run.sh'
expect deny "$kill_msg" "$root" 'pkill voxcmd'
expect deny "$kill_msg" "$root" 'sleep 1; killall -q run.sh'
expect deny "$kill_msg" "$root" 'pgrep -f run-phrases | xargs kill'
expect deny "$kill_msg" "$root" 'pgrep -f run-phrases | xargs -r kill -9'
expect allow "" "$root" 'pkill -P 4242 -f tests/run.sh'
expect allow "" "$root" 'pkill --parent=4242 sleep'
expect allow "" "$root" 'kill 4242'
expect allow "" "$root" 'kill "$!"'
expect allow "" "$root" 'pgrep -f tests/run.sh'
expect allow "" "$root" 'grep -rn pkill lib/'
expect allow "" "$root" $'cat >notes <<\'EOF\'\npkill -f tests/run.sh\nEOF'

echo "== check output piped into a filter"
masked="hides its exit code from &&"
expect deny "just check | tail $masked" "$root" 'just check 2>&1 | tail -3 && git push'
expect deny "home/voxcmd/tests/run.sh | grep" "$root" 'bash home/voxcmd/tests/run.sh | grep FAIL || echo clean'
expect deny "make test | tail" "$root" 'make test | tail && echo ok'
expect deny "npm run test | grep" "$root" 'npm run test | grep -c fail && echo ok'
expect deny "pytest | tail" "$root" 'python -m pytest -q | tail -1 && git push'
expect deny "cargo test | tail" "$root" 'cargo test 2>&1 | tail -3 && git push'
expect deny "./tests/run-all.sh | tail" "$root" './tests/run-all.sh | tail -3 && git push'
expect allow "" "$root" 'sh ./lib/check.sh | head -20 && echo done'
# The repo's own check commands come from its .claude/check-commands.
checks_repo=$root/checks
git init -q "$checks_repo"
mkdir "$checks_repo/.claude"
printf '%s\n' '# repo checks' 'lib/check.sh' 'home/voxcmd/tests/run-phrases.sh  # phrases' 'just lint' 'scripts/verify-*.sh' >"$checks_repo/.claude/check-commands"
expect deny "./lib/check.sh | head" "$checks_repo" 'sh ./lib/check.sh | head -20 && echo done'
expect deny "run-phrases.sh | tail" "$checks_repo" $'cd x\n./home/voxcmd/tests/run-phrases.sh |& tail -5 && echo ok'
expect deny "just lint | tail" "$checks_repo" 'just lint | tail -2 && echo ok'
expect deny "scripts/verify-fast.sh | grep" "$checks_repo" 'bash scripts/verify-fast.sh | grep -v ok && echo ok'
expect allow "" "$checks_repo" 'sh lib/checker.sh | head -20 && echo done'
expect deny "just check | tail" "$root" '(set -o pipefail); just check | tail -3 && git push'
expect deny "just check | tail" "$root" '(set -o pipefail; echo hi) && just check | tail -3 && git push'
expect allow "" "$root" '(set -o pipefail; just check | tail -3 && git push)'
expect allow "" "$root" 'set -o pipefail; (echo hi); just check | tail -3 && git push'
expect allow "" "$root" 'just check | tail -3'
expect allow "" "$root" 'just check | tail -3; echo done'
expect allow "" "$root" 'set -o pipefail; just check 2>&1 | tail -3 && git push'
expect allow "" "$root" $'set -euo pipefail\njust check | tail -3 && git push'
# shellcheck disable=SC2016 # a command for the hook to read, not to run
expect allow "" "$root" 'just check >"$log" 2>&1 && tail -3 "$log"'
expect allow "" "$root" 'just check-hooks | tail -3 && echo ok'
expect allow "" "$root" $'git commit -F - <<\'EOF\'\nfix: just check | tail -3 && push hid a failure\nEOF'

echo "== conflict markers"
staged="conflict markers staged in"
fresh_repo
printf '%s HEAD\nours\n%s\ntheirs\n%s branch\n' "$ours" "$split" "$theirs" >"$repo/a"
g add a
expect deny "$staged a: resolve them, git add, then continue" "$repo" 'git commit -m fix'
expect deny "$staged a" "$root" "git -C $repo commit -m fix"
expect deny "$staged a" "$root" "git -c core.editor=true -C $repo --no-pager commit"
expect deny "$staged a" "$root" "cd $repo && GIT_EDITOR=true git rebase --continue"
expect deny "$staged a" "$root" "cd $repo/.git/.. && git cherry-pick --continue"
expect deny "$staged a" "$repo" 'git merge --continue'
expect deny "$staged a" "$repo" 'git am --continue'
expect allow "" "$repo" 'git rebase --abort'
expect allow "" "$repo" $'cat >msg <<\'EOF\'\ngit commit\nEOF'
expect allow "" "$root" 'git commit -m fix'

fresh_repo
printf 'a %s mid-line mention\nHeading\n%s\n' "$ours" "$split" >"$repo/a"
g add a
expect allow "" "$repo" 'git commit -m docs'

fresh_repo
printf '%s HEAD\n' "$ours" >"$repo/a"
expect allow "" "$repo" 'git commit -m "nothing staged"'
expect deny "$staged a" "$repo" 'git add -A && git commit -m all'
expect deny "$staged a" "$repo" 'git commit -am all'
g checkout -q a
printf 'x\n%s branch\n' "$theirs" >"$repo/new"
expect deny "$staged new" "$root" "cd $repo && git add -A && git commit -m all"
expect allow "" "$repo" 'git commit -am tracked-only'

echo "== commit <pathspec> and commit -a read the worktree"
fresh_repo
echo b >"$repo/b"
g add b
g commit -qm B
printf '%s HEAD\n' "$ours" >"$repo/a"
expect deny "$staged a" "$repo" 'git commit -m fix a'
expect deny "$staged a" "$repo" 'git commit -o a -m fix'
expect deny "$staged a" "$repo" 'git commit -m "fix a thing" -- a'
expect deny "$staged a" "$root" "cd $repo && git commit -m fix a"
expect deny "$staged a" "$repo" 'git commit -a -m fix'
expect allow "" "$repo" 'git commit -m "touch a" b'
expect allow "" "$repo" 'git commit -m fix -- b'
mkdir "$repo/sub"
echo s >"$repo/sub/s"
g add sub/s
g commit -qm S
printf '%s HEAD\n' "$ours" >"$repo/sub/s"
expect deny "$staged sub/s" "$repo/sub" 'git commit -m fix s'
expect allow "" "$repo/sub" 'git commit -m fix ../b'

echo "$pass passed, $fail failed"
((fail == 0))
