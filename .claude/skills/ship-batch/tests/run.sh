#!/usr/bin/env bash
# ship-batch against a temp repository: base selection, the lock, restows and whole batches against stubs; no GitHub.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../base.sh
source "$here/../base.sh"
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

root=$(mktemp -d) || exit 1
shadow_run=
# The end-to-end section starts detached daemons that outlive this script, so removing the temp root is not enough.
# Match processes by $root only, never by name.
cleanup() {
  trap '' EXIT TERM INT HUP
  rm -f "$root/e2e/branch_hold"
  pkill -f "$root/e2e/" 2>/dev/null
  rm -rf "$root" "$shadow_run"
}
trap cleanup EXIT
# bash runs the EXIT trap on these only when it traps them itself.
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP
# live-hypr.sh only treats a runtime dir under /tmp/shadow-* as a nested session, so this one cannot live under $root.
shadow_run=$(mktemp -d "/tmp/shadow-$UID-shipbatchtest.XXXXXX") || exit 1
repo=$root/repo
git init -q -b main "$repo"
g -C "$repo" commit -q --allow-empty -m one
first=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" worktree add -q "$root/wt" -b side
file=$(base_file "$repo")

echo "== fresh run records HEAD"
out=$(select_base "$repo" 2>"$root/err")
check "prints HEAD" "[[ $out == '$first' ]]"
check "records HEAD" "[[ \$(<'$file') == '$first' ]]"
check "says nothing" "[[ ! -s $root/err ]]"
check "a worktree sees the same file" "[[ \$(base_file '$root/wt') == '$file' ]]"

echo "== rerun after an unfinished run keeps the old base"
g -C "$repo" commit -q --allow-empty -m two
out=$(select_base "$repo" 2>"$root/err")
check "prints the recorded commit" "[[ $out == '$first' ]]"
check "keeps the file" "[[ \$(<'$file') == '$first' ]]"
check "announces the resume" "grep -q 'resuming from ${first:0:12}' $root/err"
check "recorded base is an ancestor of main" "base_is_ancestor '$repo' '$first' main"

echo "== finish removes the file"
finish_base "$repo"
check "file gone" "[[ ! -e '$file' ]]"
out=$(select_base "$repo" 2>/dev/null)
check "next run starts from the new HEAD" "[[ $out == '$(git -C "$repo" rev-parse HEAD)' ]]"
finish_base "$repo"

echo "== unusable bases"
g -C "$repo" switch -q --orphan other
g -C "$repo" commit -q --allow-empty -m unrelated
check "a commit main does not descend from is refused" "! base_is_ancestor '$repo' '$first' other"
check "a missing commit is refused" "! base_is_ancestor '$repo' 0000000000000000000000000000000000000001 main"

echo "== one batch at a time on the main checkout"
lock_file=$(dirname "$file")/ship-batch.lock
check "the first run takes the lock" "take_lock '$repo' '7 8'"
check "a second run gives up after the bounded wait" "! (SHIP_BATCH_LOCK_WAIT=1 take_lock '$repo' 9 2>'$root/err')"
check "naming the holder" "grep -q 'pid $$, since .*, merging 7 8' '$root/err'"
release_lock
check "release frees it at once" "(SHIP_BATCH_LOCK_WAIT=1 take_lock '$repo' 9)"
(
  take_lock "$repo" 5
  sleep 2
) &
holder=$!
for _ in $(seq 100); do
  grep -qs 'merging 5' "$lock_file" && break
  sleep 0.1
done
check "a second run waits for the first to finish" "(SHIP_BATCH_LOCK_WAIT=60 take_lock '$repo' 6 2>'$root/err') && grep -q 'merging 5' '$root/err'"
wait "$holder"

echo "== packages a merge left out of date"
stow_repo=$root/stow-repo
fake_home=$root/home
git init -q -b main "$stow_repo"
mkdir -p "$stow_repo/home/tools/.local/bin" "$stow_repo/home/folded/.config/folded" "$stow_repo/home/absent/.local/bin" "$fake_home/.local/bin" "$fake_home/.config"
echo a >"$stow_repo/home/tools/.local/bin/old"
echo a >"$stow_repo/home/folded/.config/folded/old"
echo a >"$stow_repo/home/absent/.local/bin/old"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m base
stow_before=$(git -C "$stow_repo" rev-parse HEAD)
# tools is stowed unfolded (a link per file), folded as a whole folder, absent not at all.
ln -s "$stow_repo/home/tools/.local/bin/old" "$fake_home/.local/bin/old"
ln -s "$stow_repo/home/folded/.config/folded" "$fake_home/.config/folded"
echo b >"$stow_repo/home/tools/.local/bin/new"
echo b >"$stow_repo/home/folded/.config/folded/new"
echo b >"$stow_repo/home/absent/.local/bin/new"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m add
stow_added=$(git -C "$stow_repo" rev-parse HEAD)
echo c >>"$stow_repo/home/tools/.local/bin/old"
g -C "$stow_repo" commit -q -am edit
stow_edited=$(git -C "$stow_repo" rev-parse HEAD)
restow() { HOME=$fake_home packages_to_restow "$stow_repo" "$@" | paste -sd,; }
check "an added file restows each installed package, folded or not" "[[ \$(restow '$stow_before' '$stow_added') == folded,tools ]]"
check "a package that is not stowed here is left alone" "[[ \$(restow '$stow_before' '$stow_added') != *absent* ]]"
check "an edit alone needs no restow" "[[ -z \$(restow '$stow_added' '$stow_edited') ]]"
g -C "$stow_repo" rm -q "$stow_repo/home/tools/.local/bin/new"
g -C "$stow_repo" commit -q -m remove
check "a removed file restows its package" "[[ \$(restow '$stow_edited' HEAD) == tools ]]"
mkdir -p "$stow_repo/home/units/.config/units"
echo a >"$stow_repo/home/units/.config/units/only"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m units
stow_units=$(git -C "$stow_repo" rev-parse HEAD)
mkdir -p "$fake_home/.config/units"
ln -s "$stow_repo/home/units/.config/units/only" "$fake_home/.config/units/only"
g -C "$stow_repo" mv "$stow_repo/home/units/.config/units/only" "$stow_repo/home/units/.config/units/renamed"
g -C "$stow_repo" commit -q -m rename
check "renaming a package's only linked file restows it, though its link now dangles" "[[ \$(restow '$stow_units' HEAD) == units ]]"
mkdir -p "$stow_repo/home/gone/.config/gone"
echo a >"$stow_repo/home/gone/.config/gone/only"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m gone
stow_gone=$(git -C "$stow_repo" rev-parse HEAD)
ln -s "$stow_repo/home/gone/.config/gone" "$fake_home/.config/gone"
g -C "$stow_repo" rm -rq "$stow_repo/home/gone"
g -C "$stow_repo" commit -q -m "delete gone"
check "a package the merge deleted is skipped, not restowed" "[[ -z \$(restow '$stow_gone' HEAD 2>/dev/null) ]]"
check "and says so" "[[ \$(restow '$stow_gone' HEAD 2>&1 >/dev/null) == *'home/gone no longer exists'* ]]"
mkdir -p "$stow_repo/home/never/.config/never"
echo a >"$stow_repo/home/never/.config/never/only"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m never
stow_never=$(git -C "$stow_repo" rev-parse HEAD)
g -C "$stow_repo" rm -rq "$stow_repo/home/never"
g -C "$stow_repo" commit -q -m "delete never"
check "a deleted package never stowed here is skipped silently" "[[ -z \$(restow '$stow_never' HEAD 2>&1) ]]"

echo "== the branch check, and a branch with no local worktree"
origin=$root/origin.git
work=$root/work
git init -q --bare -b main "$origin"
git clone -q "$origin" "$work" 2>/dev/null
mkdir -p "$work/lib"
# shellcheck disable=SC2016 # the stub expands its own variable
printf '#!/bin/sh\necho "$*" >>"${STUB_CHECK_LOG:-/dev/null}"\nexit "${STUB_CHECK_STATUS:-0}"\n' >"$work/lib/check.sh"
chmod +x "$work/lib/check.sh"
g -C "$work" add -A
g -C "$work" commit -q -m base
git -C "$work" push -q origin main 2>/dev/null
g -C "$work" switch -q -c pr-branch
echo change >"$work/file"
g -C "$work" add -A
g -C "$work" commit -q -m change
# What a forge serves for a PR whose branch was pushed from elsewhere.
git -C "$work" push -q origin pr-branch:refs/pull/7/head 2>/dev/null
check "a branch on top of origin/main is checked against it" "(cd '$work' && STUB_CHECK_LOG='$root/check.log' check_branch_here) && grep -qx -e '--changed origin/main' '$root/check.log'"
check "a failing check fails the branch" "! (cd '$work' && STUB_CHECK_STATUS=1 check_branch_here)"
# main moves on while the branch waits: its check would say nothing about what main becomes.
g -C "$work" switch -q main
echo more >"$work/more"
g -C "$work" add -A
g -C "$work" commit -q -m more
git -C "$work" push -q origin main 2>/dev/null
g -C "$work" switch -q pr-branch
: >"$root/check.log"
check "a branch missing commits of origin/main is refused, unchecked" "! (cd '$work' && STUB_CHECK_LOG='$root/check.log' check_branch_here 2>/dev/null) && [[ ! -s '$root/check.log' ]]"
add_temp_worktree "$work" pull/7/head
check "the temporary worktree is the PR head" "[[ \$(git -C '$temp_worktree' rev-parse HEAD) == \$(git -C '$work' rev-parse pr-branch) ]]"
tmp_path=$temp_worktree
remove_temp_worktree
check "removing it deletes the directory and the registration" "[[ ! -e '$tmp_path' ]] && ! git -C '$work' worktree list | grep -q '$tmp_path'"
check "a second removal is harmless" "remove_temp_worktree"
check "an unknown ref fails without leaving a worktree" "! add_temp_worktree '$work' pull/99/head && [[ -z \$temp_worktree ]]"
(
  add_temp_worktree "$work" pull/7/head
  echo "$temp_worktree" >"$root/exit-path"
  trap remove_temp_worktree EXIT
  exit 1
)
check "the EXIT trap removes it on a failing exit" "[[ ! -e \$(<'$root/exit-path') ]]"

echo "== a whole batch: reviews and branch checks before the lock"
# Stubs log each step with whether the ship lock was held at that moment: merge-prs (the gate under --check, the merge
# otherwise) and lib/check.sh in each worktree.
e2e=$root/e2e
stubs=$e2e/stubs
fake_home=$e2e/home
mkdir -p "$stubs" "$fake_home/.claude/skills/merge-prs"
export SHIP_LOG=$e2e/log
# Every run of ship-batch is bounded, so a reverted lifecycle fix fails its test instead of hanging the suite.
ship_timeout=120
# shellcheck disable=SC2016 # expanded by the stubs
lock_state='$(if flock -n "$SHIP_LOCK" true; then echo free; else echo held; fi)'
cat >"$fake_home/.claude/skills/merge-prs/merge-prs.sh" <<STUB
#!/usr/bin/env bash
if [[ \$1 == --check ]]; then
  echo "gate \$* $lock_state" >>"\$SHIP_LOG"
  # With $e2e/advance_branch present the PR branch gets a commit while the gate waits for its reviewers.
  if [[ -e $e2e/advance_branch ]]; then
    sleep 1 # the check is reading the worktree (index.lock) at first
    git -C "$e2e/wt-1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m late
    rm -f $e2e/advance_branch
  fi
  [[ " \${STUB_GATE_FAIL:-} " != *" \${*: -1} "* ]]
  exit
fi
echo "merge \$* $lock_state" >>"\$SHIP_LOG"
while [[ -e $e2e/merge_hold ]]; do sleep 0.2; done
[[ ! -e $e2e/merge_removes_wt ]] || git -C "$e2e/main" worktree remove --force "$e2e/wt-1"
[[ -z \${STUB_MERGE_FAIL:-} ]] || exit 1
for pr; do [[ \$pr == --* ]] && continue; git push -q origin "b\$pr:main" 2>/dev/null || exit 1; done
STUB
printf '#!/bin/sh\n' >"$fake_home/.claude/skills/merge-prs/status.sh"
# shellcheck disable=SC2016 # expanded by the stub
# With $e2e/stale_head present the PR head on the forge is not the commit that was checked.
cat >"$stubs/gh" <<STUB
#!/bin/sh
case "\$*" in
*headRefOid*) if [ -e $e2e/stale_head ]; then echo 0000000000000000000000000000000000000001; else git -C $e2e/main rev-parse "b\$3"; fi ;;
*) echo "b\$3" ;;
esac
STUB
# Logs each recipe with the lock state; fd 9 must not reach it.
cat >"$stubs/just" <<STUB
#!/usr/bin/env bash
: "\${SHIP_LOG:=$e2e/log}" "\${SHIP_LOCK:=$e2e/main/.git/ship-batch.lock}"
echo "just \$* $lock_state" >>"\$SHIP_LOG"
[[ ! -e /proc/\$\$/fd/9 ]] || echo "just fd9 leaked" >>"\$SHIP_LOG"
if [[ \$1 == migrate-quickshell-state ]]; then
  grep -q qs "\$STUB_QS_PROCS" 2>/dev/null && bar=up || bar=down
  echo "migrate bar \$bar" >>"\$SHIP_LOG"
  [[ -z \${STUB_MIGRATE_STATUS:-} || ( -n \${STUB_MIGRATE_ONLY_DOWN:-} && \$bar == up ) ]] || exit "\$STUB_MIGRATE_STATUS"
fi
[[ \$1 != voxcmd-build || -z \${STUB_VOXCMD_BUILD_STATUS:-} ]] || exit "\$STUB_VOXCMD_BUILD_STATUS"
exit \${STUB_JUST_STATUS:-0}
STUB
cat >"$stubs/notify-send" <<STUB
#!/usr/bin/env bash
: "\${SHIP_LOCK:=$e2e/main/.git/ship-batch.lock}"
echo "notify-send \$* $lock_state" >>"$e2e/log"
STUB
chmod +x "$stubs"/* "$fake_home"/.claude/skills/merge-prs/*

# A main checkout on main with two PR branches, b1 and b2, the second cut from the first, each in a worktree of its own.
e2e_setup() {
  rm -rf "$e2e/origin.git" "$e2e/main" "$e2e"/wt-* "$SHIP_LOG" "$e2e/branch_hold" "$e2e/advance_main" "$e2e/stale_head" "$e2e/advance_branch" "$e2e/merge_hold" "$e2e/merge_removes_wt"
  git init -q --bare -b main "$e2e/origin.git"
  git clone -q "$e2e/origin.git" "$e2e/main" 2>/dev/null
  mkdir -p "$e2e/main/lib" "$e2e/main/.claude/skills/ship-batch"
  cp "$here/../ship-batch.sh" "$here/../base.sh" "$here/../live-hypr.sh" "$e2e/main/.claude/skills/ship-batch/"
  # With $e2e/branch_hold present a check waits until that file is removed; STUB_BRANCH_STATUS is its exit status.
  cat >"$e2e/main/lib/check.sh" <<STUB
#!/usr/bin/env bash
echo "check \$(basename "\$PWD") \$* $lock_state" >>"\$SHIP_LOG"
echo "checking \$(basename "\$PWD")"
while [[ -e $e2e/branch_hold ]]; do sleep 0.2; done
# With $e2e/advance_main present another batch lands a commit on origin/main while the branch is being checked.
if [[ -e $e2e/advance_main ]]; then
  rm -rf $e2e/other && git clone -q $e2e/origin.git $e2e/other 2>/dev/null
  git -C $e2e/other -c user.name=t -c user.email=t@t commit -q --allow-empty -m other && git -C $e2e/other push -q origin main 2>/dev/null
fi
exit \${STUB_BRANCH_STATUS:-0}
STUB
  chmod +x "$e2e/main/lib/check.sh"
  g -C "$e2e/main" add -A
  g -C "$e2e/main" commit -q -m base
  git -C "$e2e/main" push -q origin main 2>/dev/null
  export SHIP_LOCK=$e2e/main/.git/ship-batch.lock
  git -C "$e2e/main" worktree add -q -b b1 "$e2e/wt-1"
  echo 1 >"$e2e/wt-1/one"
  g -C "$e2e/wt-1" add -A
  g -C "$e2e/wt-1" commit -q -m one
  git -C "$e2e/main" worktree add -q -b b2 "$e2e/wt-2" b1
  echo 2 >"$e2e/wt-2/two"
  g -C "$e2e/wt-2" add -A
  g -C "$e2e/wt-2" commit -q -m two
}
ship() { HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" "$@" >"$e2e/out" 2>&1; }
logged() { grep -qxF -- "$1" "$SHIP_LOG" 2>/dev/null; }
line_of() { grep -nxF -- "$1" "$SHIP_LOG" | cut -d: -f1; }

e2e_setup
ship 1 2
check "the batch succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "each review is waited for outside the lock, without requesting one" "logged 'gate --check --wait-review 1 free' && logged 'gate --check --wait-review 2 free'"
check "each branch is checked outside the lock" "logged 'check wt-1 --changed origin/main free' && logged 'check wt-2 --changed origin/main free'"
check "the merge runs under the lock, without waiting for reviews" "logged 'merge 1 2 held'"
check "after every review and branch check" "((\$(line_of 'check wt-2 --changed origin/main free') < \$(line_of 'merge 1 2 held')))"
# The foreground check starts while the batch still holds the lock and releases it moments later; the overlap is benign.
check "main is not checked after the merge" "! grep -q '^just check' '$SHIP_LOG' && ! grep -q 'check main' '$SHIP_LOG'"
check "main is pulled" "[[ \$(git -C '$e2e/main' rev-parse HEAD) == \$(git -C '$e2e/main' rev-parse b2) ]]"
check "nothing is left to resume" "[[ ! -e \$(base_file '$e2e/main') ]]"
check "the lock is free" "flock -n '$SHIP_LOCK' true"

e2e_setup
STUB_GATE_FAIL=2 ship 1 2
check "a PR failing its gate fails the run" "[[ $? != 0 ]]"
check "the PRs before it still merge" "logged 'merge 1 held' && [[ \$(git -C '$e2e/main' rev-parse HEAD) == \$(git -C '$e2e/main' rev-parse b1) ]]"
check "it and the ones after it are named for a rerun" "grep -q 'PR 2 does not pass the review gate; rerun ship-batch' '$e2e/out'"
check "a branch after it is not checked" "! logged 'check wt-2 --changed origin/main free'"

e2e_setup
STUB_GATE_FAIL=1 ship 1 2
check "a first PR failing its gate merges nothing" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && [[ ! -e \$(base_file '$e2e/main') ]]"

e2e_setup
STUB_BRANCH_STATUS=1 ship 1 2
check "a failing branch check merges nothing and fails the run" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && grep -q 'the check fails on b1 (PR 1)' '$e2e/out'"
check "and leaves nothing to resume" "[[ ! -e \$(base_file '$e2e/main') ]]"
check "the failing check's output is shown" "grep -q 'checking wt-1' '$e2e/out'"

# What would land was checked against an older main: another batch merged in between.
e2e_setup
touch "$e2e/advance_main"
ship 1
check "a branch checked against a main that has since moved is not merged" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && grep -q 'main moved since b1 was checked (PR 1); nothing was merged; rerun' '$e2e/out'"

# merge-prs merges the PR head on the forge, which can differ from the commit that was checked.
e2e_setup
touch "$e2e/stale_head"
ship 1
check "a PR whose head is not the checked commit is not merged" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && grep -q 'PR head differs from the checked commit' '$e2e/out'"

# A commit pushed while the reviewers are awaited was not part of the check.
e2e_setup
touch "$e2e/advance_branch"
ship 1
check "a commit that lands during the gate wait is not merged on the earlier pass" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && grep -q 'PR head differs from the checked commit' '$e2e/out'"

# The check runs on the worktree's files, so they must be the commit that merges.
e2e_setup
echo dirty >"$e2e/wt-1/untracked"
ship 1
check "a worktree with uncommitted changes is not checked or merged" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && grep -q 'b1 worktree has uncommitted changes; commit or stash them' '$e2e/out'"

# The check and the review wait run together: a check that fails while the gate is still waiting must not be lost.
e2e_setup
touch "$e2e/branch_hold"
(sleep 1 && rm -f "$e2e/branch_hold") &
STUB_BRANCH_STATUS=1 ship 1
check "a check that outlasts the gate still stops the merge" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG'"
wait

e2e_setup
ship --request-review 1 2
check "with --request-review the batch succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "the gate gets --request-review" "logged 'gate --check --wait-review --request-review 1 free' && logged 'gate --check --wait-review --request-review 2 free'"

e2e_setup
ship --skip-review-gate 1 2
check "with --skip-review-gate the batch succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "only the thread check runs before the lock, never a review wait" "logged 'gate --check --skip-review-gate 1 free' && logged 'gate --check --skip-review-gate 2 free' && ! grep -q -e '--wait-review' '$SHIP_LOG'"
check "each branch is still checked outside the lock" "logged 'check wt-1 --changed origin/main free' && logged 'check wt-2 --changed origin/main free'"
check "the merge gets --skip-review-gate under the lock" "logged 'merge --skip-review-gate 1 2 held'"
check "each PR says its reviewer states were skipped" "grep -q 'PR 1: reviewer states skipped by request; threads still checked' '$e2e/out' && grep -q 'PR 2: reviewer states skipped by request; threads still checked' '$e2e/out'"

e2e_setup
ship 1 2
check "without the flag nothing is skipped" "! grep -q 'skip' '$SHIP_LOG' '$e2e/out' && logged 'merge 1 2 held'"

echo "== the greeter's Quickshell paths"
greeter_regex=$(greeter_qs_regex "$here/../../../.." qs)
for path in features/lock/skins/x.qml features/lock/skins/sub/y.png features/lock/Tints.js styles/goldeneye/PanelShape.qml theme/Style.qml styles/nes/tokens.js assets/fonts/a.ttf assets/fonts/OFL-a.txt VERSION; do
  check "$path is staged" "grep -Eq '^$greeter_regex' <<<'qs/$path'"
done
for path in services/Foo.qml features/lock/Lock.qml assets/fonts/a.otf styles/nes/widgets/Foo.qml theme/Foo.qml; do
  check "$path is not staged" "! grep -Eq '^$greeter_regex' <<<'qs/$path'"
done

echo "== only an owner test bar blocks the bar restart"
# pgrep greps the command lines in STUB_QS_PROCS with the pattern ship-batch passes. A restart would kill the real qs,
# so the stub qs-ipc reports a locked screen ("secure"): reaching that failure shows the test-bar check let the restart proceed.
mkdir -p "$fake_home/.config/hypr/scripts" "$e2e/cache"
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\nfor a; do :; done; grep -E -- "$a" "$STUB_QS_PROCS"\n' >"$stubs/pgrep"
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\nif grep -qx "qs -n" "$STUB_QS_PROCS" 2>/dev/null; then echo "[{\\"pid\\": 4242}]"; else echo "No instances"; fi\n' >"$stubs/qs"
printf '#!/bin/sh\necho secure\n' >"$fake_home/.config/hypr/scripts/qs-ipc"
chmod +x "$stubs/pgrep" "$stubs/qs" "$fake_home/.config/hypr/scripts/qs-ipc"
export STUB_QS_PROCS=$e2e/qs_procs XDG_CACHE_HOME=$e2e/cache
bar_ship() {
  e2e_setup
  mkdir -p "$e2e/wt-1/home/quickshell"
  echo bar >"$e2e/wt-1/home/quickshell/bar"
  g -C "$e2e/wt-1" add -A
  g -C "$e2e/wt-1" commit -q -m bar
  ship 1
}
echo "qs -p /tmp/json_store_x/cfg" >"$STUB_QS_PROCS"
bar_ship
check "an unrelated qs -p instance does not block the restart" "grep -q \"lock state 'secure'\" '$e2e/out'"
echo "qs -n -p $e2e/cache/dotfiles/test-bars/x/home/quickshell/.config/quickshell" >"$STUB_QS_PROCS"
bar_ship
check "an owner test bar still blocks it" "grep -q 'a test bar is running' '$e2e/out'"

echo "== ship-batch finds the live Hyprland signature itself"
# hyprctl answers only for signatures listed in STUB_LIVE_SIGS and logs the signature each call ran with. Instance
# directories hold a .socket.sock whose age orders them; a shadow's nested Hyprland lives in its own runtime dir.
cat >"$stubs/hyprctl" <<STUB
#!/bin/sh
grep -qx "\$HYPRLAND_INSTANCE_SIGNATURE" "\$STUB_LIVE_SIGS" || exit 1
[ -e "\$XDG_RUNTIME_DIR/hypr/\$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ] || exit 1
echo "hyprctl \${HYPRLAND_INSTANCE_SIGNATURE} \$*" >>"\$SHIP_LOG"
[ "\$1" = dispatch ] && echo "qs -n" >"\$STUB_QS_PROCS"
[ "\$1" = reload ] && exit "\${STUB_RELOAD_STATUS:-0}"
exit 0
STUB
chmod +x "$stubs/hyprctl"
export STUB_LIVE_SIGS=$e2e/live_sigs
owner_run=$e2e/owner_run
rm -rf "$owner_run"
mkdir -p "$owner_run/hypr/live" "$owner_run/hypr/old_live" "$owner_run/hypr/dead" "$shadow_run/hypr/nested"
touch -d '1 hour ago' "$owner_run/hypr/live/.socket.sock"
touch -d '2 hours ago' "$owner_run/hypr/old_live/.socket.sock"
touch "$owner_run/hypr/dead/.socket.sock"
touch "$shadow_run/hypr/nested/.socket.sock"
printf 'live\nold_live\nnested\n' >"$STUB_LIVE_SIGS"
hypr_ship() {
  e2e_setup
  mkdir -p "$e2e/wt-1/home/hypr"
  echo cfg >"$e2e/wt-1/home/hypr/cfg"
  g -C "$e2e/wt-1" add -A
  g -C "$e2e/wt-1" commit -q -m hypr
  env -u HYPRLAND_INSTANCE_SIGNATURE "$@" HOME="$fake_home" PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1
}
hypr_ship XDG_RUNTIME_DIR="$owner_run" HYPRLAND_INSTANCE_SIGNATURE=gone
check "a stale signature gives way to the newest instance that answers" "[[ $? == 0 ]] && logged 'hyprctl live reload' && logged 'hyprctl live configerrors'"
check "it says which instance it used, on stderr" "grep -q 'using the live instance live' '$e2e/out'"
hypr_ship XDG_RUNTIME_DIR="$owner_run"
check "an unset signature is found too" "[[ $? == 0 ]] && logged 'hyprctl live reload'"
hypr_ship XDG_RUNTIME_DIR="$owner_run" HYPRLAND_INSTANCE_SIGNATURE=old_live
check "a valid signature in the environment is kept" "[[ $? == 0 ]] && logged 'hyprctl old_live reload' && ! grep -q 'using the live instance' '$e2e/out'"
hypr_ship XDG_RUNTIME_DIR="$shadow_run" OWNER_RUNTIME_DIR="$owner_run"
check "a shell inside a shadow still picks the owner's session, never the nested instance" "[[ $? == 0 ]] && logged 'hyprctl live reload' && ! grep -q nested '$SHIP_LOG'"
hypr_ship XDG_RUNTIME_DIR="$shadow_run" OWNER_RUNTIME_DIR="$owner_run" HYPRLAND_INSTANCE_SIGNATURE=nested
check "a shadow's own valid signature is not kept" "[[ $? == 0 ]] && logged 'hyprctl live reload' && ! grep -q nested '$SHIP_LOG'"
printf 'nested\n' >"$STUB_LIVE_SIGS"
hypr_ship XDG_RUNTIME_DIR="$shadow_run" OWNER_RUNTIME_DIR="$owner_run"
check "with only a shadow answering it dies instead of using it" "[[ $? != 0 ]] && grep -q 'hyprctl cannot reach Hyprland' '$e2e/out' && ! grep -q '^hyprctl' '$SHIP_LOG'"
hypr_ship XDG_RUNTIME_DIR="$owner_run"
check "with no instance answering it dies with a clear message" "[[ $? != 0 ]] && grep -q 'hyprctl cannot reach Hyprland' '$e2e/out'"
printf 'live\n' >"$STUB_LIVE_SIGS"
hypr_ship XDG_RUNTIME_DIR="$owner_run" STUB_RELOAD_STATUS=4
check "a failing reload dies with a message, not a silent exit" "[[ $? != 0 ]] && grep -q 'hyprctl reload failed (exit 4)' '$e2e/out'"
rm -rf "$shadow_run"

echo "== the install migrations run when a merge changes migration code"
# Each run commits the given files on b1. The stubs log the migration step with the lock state and whether a bar is up, and
# the bar restart as restart-bar stop and start (stubbed). The stub bar answers unlocked so the restart goes ahead.
printf '#!/bin/sh\necho unlocked\n' >"$fake_home/.config/hypr/scripts/qs-ipc"
# The shared restart-bar.sh is stubbed: it logs the mode and any leaked lock descriptor, a stop empties the bar list the
# migrate stub reads, a start fills it. STUB_BAR_STOP_STATUS / STUB_BAR_START_STATUS make that half fail.
cat >"$fake_home/.config/hypr/scripts/restart-bar.sh" <<STUB
#!/bin/sh
echo "restart-bar \$1" >>"\$SHIP_LOG"
[ ! -e /proc/\$\$/fd/9 ] || echo "restart-bar fd9 leaked" >>"\$SHIP_LOG"
case "\$1" in
stop) [ -z "\${STUB_BAR_STOP_STATUS:-}" ] || exit "\$STUB_BAR_STOP_STATUS"; : >"\$STUB_QS_PROCS" ;;
start) [ -z "\${STUB_BAR_START_STATUS:-}" ] || exit "\$STUB_BAR_START_STATUS"; echo "qs -n" >"\$STUB_QS_PROCS" ;;
esac
STUB
chmod +x "$fake_home/.config/hypr/scripts/restart-bar.sh"
printf 'live\n' >"$STUB_LIVE_SIGS"
migrate_step='just migrate-quickshell-state held'
migrate_ship() {
  e2e_setup
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "$e2e/wt-1/$f")"
    echo changed >"$e2e/wt-1/$f"
  done
  g -C "$e2e/wt-1" add -A
  g -C "$e2e/wt-1" commit -q -m migrate
  echo "qs -n" >"$STUB_QS_PROCS"
  env XDG_RUNTIME_DIR="$owner_run" HOME="$fake_home" PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1
}
# shellcheck disable=SC2329 # called by the checks below, through eval
migrate_count() { grep -cxF -- "$migrate_step" "$SHIP_LOG"; }
start_line() { line_of 'restart-bar start'; }
migrate_ship lib/install/migrate.sh home/quickshell/bar
check "a merge touching migrate.sh succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "it runs the migrations twice, under the lock" "[[ \$(migrate_count) == 2 ]]"
check "the first run is with the bar up, before the restart" "((\$(line_of 'migrate bar up') < \$(line_of 'restart-bar stop')))"
check "the second is after the old bar is gone and before the new one starts" "logged 'migrate bar down' && ((\$(line_of 'restart-bar stop') < \$(line_of 'migrate bar down') && \$(line_of 'migrate bar down') < \$(start_line)))"
check "without the ship lock's descriptor" "! logged 'just fd9 leaked'"
for path in lib/install/load.sh install.sh justfile; do
  migrate_ship "$path"
  check "a merge touching $path runs the step once, with no bar restart" "[[ $? == 0 && \$(migrate_count) == 1 ]]"
done
migrate_ship lib/install/migrate.sh home/hypr/cfg
check "migration code without a bar change runs the step once, with the bar up" "[[ $? == 0 && \$(migrate_count) == 1 ]] && logged 'migrate bar up' && ! logged 'migrate bar down' && ! logged 'restart-bar stop'"
migrate_ship home/quickshell/bar lib/install/stow.sh home/hypr/cfg
check "a merge touching none of those paths skips the step" "[[ $? == 0 ]] && ! grep -q 'migrate' '$SHIP_LOG' && ! grep -q 'install migrations' '$e2e/out'"
STUB_MIGRATE_STATUS=1 migrate_ship lib/install/migrate.sh home/quickshell/bar
check "a failing migration fails the ship" "[[ $? != 0 ]] && grep -q 'migrating failed' '$e2e/out'"
check "before the restart, so the bar is left alone and no check of main starts" "! logged 'restart-bar stop' && ! grep -q '^just check' '$SHIP_LOG'"
check "and leaves the base recorded, so a rerun resumes" "[[ -e \$(base_file '$e2e/main') ]]"
check "the lock is free" "flock -n '$SHIP_LOCK' true"
STUB_MIGRATE_STATUS=1 migrate_ship lib/install/migrate.sh
check "a failure with no bar restart fails too" "[[ $? != 0 ]] && grep -q 'migrating failed' '$e2e/out'"
STUB_MIGRATE_STATUS=1 STUB_MIGRATE_ONLY_DOWN=1 migrate_ship lib/install/migrate.sh home/quickshell/bar
check "a failure with the old bar stopped relaunches the bar first, then fails" "[[ $? != 0 ]] && grep -q 'the bar was restarted' '$e2e/out' && ((\$(line_of 'migrate bar down') < \$(start_line)))"
check "and keeps the base so a rerun resumes" "[[ -e \$(base_file '$e2e/main') ]]"
check "the bar is stopped, migrated and started through the shared script, without the ship lock's descriptor" "migrate_ship lib/install/migrate.sh home/quickshell/bar && ! logged 'restart-bar fd9 leaked' && logged 'restart-bar stop' && logged 'restart-bar start' && grep -q 'restarted the stowed bar' '$e2e/out'"
STUB_BAR_STOP_STATUS=1 migrate_ship lib/install/migrate.sh home/quickshell/bar
stop_rc=$?
check "a bar that will not stop fails the ship, with nothing migrated again or started" "[[ $stop_rc != 0 && \$(migrate_count) == 1 ]] && ! logged 'migrate bar down' && ! logged 'restart-bar start' && grep -q 'the old bar did not stop' '$e2e/out'"
check "and keeps the base so a rerun resumes, and frees the lock" "[[ -e \$(base_file '$e2e/main') ]] && flock -n '$SHIP_LOCK' true"
STUB_BAR_START_STATUS=1 migrate_ship lib/install/migrate.sh home/quickshell/bar
start_rc=$?
check "a bar that does not start fails the ship and keeps the base" "[[ $start_rc != 0 ]] && grep -q 'the bar did not start' '$e2e/out' && ! grep -q 'restarted the stowed bar' '$e2e/out' && [[ -e \$(base_file '$e2e/main') ]]"

echo "== a merge that touches the voxcmd crate rebuilds the installed voxcmd"
build_count() { grep -c '^just voxcmd-build' "$SHIP_LOG"; }
migrate_ship home/voxcmd/src/paths.rs
check "a source edit runs just voxcmd-build, under the lock" "[[ $? == 0 && \$(build_count) == 1 ]] && logged 'just voxcmd-build held' && grep -q 'ran just voxcmd-build' '$e2e/out'"
check "without the ship lock's descriptor" "! logged 'just fd9 leaked'"
for path in home/voxcmd/Cargo.toml home/voxcmd/Cargo.lock; do
  migrate_ship "$path"
  check "$path runs it too" "[[ $? == 0 && \$(build_count) == 1 ]]"
done
for path in home/voxcmd/tests/run.sh home/voxcmd/.config/voxcmd/integrations/timers.sh home/voxcmd/.local/bin/voxcmd-wake home/voxcmdish/src/x.rs home/voxcmdish/src/y.rs; do
  migrate_ship "$path"
  check "$path does not" "[[ $? == 0 && \$(build_count) == 0 ]]"
done
e2e_setup
echo changed >"$e2e/wt-1/README.md"
g -C "$e2e/wt-1" add -A
g -C "$e2e/wt-1" commit -q -m docs
env XDG_RUNTIME_DIR="$owner_run" HOME="$fake_home" PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1
check "a merge touching no crate builds nothing" "[[ \$(build_count) == 0 ]] && ! grep -q 'voxcmd-build' '$e2e/out'"
env XDG_RUNTIME_DIR="$owner_run" HOME="$fake_home" PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" >"$e2e/out" 2>&1
check "a run with nothing merged builds nothing" "[[ \$(build_count) == 0 ]]"
STUB_VOXCMD_BUILD_STATUS=1 migrate_ship home/voxcmd/src/paths.rs
build_rc=$?
check "a failing build does not fail the merge" "[[ $build_rc == 0 ]] && grep -q 'merge ' '$SHIP_LOG'"
check "it warns loudly with the command to rerun" "grep -q 'WARNING: just voxcmd-build failed' '$e2e/out' && grep -q 'run: just voxcmd-build' '$e2e/out'"
check "and sends a critical notification" "grep -q 'notify-send --urgency=critical.*just voxcmd-build failed' '$SHIP_LOG'"
check "the rest of the run still happens: base settled, lock free" "[[ ! -e \$(base_file '$e2e/main') ]] && flock -n '$SHIP_LOCK' true"
# stow -R removes ~/.local/bin/voxcmd when the merge deleted its package file, so a failed build would leave no voxcmd.
mkdir -p "$fake_home/.local/bin" "$fake_home/rs/bin"
printf '#!/bin/sh\n' >"$fake_home/rs/bin/voxcmd"
chmod +x "$fake_home/rs/bin/voxcmd"
rm -f "$fake_home/.local/bin/voxcmd"
ln -s "$fake_home/rs/bin/voxcmd" "$fake_home/.local/bin/voxcmd-rs"
STUB_VOXCMD_BUILD_STATUS=1 migrate_ship home/voxcmd/src/paths.rs
check "a failed build with no voxcmd left links it to the existing voxcmd-rs build" "[[ \$(readlink -f '$fake_home/.local/bin/voxcmd') == '$fake_home/rs/bin/voxcmd' ]]"
check "and the warning says voxcmd was relinked to the previous build" "grep -q 'WARNING: just voxcmd-build failed' '$e2e/out' && grep -q 'linked ~/.local/bin/voxcmd to the previous build' '$e2e/out'"
rm -f "$fake_home/.local/bin/voxcmd" "$fake_home/.local/bin/voxcmd-rs"
STUB_VOXCMD_BUILD_STATUS=1 migrate_ship home/voxcmd/src/paths.rs
check "a failed build with no previous build to link still only warns" "[[ ! -e '$fake_home/.local/bin/voxcmd' ]] && grep -q 'WARNING: just voxcmd-build failed' '$e2e/out' && grep -q 'voice control has no voxcmd' '$e2e/out'"
ln -s "$fake_home/rs/bin/voxcmd" "$fake_home/.local/bin/voxcmd"
ln -s "$fake_home/rs/bin/voxcmd" "$fake_home/.local/bin/voxcmd-rs"
printf '#!/bin/sh\n' >"$fake_home/rs/other"
STUB_VOXCMD_BUILD_STATUS=1 migrate_ship home/voxcmd/src/paths.rs
check "a failed build leaves a working voxcmd link alone" "[[ \$(readlink '$fake_home/.local/bin/voxcmd') == '$fake_home/rs/bin/voxcmd' ]] && ! grep -q 'linked ~/.local/bin/voxcmd' '$e2e/out'"
rm -f "$fake_home/.local/bin/voxcmd" "$fake_home/.local/bin/voxcmd-rs" "$fake_home/rs/other"

echo "== the bar restart reads the lock state"
# The stub qs-ipc answers with line N of $e2e/answers on its Nth call and repeats the last line after that. ship-batch
# waits a second between calls, so the case that never settles takes the whole 15 s budget.
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\nn=$(cat "%s/calls" 2>/dev/null || echo 0)\nn=$((n+1))\necho $n >"%s/calls"\nsed -n "${n}p" "%s/answers" | grep . || tail -n1 "%s/answers"\n' "$e2e" "$e2e" "$e2e" "$e2e" >"$fake_home/.config/hypr/scripts/qs-ipc"
# shellcheck disable=SC2329 # called by the checks below
answers_ship() {
  rm -f "$e2e/calls"
  printf '%s\n' "$@" >"$e2e/answers"
  migrate_ship home/quickshell/bar
}
answers_ship "Not ready to accept queries yet." weird unlocked
check "an odd answer, then unlocked, restarts the bar" "[[ $? == 0 ]] && logged 'restart-bar stop' && [[ \$(<$e2e/calls) == 3 ]]"
answers_ship secure
check "secure skips the restart and prints the answer" "[[ $? != 0 ]] && ! logged 'restart-bar stop' && grep -q \"screen is locked (lock state 'secure')\" '$e2e/out'"
answers_ship pending secure
check "pending is retried, then secure skips" "[[ $? != 0 ]] && ! logged 'restart-bar stop' && grep -q \"lock state 'secure'\" '$e2e/out' && [[ \$(<$e2e/calls) == 2 ]]"
answers_ship pending unlocked
check "pending is retried, then unlocked restarts" "[[ $? == 0 ]] && logged 'restart-bar stop' && [[ \$(<$e2e/calls) == 2 ]]"
answers_ship weird
check "an odd answer that never settles gives up after the budget, naming the last answer" "[[ $? != 0 ]] && ! logged 'restart-bar stop' && grep -q \"never settled (last answer 'weird')\" '$e2e/out' && [[ \$(<$e2e/calls) == 15 ]]"
printf '#!/bin/sh\necho secure\n' >"$fake_home/.config/hypr/scripts/qs-ipc"

echo "== a batch run from a worktree the merge removes"
e2e_setup
touch "$e2e/merge_removes_wt"
(cd "$e2e" && HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/wt-1/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1)
check "still finishes the batch" "[[ $? == 0 ]] && [[ ! -e $e2e/wt-1 ]] || { cat '$e2e/out'; false; }"

echo "== flags go before the PR numbers"
e2e_setup
ship 1 --skip-review-gate
check "a flag after a PR number is refused" "[[ \$? != 0 ]]"
check "the refusal names the flag and says flags go first" "grep -q -e '--skip-review-gate came after a PR number, flags go first' '$e2e/out'"
check "nothing was gated or merged" "[[ ! -s $SHIP_LOG ]]"
check "the flag was not taken for a PR" "! grep -q 'cannot read PR' '$e2e/out'"
e2e_setup
ship --skip-review-gate 1
check "leading flags still parse" "[[ \$? == 0 ]] || { cat '$e2e/out'; false; }"
check "the reviewer states were skipped by request" "grep -q 'reviewer states skipped by request' '$e2e/out' && ! grep -q -e '--wait-review' '$SHIP_LOG'"
check "the merge got the flag and the PR" "grep -q '^merge --skip-review-gate 1 ' '$SHIP_LOG'"

echo "$pass passed, $fail failed"
((fail == 0))
