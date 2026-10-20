#!/usr/bin/env bash
# Base selection of ship-batch against a temp repository: no GitHub, no merge.
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

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
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

echo "== the check owed after the lock"
check "nothing is owed at first" "[[ -z \$(owed_check '$repo') ]]"
owe_check "$repo" "$first"
owe_check "$repo" "$(git -C "$repo" rev-parse main)"
check "the oldest debt is kept" "[[ \$(owed_check '$repo') == '$first' ]]"
settle_check "$repo"
check "settling clears it" "[[ -z \$(owed_check '$repo') ]]"

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

echo "== a branch with no local worktree, and recording its pass"
origin=$root/origin.git
work=$root/work
git init -q --bare -b main "$origin"
git clone -q "$origin" "$work" 2>/dev/null
mkdir -p "$work/lib/check"
cp "$here/../../../../lib/check/passed.sh" "$here/../../../../lib/check/passed.py" "$work/lib/check/"
# shellcheck disable=SC2016 # the stub expands its own variable
printf '#!/bin/sh\nexit "${STUB_CHECK_STATUS:-0}"\n' >"$work/lib/check.sh"
chmod +x "$work/lib/check.sh"
g -C "$work" add -A
g -C "$work" commit -q -m base
git -C "$work" push -q origin main 2>/dev/null
git -C "$work" fetch -q origin
base_tree=$(git -C "$work" rev-parse 'HEAD^{tree}')
g -C "$work" switch -q -c pr-branch
echo change >"$work/file"
g -C "$work" add -A
g -C "$work" commit -q -m change
branch_tree=$(git -C "$work" rev-parse 'HEAD^{tree}')
# What a forge serves for a PR whose branch was pushed from elsewhere.
git -C "$work" push -q origin pr-branch:refs/pull/7/head 2>/dev/null
passed_file=$(git -C "$work" rev-parse --path-format=absolute --git-common-dir)/claude-check-passed-trees
check "the branch tree has not passed yet" "! (cd '$work' && lib/check/passed.sh passed-somewhere HEAD)"
check "a pass on an unrecorded base is not recorded" "(cd '$work' && check_branch_here) && ! grep -sq '$branch_tree' '$passed_file'"
printf '%s no-repos\n' "$base_tree" >"$passed_file"
check "a pass on a recorded base is recorded" "(cd '$work' && check_branch_here) && grep -qx '$branch_tree no-repos' '$passed_file'"
check "a no-repos pass does not stand in for a checkout with repos/" "(mkdir -p '$work/repos/x' && cd '$work' && ! lib/check/passed.sh is-passed '$branch_tree' && lib/check/passed.sh passed-somewhere '$branch_tree'); rm -rf '$work/repos'"
check "a failing check fails the branch" "! (cd '$work' && STUB_CHECK_STATUS=1 check_branch_here)"
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

echo "== a whole batch: reviews and branch checks before the lock, the check of main after it"
# Stubs log each step with whether the ship lock was held at that moment: merge-prs (the gate under --check, the merge
# otherwise), lib/check.sh in each worktree, and just check on main.
e2e=$root/e2e
stubs=$e2e/stubs
fake_home=$e2e/home
mkdir -p "$stubs" "$fake_home/.claude/skills/merge-prs"
export SHIP_LOG=$e2e/log
# The old sections wait for the check of main; the background check has its own section at the end. The unit name is
# private to this run, so stopping it never touches the owner's real dotfiles-main-check.
export SHIP_BATCH_SYNC_CHECK=1 MAIN_CHECK_UNIT=dotfiles-main-check-test-$$
# Every run of ship-batch is bounded, so a reverted lifecycle fix fails its test instead of hanging the suite.
ship_timeout=120
# shellcheck disable=SC2016 # expanded by the stubs
lock_state='$(if flock -n "$SHIP_LOCK" true; then echo free; else echo held; fi)'
cat >"$fake_home/.claude/skills/merge-prs/merge-prs.sh" <<STUB
#!/usr/bin/env bash
if [[ \$1 == --check ]]; then
  echo "gate \$* $lock_state" >>"\$SHIP_LOG"
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
printf '#!/bin/sh\necho "b$3"\n' >"$stubs/gh"
# The slot file named in $e2e/just_hold makes `just check` take that flock and wait until the hold file is removed, as a
# heavy check step does; a second holder that cannot get the slot in 5 s logs "slot busy" (a leaked lock). Control goes
# through files, since a check started by systemd-run does not inherit this script's environment. With $e2e/just_daemon
# present it also leaves a setsid daemon behind that keeps every descriptor it inherited, and with $e2e/just_chatty that
# daemon writes a line to its stdout every 0.2 s, as a shadow's qs does. A holding check that is stopped logs whether the
# check was marked suspended by then. A check started with the ship lock's fd 9 open logs "just fd9 leaked": the lock state
# cannot show that, since ship-batch's `flock -u 9` also unlocks every inherited copy of the descriptor.
cat >"$stubs/just" <<STUB
#!/usr/bin/env bash
: "\${SHIP_LOG:=$e2e/log}" "\${SHIP_LOCK:=$e2e/main/.git/ship-batch.lock}"
echo "just \$* $lock_state" >>"\$SHIP_LOG"
[[ ! -e /proc/\$\$/fd/9 ]] || echo "just fd9 leaked" >>"\$SHIP_LOG"
[[ ! -e $e2e/just_daemon ]] || setsid -f bash -c 'exec -a $e2e/test-daemon sleep 300'
[[ ! -e $e2e/just_chatty ]] || setsid -f bash -c 'exec -a $e2e/test-daemon bash -c "while sleep 0.2; do echo daemon tick; done"'
slot=\$(cat "$e2e/just_hold" 2>/dev/null)
if [[ -n \$slot ]]; then
  exec 7>"\$slot"
  flock -w 5 7 || echo "slot busy" >>"\$SHIP_LOG"
  echo "just holding" >>"\$SHIP_LOG"
  trap 'if [[ -e $e2e/main/.git/ship-batch-main-check.suspended ]]; then echo "stopped with marker"; else echo "stopped without marker"; fi >>"\$SHIP_LOG"; exit 143' TERM
  while [[ -e $e2e/just_hold ]]; do sleep 0.2; done
fi
[[ \$1 != migrate-quickshell-state || -z \${STUB_MIGRATE_STATUS:-} ]] || exit "\$STUB_MIGRATE_STATUS"
exit \${STUB_JUST_STATUS:-0}
STUB
cat >"$stubs/notify-send" <<STUB
#!/usr/bin/env bash
: "\${SHIP_LOCK:=$e2e/main/.git/ship-batch.lock}"
echo "notify-send \$* $lock_state" >>"$e2e/log"
STUB
# With $e2e/setsid_delay present every setsid waits a second before starting its command, which widens the gap between
# starting a check and the check taking its run lock.
real_setsid=$(command -v setsid)
cat >"$stubs/setsid" <<STUB
#!/bin/sh
[ ! -e $e2e/setsid_delay ] || sleep 1
exec $real_setsid "\$@"
STUB
chmod +x "$stubs"/* "$fake_home"/.claude/skills/merge-prs/*

# A main checkout on main with two stacked PR branches, b1 and b2, each in a worktree of its own.
e2e_setup() {
  rm -rf "$e2e/origin.git" "$e2e/main" "$e2e"/wt-* "$SHIP_LOG" "$e2e/just_hold" "$e2e/just_daemon" "$e2e/just_chatty" \
    "$e2e/probe_main_check" "$e2e/branch_hold" "$e2e/setsid_delay" "$e2e/merge_hold" "$e2e/lock_hold" "$e2e/merge_removes_wt"
  git init -q --bare -b main "$e2e/origin.git"
  git clone -q "$e2e/origin.git" "$e2e/main" 2>/dev/null
  mkdir -p "$e2e/main/lib/check" "$e2e/main/.claude/skills/ship-batch"
  cp "$here/../../../../lib/check/passed.sh" "$here/../../../../lib/check/passed.py" "$e2e/main/lib/check/"
  cp "$here/../ship-batch.sh" "$here/../base.sh" "$here/../main-check.sh" "$e2e/main/.claude/skills/ship-batch/"
  mkdir -p "$e2e/main/.claude/hooks"
  cp "$here/../../../hooks/live-hypr.sh" "$e2e/main/.claude/hooks/"
  # With $e2e/probe_main_check present a check also logs whether a check of main held its run lock at that moment; with
  # $e2e/branch_hold present it waits until that file is removed.
  cat >"$e2e/main/lib/check.sh" <<STUB
#!/usr/bin/env bash
echo "check \$(basename "\$PWD") \$* $lock_state" >>"\$SHIP_LOG"
if [[ -e $e2e/probe_main_check ]]; then
  if flock -n "$e2e/main/.git/ship-batch-main-check.lock" true; then echo "main check idle" >>"\$SHIP_LOG"; else echo "main check running" >>"\$SHIP_LOG"; fi
fi
while [[ -e $e2e/branch_hold ]]; do sleep 0.2; done
exit \${STUB_BRANCH_STATUS:-0}
STUB
  chmod +x "$e2e/main/lib/check.sh"
  g -C "$e2e/main" add -A
  g -C "$e2e/main" commit -q -m base
  git -C "$e2e/main" push -q origin main 2>/dev/null
  e2e_base=$(git -C "$e2e/main" rev-parse HEAD)
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
check "each review is waited for outside the lock" "logged 'gate --check --wait-review --request-review 1 free' && logged 'gate --check --wait-review --request-review 2 free'"
check "each branch is checked outside the lock" "logged 'check wt-1 --changed $e2e_base free' && logged 'check wt-2 --changed $e2e_base free'"
check "the merge runs under the lock, without waiting for reviews" "logged 'merge 1 2 held'"
check "after every review and branch check" "((\$(line_of 'check wt-2 --changed $e2e_base free') < \$(line_of 'merge 1 2 held')))"
# The foreground check starts while the batch still holds the lock and releases it moments later; the overlap is benign.
check "main is checked, even before the batch has released the lock" "grep -Eqx 'just check (held|free)' '$SHIP_LOG'"
check "without the ship lock's descriptor" "! logged 'just fd9 leaked'"
check "main is pulled" "[[ \$(git -C '$e2e/main' rev-parse HEAD) == \$(git -C '$e2e/main' rev-parse b2) ]]"
check "nothing is left owed" "[[ -z \$(owed_check '$e2e/main') && ! -e \$(base_file '$e2e/main') ]]"
check "the lock is free" "flock -n '$SHIP_LOCK' true"

e2e_setup
STUB_GATE_FAIL=2 ship 1 2
check "a PR failing its gate fails the run" "[[ $? != 0 ]]"
check "the PRs before it still merge" "logged 'merge 1 held' && [[ \$(git -C '$e2e/main' rev-parse HEAD) == \$(git -C '$e2e/main' rev-parse b1) ]]"
check "it and the ones after it are named for a rerun" "grep -q 'PR 2 does not pass the review gate; rerun ship-batch' '$e2e/out'"
check "a branch after it is not checked" "! logged 'check wt-2 --changed $e2e_base free'"

e2e_setup
STUB_GATE_FAIL=1 ship 1 2
check "a first PR failing its gate merges nothing" "[[ $? != 0 ]] && ! grep -q '^merge' '$SHIP_LOG' && [[ ! -e \$(base_file '$e2e/main') ]]"

e2e_setup
STUB_JUST_STATUS=1 ship 1 2
check "a failing check of main fails the run" "[[ $? != 0 ]] && grep -q 'the check fails on main' '$e2e/out'"
check "and leaves the check owed from the old main" "[[ \$(owed_check '$e2e/main') == '$e2e_base' ]]"
: >"$SHIP_LOG"
ship
check "a rerun with no PRs checks main again" "[[ $? == 0 ]] && grep -Eqx 'just check (held|free)' '$SHIP_LOG' && ! logged 'just fd9 leaked'"
check "and clears the debt" "[[ -z \$(owed_check '$e2e/main') ]]"
: >"$SHIP_LOG"
ship
check "a run with nothing new and nothing owed checks nothing" "[[ $? == 0 ]] && ! grep -q check '$SHIP_LOG'"

e2e_setup
ship --skip-review-gate 1 2
check "with --skip-review-gate the batch succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "the review gate is never called" "! grep -q '^gate' '$SHIP_LOG'"
check "each branch is still checked outside the lock" "logged 'check wt-1 --changed $e2e_base free' && logged 'check wt-2 --changed $e2e_base free'"
check "the merge gets --skip-review-gate under the lock" "logged 'merge --skip-review-gate 1 2 held'"
check "each PR says its gate was skipped" "grep -q 'PR 1: review gate skipped by request' '$e2e/out' && grep -q 'PR 2: review gate skipped by request' '$e2e/out'"

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
# pgrep greps the command lines in STUB_QS_PROCS with the pattern ship-batch passes. A restart would pkill the real qs,
# so the stub qs-ipc reports a locked screen: reaching that failure shows the test-bar check let the restart proceed.
mkdir -p "$fake_home/.config/hypr/scripts" "$e2e/cache"
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\ngrep -E -- "$2" "$STUB_QS_PROCS"\n' >"$stubs/pgrep"
printf '#!/bin/sh\necho locked\n' >"$fake_home/.config/hypr/scripts/qs-ipc"
chmod +x "$stubs/pgrep" "$fake_home/.config/hypr/scripts/qs-ipc"
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
check "an unrelated qs -p instance does not block the restart" "grep -q \"lock state is 'locked'\" '$e2e/out'"
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
[ "\$1" = dispatch ] && echo qs >"\$STUB_QS_PROCS"
[ "\$1" = reload ] && exit "\${STUB_RELOAD_STATUS:-0}"
exit 0
STUB
chmod +x "$stubs/hyprctl"
export STUB_LIVE_SIGS=$e2e/live_sigs
owner_run=$e2e/owner_run
shadow_run=/tmp/shadow-$UID-shipbatchtest
rm -rf "$owner_run" "$shadow_run"
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
# Each run commits the given files on b1; the stubs log the migration step with the lock state, and the bar restart as
# pkill and the relaunch dispatch. The stub bar answers unlocked so the restart goes ahead.
printf '#!/bin/sh\necho unlocked\n' >"$fake_home/.config/hypr/scripts/qs-ipc"
printf '#!/bin/sh\necho "pkill $*" >>"$SHIP_LOG"\n: >"$STUB_QS_PROCS"\n' >"$stubs/pkill"
chmod +x "$stubs/pkill"
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
  : >"$STUB_QS_PROCS"
  env XDG_RUNTIME_DIR="$owner_run" HOME="$fake_home" PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1
}
migrate_count() { grep -cxF -- "$migrate_step" "$SHIP_LOG"; }
migrate_ship lib/install/migrate.sh home/quickshell/bar
check "a merge touching migrate.sh succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "it runs the migrations twice, under the lock" "[[ \$(migrate_count) == 2 ]]"
# shellcheck disable=SC2034 # read by the check below, through eval
read -r first_migrate last_migrate < <(grep -nxF -- "$migrate_step" "$SHIP_LOG" | cut -d: -f1 | paste -sd' ')
# shellcheck disable=SC2034 # read by the check below, through eval
read -r pkill_line < <(line_of 'pkill -x qs')
# shellcheck disable=SC2034 # read by the check below, through eval
dispatch_line=$(grep -n '^hyprctl live dispatch' "$SHIP_LOG" | cut -d: -f1)
check "once before the restart and once after" "((first_migrate < pkill_line && pkill_line < dispatch_line && dispatch_line < last_migrate))"
check "without the ship lock's descriptor" "! logged 'just fd9 leaked'"
for path in lib/install/load.sh install.sh justfile; do
  migrate_ship "$path"
  check "a merge touching $path runs them too" "[[ $? == 0 && \$(migrate_count) == 2 ]]"
done
migrate_ship home/quickshell/bar lib/install/stow.sh home/hypr/cfg
check "a merge touching none of those paths skips the step" "[[ $? == 0 ]] && ! grep -q 'migrate' '$SHIP_LOG' && ! grep -q 'install migrations' '$e2e/out'"
STUB_MIGRATE_STATUS=1 migrate_ship lib/install/migrate.sh home/quickshell/bar
check "a failing migration fails the ship" "[[ $? != 0 ]] && grep -q 'migrating failed' '$e2e/out'"
check "before the restart, so the bar is left alone and no check of main starts" "! logged 'pkill -x qs' && ! grep -q '^just check' '$SHIP_LOG'"
check "and leaves the base recorded, so a rerun resumes" "[[ -e \$(base_file '$e2e/main') ]]"
check "the lock is free" "flock -n '$SHIP_LOCK' true"
STUB_MIGRATE_STATUS=1 migrate_ship lib/install/migrate.sh
check "a failure with no bar restart fails too, after the reloads" "[[ $? != 0 ]] && grep -q 'migrating failed' '$e2e/out'"
printf '#!/bin/sh\necho locked\n' >"$fake_home/.config/hypr/scripts/qs-ipc"

echo "== the check of main in the background"
# The default path: ship-batch returns after the merge and the check runs detached. systemd-run is stubbed to fail, so the
# setsid fallback is what runs, with real processes; the one real-unit scenario is at the end. A check "takes a slot" by
# holding the flock named in just_hold until that file is removed.
unset SHIP_BATCH_SYNC_CHECK
# The stub fails after logging its arguments and whether the script among them can be found from /, where a unit starts.
cat >"$stubs/systemd-run" <<STUB
#!/usr/bin/env bash
echo "systemd-run \$*" >>"$e2e/log"
[[ ! -e /proc/\$\$/fd/9 ]] || echo "systemd-run fd9 leaked" >>"$e2e/log"
for arg; do
  if [[ \$arg == *main-check.sh ]] && (cd / && [[ -x \$arg ]]); then echo "systemd-run script found from /" >>"$e2e/log"; fi
done
exit 1
STUB
chmod +x "$stubs/systemd-run" "$stubs/notify-send"
mc=$e2e/main/.claude/skills/ship-batch/main-check.sh
slot=$e2e/slot.lock
common=$e2e/main/.git
run_lock=$common/ship-batch-main-check.lock
ship_bg() { ship "$@"; }
hold() { echo "$slot" >"$e2e/just_hold"; }
release() { rm -f "$e2e/just_hold"; }
checking() { ! flock -n "$run_lock" true 2>/dev/null; }
wait_until() {
  for _ in $(seq 100); do
    eval "$1" && return 0
    sleep 0.1
  done
  return 1
}
# The check is stopped before its slot is released: released first, a check still starting could pass and settle the debt.
stop_all() {
  pkill -f "$e2e/main/.claude/skills/ship-batch/main-check.sh" 2>/dev/null
  release
  pkill -f "$e2e/test-daemon" 2>/dev/null
  wait_until '! checking'
}

e2e_setup
hold
ship_bg 1 2
check "the batch returns while the check runs" "[[ $? == 0 ]] && checking && grep -q 'runs in the background' '$e2e/out'"
check "the merge is done and the check is owed" "[[ \$(git -C '$e2e/main' rev-parse HEAD) == \$(git -C '$e2e/main' rev-parse b2) && \$(owed_check '$e2e/main') == '$e2e_base' ]]"
check "no result before the check ends" "[[ ! -e $common/ship-batch-main-check.result ]]"
check "the background job ran just check" "wait_until \"grep -q '^just check ' '$SHIP_LOG'\""
check "with neither systemd-run nor the setsid check given the ship lock's descriptor" "wait_until \"logged 'just holding'\" && ! logged 'systemd-run fd9 leaked' && ! logged 'just fd9 leaked'"
check "the ship lock is free while it runs" "flock -n '$SHIP_LOCK' true"
check "the setsid check runs at nice 19" "[[ \$(ps -o ni= -p \$(<$common/ship-batch-main-check.pid) | tr -d ' ') == 19 ]]"
check "wait blocks while it runs" "(timeout 2 '$e2e/main/.claude/skills/ship-batch/ship-batch.sh' --wait-main-check >/dev/null 2>&1; [[ \$? == 124 ]])"
(
  HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" --wait-main-check >"$e2e/wait.out" 2>&1
  echo $? >"$e2e/wait.rc"
) &
waiter=$!
sleep 0.5
release
wait "$waiter"
check "wait returns 0 once the check passed" "[[ \$(<$e2e/wait.rc) == 0 ]]"
check "the pass is recorded in the result and the debt cleared" "[[ \$(cut -d' ' -f1-2 $common/ship-batch-main-check.result) == 'pass $(git -C "$e2e/main" rev-parse HEAD)' && -z \$(owed_check '$e2e/main') ]]"
check "the log is kept" "grep -q 'main-check: passed' $common/ship-batch-main-check.log"
check "wait with nothing owed returns 0 at once" "timeout 5 '$mc' wait >/dev/null"

echo "== a main that already passed is settled in the foreground"
owe_check "$e2e/main" "$e2e_base"
ship_bg
check "no background job for a lookup" "[[ $? == 0 ]] && ! grep -q 'runs in the background' '$e2e/out' && [[ -z \$(owed_check '$e2e/main') ]]"

echo "== a failed background check warns and does not block"
e2e_setup
STUB_JUST_STATUS=1 ship_bg 1
check "the failing check is detached too" "[[ $? == 0 ]]"
check "it ends" "wait_until '! checking'"
check "the result says fail with the log" "[[ \$(cut -d' ' -f1 $common/ship-batch-main-check.result) == fail ]] && grep -q 'ship-batch-main-check.log' $common/ship-batch-main-check.result"
check "the debt is kept" "[[ \$(owed_check '$e2e/main') == '$e2e_base' ]]"
check "the owner gets a critical alert" "grep -q 'notify-send -u critical main check failed' '$SHIP_LOG'"
check "after the ship lock is released" "grep -q '^notify-send .* free$' '$SHIP_LOG'"
check "wait exits 1 and shows the failure" "! timeout 30 '$mc' wait >'$e2e/wait.out' 2>&1 && grep -q 'FAILED' '$e2e/wait.out'"
check "the session hook prints the failure" "[[ \$(CLAUDE_PROJECT_DIR='$e2e/main' '$here/../../../hooks/report-failed-main-check.sh') == *'FAILED at'* ]]"
check "with the absolute path of main-check.sh" "[[ \$(CLAUDE_PROJECT_DIR='$e2e/main' '$here/../../../hooks/report-failed-main-check.sh') == *'$(cd "$here/.." && pwd)/main-check.sh status'* ]]"
ship_bg 2
check "the next batch still merges" "[[ \$? == 0 ]] && logged 'merge 2 held'"
check "and opens with the FAILED banner" "head -3 '$e2e/out' | grep -q 'the check of main FAILED'"
check "and closes with it" "tail -1 '$e2e/out' | grep -q 'the check of main FAILED'"
wait_until '! checking'
check "the rerun from the oldest base passes and clears the banner" "[[ \$(cut -d' ' -f1 $common/ship-batch-main-check.result) == pass && -z \$(owed_check '$e2e/main') ]]"
check "the hook is silent again" "[[ -z \$(CLAUDE_PROJECT_DIR='$e2e/main' '$here/../../../hooks/report-failed-main-check.sh') ]]"

echo "== the next batch stops a running check and restarts from the oldest owed base"
e2e_setup
hold
ship_bg 1
checking
old_pid=$(<"$common/ship-batch-main-check.pid")
wait_until "logged 'just holding'"
ship_bg 2
check "the second batch succeeds" "[[ $? == 0 ]]"
check "the first check is gone" "! kill -0 $old_pid 2>/dev/null"
check "a new check runs on the newest main" "checking && [[ \$(<$common/ship-batch-main-check.pid) != $old_pid ]] && wait_until \"grep -q 'checking $(git -C "$e2e/main" rev-parse --short=12 HEAD) from ${e2e_base:0:12}' $common/ship-batch-main-check.log\""
check "it checks from the oldest owed base" "[[ \$(owed_check '$e2e/main') == '$e2e_base' ]]"
check "the stopped check did not leave its slot held" "wait_until \"[[ \\\$(grep -c 'just holding' '$SHIP_LOG') == 2 ]]\" && ! logged 'slot busy'"
check "the stopped check recorded neither a result nor a pass" "[[ ! -e $common/ship-batch-main-check.result ]] && ! (cd '$e2e/main' && lib/check/passed.sh is-passed HEAD)"
release
wait_until '! checking'
check "the restarted check passes and settles" "[[ \$(cut -d' ' -f1 $common/ship-batch-main-check.result) == pass && -z \$(owed_check '$e2e/main') ]]"

echo "== a batch that fails after stopping the check keeps the debt"
e2e_setup
hold
ship_bg 1
checking
STUB_RELOAD_STATUS=0 STUB_GATE_FAIL=2 ship_bg 2
check "the batch merges only the ready PR and fails for the other" "[[ $? != 0 ]]"
check "the debt is still the oldest base" "[[ \$(owed_check '$e2e/main') == '$e2e_base' ]]"
stop_all
check "wait reports a check owed but not running" "! timeout 30 '$mc' wait >'$e2e/wait.out' 2>&1 && grep -q 'owed but none is running' '$e2e/wait.out'"
check "status says so" "[[ \$('$mc' status) == 'not running'* ]]"

echo "== a bar restart never meets a running check"
e2e_setup
hold
ship_bg 1
checking
mkdir -p "$e2e/wt-2/home/quickshell"
echo bar >"$e2e/wt-2/home/quickshell/bar"
g -C "$e2e/wt-2" add -A
g -C "$e2e/wt-2" commit -q -m bar
printf '#!/bin/sh\necho unlocked\n' >"$fake_home/.config/hypr/scripts/qs-ipc"
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\nif flock -n "%s" true; then echo "pkill idle" >>"%s"; else echo "pkill checking" >>"%s"; fi\n' "$run_lock" "$e2e/log" "$e2e/log" >"$stubs/pkill"
echo "qs -p /tmp/json_store_x/cfg" >"$STUB_QS_PROCS"
chmod +x "$stubs/pkill"
HOME=$fake_home PATH="$stubs:$PATH" XDG_RUNTIME_DIR="$owner_run" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 2 >"$e2e/out" 2>&1
check "the old check was stopped before the bar was killed" "logged 'pkill idle' && ! logged 'pkill checking'"
check "the new check started after the restart" "checking"
stop_all
rm -f "$stubs/pkill"
printf '#!/bin/sh\necho locked\n' >"$fake_home/.config/hypr/scripts/qs-ipc"

echo "== two batches racing to start the check"
e2e_setup
hold
ship_bg 1 &
first=$!
ship_bg &
second=$!
wait "$first" "$second"
check "exactly one check is running" "wait_until checking && [[ \$(pgrep -fc '$mc run') == 1 ]]"
check "no slot was left held by the loser" "! logged 'slot busy'"
stop_all

echo "== a second run of the same check is refused"
e2e_setup
hold
ship_bg 1
check "the lock refuses a duplicate" "! timeout 10 '$mc' run --notify HEAD HEAD >/dev/null 2>&1"
stop_all

echo "== a batch that dies after stopping the check starts it again"
e2e_setup
hold
ship_bg 1
checking
old_pid=$(<"$common/ship-batch-main-check.pid")
STUB_MERGE_FAIL=1 ship_bg 2
check "the merge failure fails the batch" "[[ $? != 0 ]] && grep -q 'merge-prs failed' '$e2e/out'"
check "and says it restarted the check it stopped" "grep -q 'restarted the check of main this run stopped' '$e2e/out'"
check "a new check runs on main from the oldest owed base" "checking && [[ \$(<$common/ship-batch-main-check.pid) != $old_pid ]] && wait_until \"grep -q 'checking $(git -C "$e2e/main" rev-parse --short=12 HEAD) from ${e2e_base:0:12}' $common/ship-batch-main-check.log\""
stop_all

echo "== branch checks run after the check of main is stopped"
e2e_setup
hold
ship_bg 1
checking
touch "$e2e/probe_main_check"
STUB_BRANCH_STATUS=1 ship_bg 2
check "the failing branch fails the batch" "[[ $? != 0 ]] && grep -q 'the check fails on b2' '$e2e/out'"
check "the branch check saw no check of main running" "logged 'main check idle' && ! logged 'main check running'"
check "the stopped check runs again" "checking && grep -q 'restarted the check of main' '$e2e/out'"
stop_all

echo "== a newer batch supersedes a foreground check"
e2e_setup
hold
(
  SHIP_BATCH_SYNC_CHECK=1 HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/sync.out" 2>&1
  echo $? >"$e2e/sync.rc"
) &
sync_batch=$!
wait_until checking
wait_until "logged 'just holding'"
HOME=$fake_home PATH="$stubs:$PATH" timeout 40 bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 2 >"$e2e/out" 2>&1
check "the newer batch stops it at once and merges" "[[ $? == 0 ]] && logged 'merge 2 held'"
check "the superseded batch exits 0" "wait_until '[[ -s $e2e/sync.rc ]]' && [[ \$(<$e2e/sync.rc) == 0 ]] || { cat '$e2e/sync.out'; false; }"
check "saying the check is superseded and still owed" "grep -q 'superseded' '$e2e/sync.out' && ! grep -q 'the check fails on main' '$e2e/sync.out'"
check "the newer batch's check runs from the oldest owed base" "checking && [[ \$(owed_check '$e2e/main') == '$e2e_base' ]]"
stop_all
wait "$sync_batch"

echo "== a daemon a step leaves behind does not keep the check running"
e2e_setup
touch "$e2e/just_daemon"
ship_bg 1
check "the daemon is up" "wait_until 'pgrep -f $e2e/test-daemon >/dev/null'"
check "the check counts as ended" "wait_until '! checking'"
check "wait returns at once" "timeout 10 '$mc' wait >/dev/null"
stop_all

echo "== wait gives up on a check that never ends"
e2e_setup
flock "$run_lock" sleep 30 &
lock_holder=$!
wait_until checking
MAIN_CHECK_WAIT_SECS=1 timeout 10 "$mc" wait >"$e2e/wait.out" 2>&1
check "after MAIN_CHECK_WAIT_SECS, with exit 1" "[[ $? == 1 ]] && grep -q 'has run for too long' '$e2e/wait.out'"
kill "$lock_holder" 2>/dev/null
wait "$lock_holder" 2>/dev/null
stop_all

echo "== the unit gets the session environment"
e2e_setup
# Run by the relative path SKILL.md documents, so a script path systemd-run cannot resolve from / shows.
(
  cd "$e2e/main" &&
    WAYLAND_DISPLAY=wl-test HYPRLAND_INSTANCE_SIGNATURE=sig-test DBUS_SESSION_BUS_ADDRESS=unix:test SSH_AUTH_SOCK=/tmp/agent-test \
      XDG_RUNTIME_DIR=$owner_run HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout \
      bash .claude/skills/ship-batch/ship-batch.sh 1 >"$e2e/out" 2>&1
)
for name in WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK; do
  check "systemd-run passes $name" "grep '^systemd-run ' '$SHIP_LOG' | grep -q -- '--setenv=$name '"
done
check "and a script path that resolves from /" "logged 'systemd-run script found from /'"
check "under the MAIN_CHECK_UNIT override" "grep '^systemd-run ' '$SHIP_LOG' | grep -q -- '--unit=$MAIN_CHECK_UNIT '"
stop_all
# Without the override each repository gets its own unit, so two clones never stop each other's check.
other_clone=$e2e/other-clone
rm -rf "$other_clone"
git clone -q "$e2e/origin.git" "$other_clone" 2>/dev/null
for clone in "$e2e/main" "$other_clone"; do
  owe_check "$clone" "$e2e_base"
  (cd "$clone" && env -u MAIN_CHECK_UNIT HOME="$fake_home" PATH="$stubs:$PATH" CHECK_FULL=1 timeout -k 5 $ship_timeout bash .claude/skills/ship-batch/ship-batch.sh >"$e2e/out" 2>&1)
  pkill -f "$clone/.claude/skills/ship-batch/main-check.sh" 2>/dev/null
  wait_until "flock -n '$clone/.git/ship-batch-main-check.lock' true"
done
# shellcheck disable=SC2034 # read by the check below, through eval
mapfile -t clone_units < <(grep -oE -- '--unit=dotfiles-main-check-[0-9a-f]{8} ' "$SHIP_LOG")
check "two clones get different default unit names" "[[ \${#clone_units[@]} == 2 && \${clone_units[0]} != \${clone_units[1]} ]]"
rm -rf "$other_clone"

echo "== a batch waiting for the lock stops a foreground check it started under the lock"
# The foreground batch pauses in its merge while the second batch queues for the lock; every setsid is a second slow, so a
# check started after the lock is released would still be starting when the second batch takes it.
e2e_setup
touch "$e2e/merge_hold" "$e2e/setsid_delay"
(
  SHIP_BATCH_SYNC_CHECK=1 HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/sync.out" 2>&1
  echo $? >"$e2e/sync.rc"
) &
sync_batch=$!
wait_until "logged 'merge 1 held'"
(
  ship_bg 2
  echo $? >"$e2e/queued.rc"
) &
queued_batch=$!
wait_until "grep -q 'another ship-batch holds the main checkout' '$e2e/out'"
rm -f "$e2e/merge_hold"
wait "$sync_batch" "$queued_batch"
check "the queued batch merges" "[[ \$(<$e2e/queued.rc) == 0 ]] && logged 'merge 2 held' || { cat '$e2e/out'; false; }"
check "the foreground batch exits 0" "[[ \$(<$e2e/sync.rc) == 0 ]] || { cat '$e2e/sync.out'; false; }"
check "and the debt is settled by a check of the newest main" "wait_until '! checking' && [[ -z \$(owed_check '$e2e/main') ]] && [[ \$(cut -d' ' -f2 $common/ship-batch-main-check.result) == \$(git -C '$e2e/main' rev-parse HEAD) ]]"
rm -f "$e2e/setsid_delay"
stop_all

echo "== wait keeps waiting while a batch has the check stopped for its branch checks"
e2e_setup
hold
ship_bg 1
checking
touch "$e2e/branch_hold"
(
  ship_bg 2
  echo $? >"$e2e/suspending.rc"
) &
suspending_batch=$!
wait_until "grep -q '^check wt-2 ' '$SHIP_LOG'"
check "the check is stopped for the branch check" "wait_until '! checking'"
check "wait blocks instead of reporting a check owed and not running" "(timeout 3 '$mc' wait >'$e2e/wait.out' 2>&1; [[ \$? == 124 ]]) || { cat '$e2e/wait.out'; false; }"
check "status names the batch" "[[ \$('$mc' status) == 'stopped while ship-batch (pid '[0-9]*') checks its branches'* ]]"
(
  timeout -k 5 60 "$mc" wait >"$e2e/wait.out" 2>&1
  echo $? >"$e2e/wait.rc"
) &
waiter=$!
sleep 1.5
rm -f "$e2e/branch_hold"
wait "$suspending_batch"
check "the batch restarts the check and clears the marker" "[[ \$(<$e2e/suspending.rc) == 0 ]] && checking && [[ ! -e $common/ship-batch-main-check.suspended ]]"
release
wait "$waiter"
check "a waiter that started during the branch check returns 0 once the check passed" "[[ \$(<$e2e/wait.rc) == 0 ]] || { cat '$e2e/wait.out'; false; }"
wait_until '! checking'
owe_check "$e2e/main" "$e2e_base"
bash -c 'echo $$' >"$common/ship-batch-main-check.suspended"
check "a marker left by a dead batch does not block wait" "! timeout 10 '$mc' wait >'$e2e/wait.out' 2>&1 && grep -q 'owed but none is running' '$e2e/wait.out'"
sleep 30 &
reused_pid=$!
echo "$reused_pid" >"$common/ship-batch-main-check.suspended"
check "nor does one whose pid now belongs to another program" "! timeout 10 '$mc' wait >'$e2e/wait.out' 2>&1 && grep -q 'owed but none is running' '$e2e/wait.out'"
kill "$reused_pid"
wait "$reused_pid" 2>/dev/null
# Named like a batch, and with a second command so bash does not exec sleep in its place.
bash -c 'sleep 30; :' ship-batch.sh &
live_holder=$!
echo "$live_holder" >"$common/ship-batch-main-check.suspended"
MAIN_CHECK_WAIT_SECS=1 timeout 10 "$mc" wait >"$e2e/wait.out" 2>&1
check "a live one blocks only up to MAIN_CHECK_WAIT_SECS" "[[ $? == 1 ]] && grep -q 'kept the check of main stopped for too long' '$e2e/wait.out'"
kill "$live_holder"
wait "$live_holder" 2>/dev/null
rm -f "$common/ship-batch-main-check.suspended"
stop_all

echo "== a daemon writing to the log does not garble the next check's log"
e2e_setup
touch "$e2e/just_chatty"
ship_bg 1
wait_until '! checking'
rm -f "$e2e/just_chatty"
sleep 1
owe_check "$e2e/main" "$e2e_base"
CHECK_FULL=1 ship_bg
check "a background check's log" "wait_until '! checking' && sleep 1 && [[ \$(tr -cd '\\0' <$common/ship-batch-main-check.log | wc -c) == 0 ]] && [[ \$(grep -m1 -v 'daemon tick' $common/ship-batch-main-check.log) == 'main-check: checking'* ]]"
owe_check "$e2e/main" "$e2e_base"
SHIP_BATCH_SYNC_CHECK=1 CHECK_FULL=1 ship_bg
check "a foreground check's log" "[[ $? == 0 ]] && sleep 1 && [[ \$(tr -cd '\\0' <$common/ship-batch-main-check.log | wc -c) == 0 ]] && [[ \$(grep -m1 -v 'daemon tick' $common/ship-batch-main-check.log) == 'main-check: checking'* ]]"
stop_all

echo "== every stop marks the check suspended before it kills it"
e2e_setup
hold
ship_bg 1
wait_until "logged 'just holding'"
ship_bg 2
check "the stop before the branch checks" "[[ $? == 0 ]] && logged 'stopped with marker' && ! logged 'stopped without marker'"
stop_all
e2e_setup
hold
ship_bg 1
wait_until "logged 'just holding'"
ship_bg
check "the stop under the lock" "[[ $? == 0 ]] && logged 'stopped with marker' && ! logged 'stopped without marker'"
stop_all

echo "== a dying batch keeps the check marked suspended until it has restarted it"
e2e_setup
hold
ship_bg 1
wait_until "logged 'just holding'"
touch "$e2e/branch_hold" "$e2e/lock_hold"
(
  STUB_BRANCH_STATUS=1 ship_bg 2
  echo $? >"$e2e/dying.rc"
) &
dying_batch=$!
wait_until "grep -q '^check wt-2 ' '$SHIP_LOG'"
flock "$SHIP_LOCK" bash -c "while [[ -e $e2e/lock_hold ]]; do sleep 0.2; done" &
lock_holder=$!
wait_until "! flock -n '$SHIP_LOCK' true"
rm -f "$e2e/branch_hold"
wait_until "grep -q 'another ship-batch holds the main checkout' '$e2e/out'"
check "status still names it while it waits for the lock" "[[ \$('$mc' status) == 'stopped while ship-batch'* ]]"
rm -f "$e2e/lock_hold"
wait "$lock_holder" "$dying_batch"
check "then it restarts the check and clears the marker" "[[ \$(<$e2e/dying.rc) != 0 ]] && checking && grep -q 'restarted the check of main' '$e2e/out' && [[ ! -e $common/ship-batch-main-check.suspended ]]"
stop_all

echo "== a batch run from a worktree the merge removes"
e2e_setup
hold
touch "$e2e/merge_removes_wt"
(cd "$e2e" && HOME=$fake_home PATH="$stubs:$PATH" timeout -k 5 $ship_timeout bash "$e2e/wt-1/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1)
check "still starts the check of main" "[[ $? == 0 ]] && [[ ! -e $e2e/wt-1 ]] && checking && grep -q 'runs in the background' '$e2e/out' || { cat '$e2e/out'; false; }"
stop_all

echo "== a batch skips the early stop while another batch holds the lock"
e2e_setup
hold
ship_bg 1
checking
touch "$e2e/probe_main_check" "$e2e/lock_hold"
flock "$SHIP_LOCK" bash -c "while [[ -e $e2e/lock_hold ]]; do sleep 0.2; done" &
lock_holder=$!
wait_until "! flock -n '$SHIP_LOCK' true"
(
  ship_bg 2
  echo $? >"$e2e/skipping.rc"
) &
skipping_batch=$!
check "its branch check runs at once, with the check of main left to the lock holder" "wait_until \"grep -q '^check wt-2 .* held$' '$SHIP_LOG'\" && logged 'main check running'"
rm -f "$e2e/lock_hold"
wait "$lock_holder" "$skipping_batch"
check "then it takes the lock, merges and restarts the check" "[[ \$(<$e2e/skipping.rc) == 0 ]] && logged 'merge 2 held' && checking"
stop_all

echo "== a pass of a main checkout with local changes settles nothing"
e2e_setup
hold
ship_bg 1
wait_until "logged 'just holding'"
echo edit >>"$e2e/main/one"
release
check "a tracked file changed during the check: it ends" "wait_until '! checking'"
check "with the debt still owed and no pass" "[[ \$(owed_check '$e2e/main') == '$e2e_base' && \$(cut -d' ' -f1 $common/ship-batch-main-check.result) == unrecorded ]]"
check "the log says why" "grep -q 'tracked files in the main checkout differ' $common/ship-batch-main-check.log"
check "wait exits 1 and names the local changes" "! timeout 30 '$mc' wait >'$e2e/wait.out' 2>&1 && grep -q 'local changes to tracked files' '$e2e/wait.out'"
SHIP_BATCH_SYNC_CHECK=1 ship_bg
check "a foreground check of it fails the run and keeps the debt" "[[ $? != 0 ]] && grep -q 'local changes to tracked files' '$e2e/out' && [[ \$(owed_check '$e2e/main') == '$e2e_base' ]]"
git -C "$e2e/main" checkout -q -- one
stop_all

echo "== a batch that gives up waiting for the lock restarts nothing without it"
e2e_setup
hold
ship_bg 1
wait_until "logged 'just holding'"
touch "$e2e/branch_hold" "$e2e/lock_hold"
(
  SHIP_BATCH_LOCK_WAIT=1 ship_bg 2
  echo $? >"$e2e/timed_out.rc"
) &
timed_out_batch=$!
wait_until "grep -q '^check wt-2 ' '$SHIP_LOG'"
flock "$SHIP_LOCK" bash -c "while [[ -e $e2e/lock_hold ]]; do sleep 0.2; done" &
lock_holder=$!
wait_until "! flock -n '$SHIP_LOCK' true"
rm -f "$e2e/branch_hold"
wait "$timed_out_batch"
check "it fails once the wait runs out" "[[ \$(<$e2e/timed_out.rc) != 0 ]] && grep -q 'gave up waiting' '$e2e/out'"
check "and starts no check while the other holder has the main checkout" "! checking && ! grep -q 'restarted the check' '$e2e/out'"
rm -f "$e2e/lock_hold"
wait "$lock_holder"
stop_all

if systemd-run --user --collect --quiet true 2>/dev/null; then
  echo "== a real transient unit, with a stale unit of the same name"
  rm -f "$stubs/systemd-run"
  e2e_setup
  hold
  systemd-run --user --unit="$MAIN_CHECK_UNIT" --collect --quiet sleep 300
  ship_bg 1
  check "the stale unit gives way to the check" "checking && systemctl --user is-active --quiet $MAIN_CHECK_UNIT && [[ \$(systemctl --user show -p ExecMainPID --value $MAIN_CHECK_UNIT) == \$(<$common/ship-batch-main-check.pid) ]]"
  check "the unit runs at nice 19" "[[ \$(ps -o ni= -p \$(<$common/ship-batch-main-check.pid) | tr -d ' ') == 19 ]]"
  ship_bg 2
  check "the next batch stops the unit and starts a fresh one" "[[ \$? == 0 ]] && checking && systemctl --user is-active --quiet $MAIN_CHECK_UNIT"
  release
  wait_until '! checking'
  check "the unit's check passes and the unit is collected" "[[ \$(cut -d' ' -f1 $common/ship-batch-main-check.result) == pass ]] && wait_until '! systemctl --user is-active --quiet $MAIN_CHECK_UNIT'"
  systemctl --user stop "$MAIN_CHECK_UNIT" 2>/dev/null
  printf '#!/bin/sh\nexit 1\n' >"$stubs/systemd-run"
fi
stop_all
echo "$pass passed, $fail failed"
((fail == 0))
