#!/bin/bash
# Tests the pass records of `lib/check.sh`: which steps a run skips as passed for their inputs, and when it records a tree.
# Runs in a scratch clone of this checkout whose steps (lib/check/scopes.py) only log their name, so no linter or suite runs.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CHECK_FULL CHECK_SKIP_STEPS CHECK_JOBS VOXCMD_ONLY_SECTIONS

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
mkdir -p lib/common lib/install
cp -R "$repo_dir"/lib/common/. lib/common/
cp -R "$repo_dir"/lib/install/. lib/install/
# Each step logs its name, fails when listed in FAIL_STEPS, and appends to EDIT_FILE when it is EDIT_STEP, as an agent
# editing while the check runs would.
cat >>lib/check/scopes.py <<'EOF'

STUB = 'name=%s; echo "$name" >>"$STEP_LOG"; [ "$name" != "${EDIT_STEP:-}" ] || echo edit >>"$EDIT_FILE"; case " ${FAIL_STEPS:-} " in *" $name "*) exit 1 ;; esac'
STEPS = [step._replace(command=STUB % step.name) for step in STEPS]
EOF
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

# An edit to the scope table that touches no step reruns only the steps that read scopes.py (check-scope, check-cache) and the
# tree steps; the others keep their passes. Editing a step's own command or scope reruns that step.
echo '# an unrelated edit' >>lib/check/scopes.py
check_run
expect "an unrelated scopes.py edit reruns only the steps that read it" "ran_step check-scope && ran_step check-cache && ! ran_step voxcmd-click && ! ran_step qmllint && ! ran_step shellcheck"
git checkout -q -- lib/check/scopes.py
sed -i 's|^STEPS = \[step._replace(command=STUB % step.name)|STEPS = [step._replace(command=STUB % step.name + ("; :" if step.name == "qmllint" else ""))|' lib/check/scopes.py
check_run
expect "editing one step's command reruns that step alone" "ran_step qmllint && ! ran_step voxcmd-click && ! ran_step shellcheck"
git checkout -q -- lib/check/scopes.py

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

check_run --only nope
expect "--only with an unknown step exits 2" "[ $status = 2 ] && grep -q \"unknown step 'nope'\" '$scratch/out'"
check_run --only voxcmd-click,nope
expect "and runs nothing, even the steps it does know" "[ $status = 2 ] && [ -z '$ran' ]"

# Every step but voxcmd-click passes for this content, so once --only passes it, every step has: the tree record is
# then held back by the --only gate alone.
echo w >>"$voxcmd_file"
git commit -qam 'voxcmd change for --only'
FAIL_STEPS=voxcmd-click check_run
cp "$trees_file" "$scratch/trees.before"
check_run --only voxcmd-click,voxcmd-wake
expect "--only runs only the named steps not yet passed" "[ $status = 0 ] && [ '$ran' = voxcmd-click ]"
expect "and names the rest as passed" "grep -q 'skipped (passed for these inputs): voxcmd-wake;' '$scratch/out'"
expect "and says what it was limited to" "grep -q '^check: only voxcmd-click,voxcmd-wake; ran: voxcmd-click;' '$scratch/out'"
expect "--only never records the tree, though every step has now passed" "cmp -s '$trees_file' '$scratch/trees.before'"
check_run --only voxcmd-click --changed HEAD~
expect "nor a pass against a --changed base" "[ $status = 0 ] && cmp -s '$trees_file' '$scratch/trees.before'"
check_run --changed HEAD~
expect "a later --changed run reuses the pass --only recorded" "[ $status = 0 ] && ! ran_step voxcmd-click"
expect "and says so" "grep -q '^== voxcmd-click skipped (passed for these inputs)' '$scratch/out'"
expect "and records the tree itself" "lib/check/passed.sh passed-since HEAD~ && lib/check/passed.sh is-passed"
echo dirty >>"$voxcmd_file"
check_run --only voxcmd-click
expect "--only after an edit in the step's scope runs it again" "ran_step voxcmd-click"
git checkout -q -- "$voxcmd_file"

echo v >>"$voxcmd_file"
git commit -qam 'voxcmd change run in part'
cp "$trees_file" "$scratch/trees.before"
VOXCMD_ONLY_SECTIONS=some-section check_run --changed HEAD~
expect "VOXCMD_ONLY_SECTIONS runs the voxcmd suites" "[ $status = 0 ] && ran_step voxcmd-click"
expect "and says their pass is not recorded" "grep -q 'VOXCMD_ONLY_SECTIONS is set, so no pass is recorded for' '$scratch/out'"
expect "nor the tree or the base" "cmp -s '$trees_file' '$scratch/trees.before'"
check_run --changed HEAD~
expect "so the next run runs the suites again" "ran_step voxcmd-click && ran_step voxcmd-wake"
expect "but not the steps that ran whole beside them" "! ran_step conflicts"

[ "$failures" = 0 ] || {
  printf '%s failed\n' "$failures" >&2
  exit 1
}
echo 'all pass record cases passed'
