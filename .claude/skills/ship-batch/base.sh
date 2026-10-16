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
      return 1
    }
  fi
  printf 'pid %s, since %s, merging %s\n' "$$" "$(date +%H:%M:%S)" "${merging:-no PRs}" >"$lock"
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

# Prints the stow packages under home/ that gained, lost or renamed a file between two commits and are installed here.
# Pulling updates the files behind existing links, but a new file in a folder stow did not fold has no link until the
# package is restowed (a merged unit or script then silently does not exist), and a deleted one leaves a dead link.
# A package counts as installed when one of its files, before or after the merge, is reached through its link in $HOME
# (a link to a file the merge removed still resolves to that path); a package never stowed here is left alone.
packages_to_restow() {
  local repo=$1 before=$2 after=$3 package relative
  while IFS= read -r package; do
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

# Prints an extended regex for the Quickshell paths the greeter stages (lib/greeter-files.sh of the repo at $1), under
# the config dir $2: a directory entry matches as a prefix, a file or glob entry exactly.
greeter_qs_regex() {
  local entry pattern alternatives=()
  # shellcheck source=/dev/null
  source "$1/lib/greeter-files.sh"
  for entry in "${GREETER_QS_FILES[@]}"; do
    entry=${entry%'?'}
    pattern=$(sed 's/[.]/\\./g; s/[*]/[^\/]*/g' <<<"$entry")
    [[ $entry == */ ]] || pattern+='$'
    alternatives+=("$pattern")
  done
  printf '%s/(%s)' "$2" "$(IFS='|' && echo "${alternatives[*]}")"
}
