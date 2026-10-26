#!/usr/bin/env bash
# Sourced by ship-batch.sh and its tests: the commit the post-merge check is measured from, and the stow packages a
# merge left out of date.

base_file() {
  echo "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/ship-batch-base"
}

# One batch at a time per repository works on the main checkout: the merge, the pull and the reloads after them. A
# second run waits for the first, up to SHIP_BATCH_LOCK_WAIT seconds (default 900), naming it. The lock lives on fd 9
# until release_lock or exit, so it also covers merge-prs and the reloads it spawns.
take_lock() {
  local repo=$1 merging=$2 lock holder wait_s=${SHIP_BATCH_LOCK_WAIT:-900}
  lock="$(dirname "$(base_file "$repo")")/ship-batch.lock"
  # Opened read-write, since truncating it would wipe the note naming the holder.
  exec 9<>"$lock"
  if ! flock -n 9; then
    holder=$(<"$lock")
    echo "ship-batch: another ship-batch holds the main checkout (${holder:-unknown}); waiting up to ${wait_s}s" >&2
    flock -w "$wait_s" 9 || {
      echo "ship-batch: still held after ${wait_s}s by: $(<"$lock")" >&2
      # Closed, since ship-batch's exit trap reads an open fd 9 as holding the lock.
      exec 9>&-
      return 1
    }
  fi
  printf 'pid %s, since %s, merging %s\n' "$$" "$(date +%H:%M:%S)" "${merging:-no PRs}" >"$lock"
}

# Takes the ship lock only if it is free right now; returns 1, holding nothing, when another batch has it.
try_lock() {
  local lock
  lock="$(dirname "$(base_file "$1")")/ship-batch.lock"
  exec 9<>"$lock"
  flock -n 9 || {
    exec 9>&-
    return 1
  }
  printf 'pid %s, since %s, %s\n' "$$" "$(date +%H:%M:%S)" "$2" >"$lock"
}

release_lock() {
  flock -u 9 2>/dev/null
  exec 9>&-
}

# Prints the commit to check from. A base left by an unfinished run wins over HEAD, since that run may already
# have merged and pulled, which would leave HEAD equal to the new main and nothing to check.
select_base() {
  local repo=$1 file base
  file=$(base_file "$repo")
  if [[ -s $file ]]; then
    base=$(<"$file")
    echo "ship-batch: resuming from ${base:0:12}, the last batch's check did not finish" >&2
  else
    base=$(git -C "$repo" rev-parse HEAD)
    echo "$base" >"$file"
  fi
  echo "$base"
}

# True when the recorded base is a commit of this repository that the new main descends from.
base_is_ancestor() {
  git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null && git -C "$1" merge-base --is-ancestor "$2" "$3"
}

finish_base() {
  rm -f "$(base_file "$1")"
}

# The check of main runs after the lock is released, so what it still owes is kept apart from the base above: the
# commit main was at before the oldest merge not yet checked. Written under the lock; an older debt is kept, since
# checking from it covers the newer merges too.
check_base_file() {
  echo "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/ship-batch-check-base"
}

owe_check() {
  local file
  file=$(check_base_file "$1")
  [[ -s $file ]] || echo "$2" >"$file"
}

# Prints the owed base, or nothing when no check is owed.
owed_check() {
  local file
  file=$(check_base_file "$1")
  [[ ! -s $file ]] || cat "$file"
}

settle_check() {
  rm -f "$(check_base_file "$1")"
}

# The background check of main. Its state lives beside the other ship-batch files in the git common dir: the log, the
# result of the last finished check ("pass <sha> <epoch>", "fail <sha> <epoch> <log>", or "unrecorded <sha> <epoch> <log>"
# for a pass of a main checkout whose tracked files had local changes), and the run lock that
# main-check.sh holds on fd 8 for as long as it runs (so "running" is one flock test, whether systemd or setsid started it).
# The unit is named per repository, like the state: two clones under one user (a throwaway one, say) would otherwise stop
# each other's check, each seeing its own run lock free. MAIN_CHECK_UNIT overrides it.
main_check_unit() {
  local common
  [[ -z ${MAIN_CHECK_UNIT:-} ]] || {
    echo "$MAIN_CHECK_UNIT"
    return
  }
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)
  echo "dotfiles-main-check-$(printf '%s' "$common" | sha256sum | cut -c1-8)"
}

main_check_path() {
  echo "$(dirname "$(base_file "$1")")/ship-batch-main-check.$2"
}

# One line naming the failed check, or nothing. The result is warning-only: it never stops a merge, since the PR that fixes
# main ships through ship-batch too.
main_check_failure_notice() {
  local result status sha log
  result=$(main_check_path "$1" result)
  [[ -s $result ]] || return 0
  read -r status sha _ log <"$result"
  [[ $status != fail ]] || echo "ship-batch: the check of main FAILED at ${sha:0:12}; log $log; fix it before anything else"
}

main_check_is_running() {
  ! flock -n "$(main_check_path "$1" lock)" true 2>/dev/null
}

# Stops a running background check and waits until it is gone, so nothing it spawned holds a heavy-step slot or the
# checkout when the pull changes the files under it. The owed base is not touched: only a pass settles it. Sets
# main_check_stopped when there was one to stop, since the caller then owes starting it again, and marks the check
# suspended before stopping it, so a waiter never sees it gone without the marker.
main_check_stopped=false
stop_main_check() {
  local repo=$1 lock pid
  lock=$(main_check_path "$repo" lock)
  if main_check_is_running "$repo"; then
    # shellcheck disable=SC2034 # read by ship-batch.sh
    main_check_stopped=true
    suspend_main_check "$repo"
  fi
  command -v systemctl >/dev/null && systemctl --user stop "$(main_check_unit "$repo")" 2>/dev/null
  if main_check_is_running "$repo"; then
    pid=$(cat "$(main_check_path "$repo" pid)" 2>/dev/null)
    # Every check is started as a group leader (setsid); the pid is trusted only while the run lock is held.
    [[ $pid =~ ^[0-9]+$ ]] && kill -TERM -- "-$pid" 2>/dev/null
    flock -w 60 "$lock" true || {
      [[ $pid =~ ^[0-9]+$ ]] && kill -KILL -- "-$pid" 2>/dev/null
      flock -w 30 "$lock" true || {
        echo "ship-batch: the running check of main would not stop" >&2
        return 1
      }
    }
  fi
  return 0
}

# A batch that stops the check leaves its pid in the `suspended` file: a waiter keeps waiting while that batch lives,
# instead of reading the gap before the restart as a check owed and not running (the stop before the branch checks holds no
# lock at all). Cleared when the check starts again or that batch exits. A marker counts only while its pid is a
# ship-batch, so one left by a killed batch blocks nothing, even once its pid is reused.
suspend_main_check() {
  echo $$ >"$(main_check_path "$1" suspended)"
}

# Only this batch's own marker: a batch that did not stop the check exiting must not end another's suspension.
clear_main_check_suspended() {
  local file
  file=$(main_check_path "$1" suspended)
  [[ $(cat "$file" 2>/dev/null) != "$$" ]] || rm -f "$file"
}

# Prints the pid of the batch that has the check stopped, or nothing.
main_check_suspended_by() {
  local pid
  pid=$(cat "$(main_check_path "$1" suspended)" 2>/dev/null)
  [[ $pid =~ ^[0-9]+$ && $(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) == *ship-batch.sh* ]] && echo "$pid"
}

# Starts main-check.sh run detached from this shell: a transient user unit (Nice 19, survives the agent's shell), else
# setsid. fd 9 is closed so the check cannot hold the ship lock. A unit name left over from a crash is cleared first. The
# unit gets none of this shell's environment unless passed: the session variables are what the steps and notify-send need.
# Returns once the check has taken its run lock, so a waiter that sees the ship lock free also sees the check running.
start_main_check() {
  local repo=$1 script=$2 after=$3 check_from=$4 setenv=() name unit
  # The pid file marks "has started", even for a check that has already finished again.
  rm -f "$(main_check_path "$repo" pid)" "$(main_check_path "$repo" suspended)"
  for name in PATH HOME CHECK_FULL CHECK_LOCK_WAIT_SECS WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR \
    DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK; do
    [[ -z ${!name:-} ]] || setenv+=("--setenv=$name")
  done
  if command -v systemd-run >/dev/null; then
    unit=$(main_check_unit "$repo")
    systemctl --user stop "$unit" 2>/dev/null || true
    systemctl --user reset-failed "$unit" 2>/dev/null || true
    systemd-run --user --unit="$unit" --collect --property=Nice=19 "${setenv[@]}" \
      "$script" run --notify "$after" "$check_from" 9>&- >/dev/null 2>&1 || true
    wait_main_check_running "$repo" && return 0
  fi
  setsid -f nice -n 19 "$script" run --notify "$after" "$check_from" 9>&- </dev/null >/dev/null 2>&1 || true
  wait_main_check_running "$repo" && return 0
  echo "ship-batch: the background check of main did not start; run ship-batch.sh again" >&2
  return 1
}

wait_main_check_running() {
  local _
  for _ in $(seq 50); do
    [[ -e $(main_check_path "$1" pid) ]] && return 0
    sleep 0.1
  done
  return 1
}

# Prints the stow packages under home/ that gained, lost or renamed a file between two commits and are installed here.
# Pulling updates the files behind existing links, but a new file in a folder stow did not fold has no link until the
# package is restowed (a merged unit or script then silently does not exist), and a deleted one leaves a dead link.
# A package counts as installed when one of its files, before or after the merge, is reached through its link in $HOME
# (a link to a file the merge removed still resolves to that path); a package never stowed here is left alone.
# A package the merge deleted outright is skipped with a note: stow has nothing left to restow or unstow, so its dead
# links stay for the owner to remove.
packages_to_restow() {
  local repo=$1 before=$2 after=$3 package relative
  while IFS= read -r package; do
    if [[ -z $(git -C "$repo" ls-tree --name-only "$after" -- "home/$package/") ]]; then
      echo "ship-batch: home/$package no longer exists; not restowing it (remove its dead links by hand)" >&2
      continue
    fi
    while IFS= read -r relative; do
      if [[ $(realpath -q "$HOME/$relative") == "$(realpath -q "$repo/home/$package/$relative")" ]]; then
        echo "$package"
        break
      fi
    done < <(
      for commit in "$before" "$after"; do git -C "$repo" ls-tree -r --name-only "$commit" -- "home/$package/"; done |
        sed "s|^home/$package/||" | sort -u
    )
  done < <(git -C "$repo" diff --name-only --diff-filter=ADR "$before" "$after" -- home/ | awk -F/ 'NF > 2 { print $2 }' | sort -u)
}

# Prints "voxcmd-build" when the changed paths (one per line, on stdin) touch the voxcmd crate. Its tests, TOML and
# scripts do not need a rebuild: the installed binary reads those from the checkout at run time.
crate_rebuilds() {
  ! grep -Eq '^home/voxcmd/(src/|Cargo\.(toml|lock)$)' || echo voxcmd-build
}

# Runs each `just` recipe crate_rebuilds names, in the main checkout. The merge is already done, so a failure warns
# (stderr, and a desktop notification when there is one) and never stops the run: the live binary is only stale.
rebuild_crates() {
  local repo=$1 changed=$2 recipe
  while IFS= read -r recipe; do
    if (cd "$repo" && just "$recipe") 9>&-; then
      echo "ship-batch: ran just $recipe (the merge changed its crate)"
    else
      echo "ship-batch: WARNING: just $recipe failed; the installed binary is stale. Fix it and run: just $recipe" >&2
      notify-send --urgency=critical --app-name=ship-batch "ship-batch: just $recipe failed" \
        "The merge changed its crate but the rebuild failed; run: just $recipe" 9>&- 2>/dev/null || true
    fi
  done < <(crate_rebuilds <<<"$changed")
}

# A PR whose branch has no local worktree (pushed from a cloud session) is checked in a temporary one. The caller traps
# EXIT, INT and TERM to remove_temp_worktree, so every way out of the script removes it.
temp_worktree='' temp_repo=''
add_temp_worktree() {
  local repo=$1 ref=$2
  git -C "$repo" fetch -q origin "$ref" || return 1
  temp_worktree=$(mktemp -d) || return 1
  git -C "$repo" worktree add -q --detach "$temp_worktree" FETCH_HEAD || return 1
  temp_repo=$repo
}

remove_temp_worktree() {
  [[ -z $temp_worktree ]] || {
    git -C "$temp_repo" worktree remove --force "$temp_worktree" 2>/dev/null || true
    rm -rf "$temp_worktree"
    git -C "$temp_repo" worktree prune
    temp_worktree=''
  }
}

# Checks the branch checked out in the current directory against its merge-base with origin/main. A pass on top of a base
# recorded as passed is recorded for the branch's tree, so the check of main after the merge can skip a tree that already
# passed. A bare scoped pass is never recorded: without a passed base it vouches for the changed files only.
check_branch_here() {
  local base
  base=$(git merge-base HEAD origin/main) || return 1
  lib/check.sh --changed "$base" || return 1
  # check.sh counts untracked files and lib/check/passed.sh's record does not, so a pass that saw any vouches for no tree.
  [[ -z $(git status --porcelain) ]] || return 0
  if lib/check/passed.sh passed-somewhere "$base"; then lib/check/passed.sh record || true; fi
}

# Prints an extended regex for the Quickshell paths the greeter stages (lib/common/greeter-files.sh of the repo at $1), under
# the config dir $2: a directory entry matches as a prefix, a file or glob entry exactly.
greeter_qs_regex() {
  local entry pattern alternatives=()
  # shellcheck source=/dev/null
  source "$1/lib/common/greeter-files.sh"
  for entry in "${GREETER_QS_FILES[@]}"; do
    entry=${entry%'?'}
    pattern=$(sed 's/[.]/\\./g; s/[*]/[^\/]*/g' <<<"$entry")
    [[ $entry == */ ]] || pattern+='$'
    alternatives+=("$pattern")
  done
  printf '%s/(%s)' "$2" "$(IFS='|' && echo "${alternatives[*]}")"
}
