#!/usr/bin/env bash
# Sourced by ship-batch.sh and its tests: the commit the post-merge check is measured from, and the stow packages a
# merge left out of date.

base_file() {
  echo "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/ship-batch-base"
}

# One batch at a time per repository: a second run would resume from the first one's base and the first would delete it.
# The lock lives on fd 9 until the process exits, so it also covers merge-prs and the checks it spawns.
take_lock() {
  local lock
  lock="$(dirname "$(base_file "$1")")/ship-batch.lock"
  exec 9>"$lock"
  flock -n 9
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
