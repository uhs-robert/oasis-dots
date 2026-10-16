#!/bin/bash
# Tests the pass records of `lib/check.sh`: which steps a run skips as passed for their inputs, and when it records a tree.
# Runs in a scratch clone of this checkout whose check.sh steps only log their name, so no linter or suite runs.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CHECK_FULL CHECK_SKIP_STEPS CHECK_JOBS

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
holders=''
trap 'kill $holders 2>/dev/null; rm -rf "$scratch"' EXIT

git clone -q "$repo_dir" "$scratch/clone" || exit 1
cd "$scratch/clone" || exit 1
git config user.name cache-test
git config user.email cache-test@example.invalid
cp "$repo_dir"/lib/check.sh lib/
mkdir -p lib/check
cp -R "$repo_dir"/lib/check/. lib/check/
# Each step logs its name, fails when listed in FAIL_STEPS, and appends to EDIT_FILE when it is EDIT_STEP, as an agent
# editing while the check runs would.
# shellcheck disable=SC2016 # expanded by check.sh, where the stub lands
stub='  echo "$1" >>"$STEP_LOG"\n  [ "$1" != "${EDIT_STEP:-}" ] || echo edit >>"$EDIT_FILE"\n  case " ${FAIL_STEPS:-} " in *" $1 "*) return 1 ;; esac\n  return 0'
sed -i "s/^step_body() {\$/&\\n$stub/" lib/check.sh
git add -A
git commit -q --allow-empty -m 'scratch base' || exit 1
git branch -q main-line

export STEP_LOG=$scratch/steps
failures=0
ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# Runs the check; $ran is the steps that ran, one line.
check_run() {
  : >"$STEP_LOG"
  sh lib/check.sh "$@" >"$scratch/out" 2>&1
  status=$?
  ran=$(sort "$STEP_LOG" | paste -sd ' ' -)
}
ran_step() {
  case " $ran " in *" $1 "*) return 0 ;; esac
  return 1
}

voxcmd_file=$(git ls-files home/voxcmd | grep -v '\.sh$' | head -n 1)
qml_file=$(git ls-files 'home/quickshell/*.qml' | head -n 1)

check_run
expect "a first run runs every step" "[ $status = 0 ] && ran_step voxcmd-click && ran_step qmllint && ran_step shellcheck"
expect "a full pass of a clean tree records the tree" "lib/check/passed.sh is-passed"
check_run
expect "a second run runs nothing" "[ $status = 0 ] && [ -z '$ran' ]"
expect "and says why" "grep -q '^== voxcmd-click skipped (passed for these inputs)' '$scratch/out'"
CHECK_FULL=1 check_run
expect "CHECK_FULL=1 trusts no record" "ran_step voxcmd-click && ran_step conflicts"

# Both heavy-step slots held: the check itself takes none, so its steps run at once (the suites take theirs, stubbed here).
mkdir "$scratch/runtime"
for _ in 1 2; do
  XDG_RUNTIME_DIR=$scratch/runtime CHECK_HEAVY_SLOTS=2 sh -c '. lib/check/lock.sh; check_lock_take holder && exec sleep 30' &
  holders="$holders $!"
done
sleep 0.5
started=$(date +%s)
XDG_RUNTIME_DIR=$scratch/runtime CHECK_LOCK_WAIT_SECS=600 CHECK_FULL=1 check_run
elapsed=$(($(date +%s) - started))
expect "with every slot taken, the cheap steps still run without waiting" "[ $status = 0 ] && ran_step conflicts && [ $elapsed -lt 60 ]"
# shellcheck disable=SC2086 # pids
kill $holders 2>/dev/null

echo x >>"$voxcmd_file"
git commit -qam 'voxcmd change'
check_run --changed main-line
expect "a voxcmd change reruns the voxcmd steps" "ran_step voxcmd-click && ran_step voxcmd-wake"
expect "but not the QML ones" "! ran_step qmllint"
expect "a scoped pass on a clean tree is recorded against its base" "lib/check/passed.sh passed-since main-line"
expect "and, every step having passed for this content, as the tree" "lib/check/passed.sh is-passed"
voxcmd_commit=$(git rev-parse HEAD)

# main moves on with a change outside voxcmd, and the branch is rebased onto it.
git switch -q main-line
echo x >>"$qml_file"
git commit -qam 'qml change on main'
git switch -q -c rebased "$voxcmd_commit"
git rebase -q main-line
check_run --changed main-line
expect "a rebase onto a main that leaves voxcmd alone reuses the voxcmd passes" "[ $status = 0 ] && ! ran_step voxcmd-click"
expect "a scoped run checks the tree steps again for the new tree" "ran_step conflicts"
expect "the rebased tree passed against its new base" "lib/check/passed.sh passed-since main-line"
expect "but not in full: main's QML change never passed" "! lib/check/passed.sh is-passed"
check_run
expect "a full run then runs only what the QML change reaches" "ran_step qmllint && ! ran_step voxcmd-click"
expect "and records the tree" "lib/check/passed.sh is-passed"

trees_file=$(git rev-parse --git-common-dir)/claude-check-passed-trees
cp "$trees_file" "$scratch/trees.before"
echo dirty >>"$voxcmd_file"
check_run --changed HEAD
expect "an uncommitted voxcmd edit reruns the voxcmd steps" "ran_step voxcmd-click"
expect "a dirty tree is never recorded" "cmp -s '$trees_file' '$scratch/trees.before'"
check_run --changed HEAD
expect "the same uncommitted content then passes from its record" "! ran_step voxcmd-click"
echo dirtier >>"$voxcmd_file"
check_run --changed HEAD
expect "other uncommitted content does not" "ran_step voxcmd-click"
git checkout -q -- "$voxcmd_file"
echo new >home/voxcmd/untracked-input
check_run --changed HEAD
expect "an untracked file in a step's scope reruns it" "ran_step voxcmd-click"
rm home/voxcmd/untracked-input

echo y >>"$voxcmd_file"
git commit -qam 'another voxcmd change'
FAIL_STEPS=voxcmd-wake check_run --changed HEAD~
expect "a failing step fails the run" "[ $status = 1 ]"
check_run --changed HEAD~
expect "a failed step is not recorded" "ran_step voxcmd-wake"
expect "a passing step of a failed run is" "! ran_step voxcmd-click"

echo z >>"$voxcmd_file"
git commit -qam 'a third voxcmd change'
EDIT_STEP=voxcmd-click EDIT_FILE=$voxcmd_file check_run --changed HEAD~
git checkout -q -- "$voxcmd_file"
check_run --changed HEAD~
expect "a step whose input changed while it ran is not recorded" "ran_step voxcmd-click"

echo y >>"$qml_file"
printf '%s\n' "$qml_file" >"$scratch/paths"
git commit -qam 'qml again'
check_run --paths-from "$scratch/paths"
expect "--paths-from records steps" "ran_step qmllint"
expect "but no tree" "! lib/check/passed.sh is-passed"

[ "$failures" = 0 ] || {
  printf '%s failed\n' "$failures" >&2
  exit 1
}
echo 'all pass record cases passed'
