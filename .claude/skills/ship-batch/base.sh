#!/usr/bin/env bash
# Sourced by ship-batch.sh, post-merge.sh and their tests: the ship lock, the commit post-merge last applied, and the
# stow packages a merge left out of date.

common_dir() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir
}

# Holds the commit whose post-merge steps all succeeded. Only record_applied writes it.
applied_file() {
  echo "$(common_dir "$1")/post-merge-applied"
}

lock_file() {
  echo "$(common_dir "$1")/ship-batch.lock"
}

# One run at a time per repository works on the main checkout: a ship-batch's merge and pull, and post-merge's reloads.
# A second run waits for the first, up to SHIP_BATCH_LOCK_WAIT seconds (default 900), naming it. The lock lives on fd 9
# until release_lock or exit, so it also covers merge-prs and the reloads it spawns.
take_lock() {
  local repo=$1 merging=$2 lock holder wait_s=${SHIP_BATCH_LOCK_WAIT:-900}
  lock=$(lock_file "$repo")
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
  lock=$(lock_file "$1")
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

# Prints the commit post-merge last applied, nothing when there is no record.
applied_commit() {
  local file
  file=$(applied_file "$1")
  [[ ! -s $file ]] || cat "$file"
}

# Renamed into place so an interrupted write cannot leave a truncated sha that reads as a valid record.
record_applied() {
  local file
  file=$(applied_file "$1")
  echo "$2" >"$file.tmp" && mv "$file.tmp" "$file"
}

# True when the recorded commit is a commit of this repository that the new main descends from.
base_is_ancestor() {
  git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null && git -C "$1" merge-base --is-ancestor "$2" "$3"
}

# Prints the stow packages under home/ that gained, lost or renamed a file between two commits and are installed here.
# Pulling updates the files behind existing links, but a new file in a folder stow did not fold has no link until the
# package is restowed (a merged unit or script then silently does not exist), and a deleted one leaves a dead link.
# A package counts as installed when one of its files, before or after the merge, is reached through its link in $HOME
# (a link to a file the merge removed still resolves to that path, hence `realpath -m`: without it a path behind a dead
# link or a missing file prints nothing, so a never-stowed deleted package would match one that is installed); a package
# never stowed here is left alone.
# An installed package the merge deleted outright is skipped with a note: stow has nothing left to restow or unstow, so
# its dead links stay for the owner to remove.
packages_to_restow() {
  local repo=$1 before=$2 after=$3 package relative
  while IFS= read -r package; do
    while IFS= read -r relative; do
      if [[ $(realpath -m "$HOME/$relative") == "$(realpath -m "$repo/home/$package/$relative")" ]]; then
        if [[ -z $(git -C "$repo" ls-tree --name-only "$after" -- "home/$package/") ]]; then
          echo "ship-batch: home/$package no longer exists; not restowing it (remove its dead links by hand)" >&2
        else
          echo "$package"
        fi
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

# The restow before the rebuild removed ~/.local/bin/voxcmd when the merge deleted the package's file, so a failed build
# would leave voice control with no voxcmd at all: link the previous build (voxcmd-rs) back, or say there is none.
keep_a_voxcmd() {
  local bin=$HOME/.local/bin
  [[ ! -x $bin/voxcmd ]] || return 0
  if [[ -x $bin/voxcmd-rs ]]; then
    ln -sfn "$(readlink -f "$bin/voxcmd-rs")" "$bin/voxcmd"
    echo "ship-batch: WARNING: linked ~/.local/bin/voxcmd to the previous build; it is older than main until just voxcmd-build succeeds" >&2
  else
    echo "ship-batch: WARNING: voice control has no voxcmd and there is no previous build to link; run: just voxcmd-build" >&2
  fi
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
      [[ $recipe != voxcmd-build ]] || keep_a_voxcmd
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

# Checks the branch checked out in the current directory. This is the only check a change gets, so it must be a check of
# what main will become: a branch missing commits of origin/main is refused rather than checked.
check_branch_here() {
  # The check would run on files that are not the commit that merges.
  [[ -z $(git status --porcelain) ]] || {
    echo "ship-batch: $(git branch --show-current) worktree has uncommitted changes; commit or stash them" >&2
    return 1
  }
  git fetch -q origin main || return 1
  git merge-base --is-ancestor origin/main HEAD || {
    echo "ship-batch: the branch does not contain origin/main; rebase it with rebase-branch.sh first" >&2
    return 1
  }
  lib/check.sh --changed origin/main
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
