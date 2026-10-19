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
for pr; do [[ \$pr == --* ]] && continue; git push -q origin "b\$pr:main" 2>/dev/null || exit 1; done
STUB
printf '#!/bin/sh\n' >"$fake_home/.claude/skills/merge-prs/status.sh"
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\necho "b$3"\n' >"$stubs/gh"
cat >"$stubs/just" <<STUB
#!/usr/bin/env bash
echo "just \$* $lock_state" >>"\$SHIP_LOG"
exit \${STUB_JUST_STATUS:-0}
STUB
chmod +x "$stubs"/* "$fake_home"/.claude/skills/merge-prs/*

# A main checkout on main with two stacked PR branches, b1 and b2, each in a worktree of its own.
e2e_setup() {
  rm -rf "$e2e/origin.git" "$e2e/main" "$e2e"/wt-* "$SHIP_LOG"
  git init -q --bare -b main "$e2e/origin.git"
  git clone -q "$e2e/origin.git" "$e2e/main" 2>/dev/null
  mkdir -p "$e2e/main/lib/check" "$e2e/main/.claude/skills/ship-batch"
  cp "$here/../../../../lib/check/passed.sh" "$here/../../../../lib/check/passed.py" "$e2e/main/lib/check/"
  cp "$here/../ship-batch.sh" "$here/../base.sh" "$e2e/main/.claude/skills/ship-batch/"
  mkdir -p "$e2e/main/.claude/hooks"
  cp "$here/../../../hooks/live-hypr.sh" "$e2e/main/.claude/hooks/"
  cat >"$e2e/main/lib/check.sh" <<STUB
#!/usr/bin/env bash
echo "check \$(basename "\$PWD") \$* $lock_state" >>"\$SHIP_LOG"
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
ship() { HOME=$fake_home PATH="$stubs:$PATH" bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" "$@" >"$e2e/out" 2>&1; }
logged() { grep -qxF -- "$1" "$SHIP_LOG"; }
line_of() { grep -nxF -- "$1" "$SHIP_LOG" | cut -d: -f1; }

e2e_setup
ship 1 2
check "the batch succeeds" "[[ $? == 0 ]] || { cat '$e2e/out'; false; }"
check "each review is waited for outside the lock" "logged 'gate --check --wait-review --request-review 1 free' && logged 'gate --check --wait-review --request-review 2 free'"
check "each branch is checked outside the lock" "logged 'check wt-1 --changed $e2e_base free' && logged 'check wt-2 --changed $e2e_base free'"
check "the merge runs under the lock, without waiting for reviews" "logged 'merge 1 2 held'"
check "after every review and branch check" "((\$(line_of 'check wt-2 --changed $e2e_base free') < \$(line_of 'merge 1 2 held')))"
check "main is checked after the lock is released" "logged 'just check free'"
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
check "a rerun with no PRs checks main again" "[[ $? == 0 ]] && logged 'just check free'"
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
echo "hyprctl \${HYPRLAND_INSTANCE_SIGNATURE} \$*" >>"\$SHIP_LOG"
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
  env -u HYPRLAND_INSTANCE_SIGNATURE "$@" HOME="$fake_home" PATH="$stubs:$PATH" bash "$e2e/main/.claude/skills/ship-batch/ship-batch.sh" 1 >"$e2e/out" 2>&1
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
printf 'nested\n' >"$STUB_LIVE_SIGS"
hypr_ship XDG_RUNTIME_DIR="$shadow_run" OWNER_RUNTIME_DIR="$owner_run"
check "with only a shadow answering it dies instead of using it" "[[ $? != 0 ]] && grep -q 'hyprctl cannot reach Hyprland' '$e2e/out' && ! grep -q '^hyprctl' '$SHIP_LOG'"
hypr_ship XDG_RUNTIME_DIR="$owner_run"
check "with no instance answering it dies with a clear message" "[[ $? != 0 ]] && grep -q 'hyprctl cannot reach Hyprland' '$e2e/out'"
printf 'live\n' >"$STUB_LIVE_SIGS"
hypr_ship XDG_RUNTIME_DIR="$owner_run" STUB_RELOAD_STATUS=4
check "a failing reload dies with a message, not a silent exit" "[[ $? != 0 ]] && grep -q 'hyprctl reload failed (exit 4)' '$e2e/out'"
rm -rf "$shadow_run"

echo "$pass passed, $fail failed"
((fail == 0))
