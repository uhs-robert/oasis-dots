#!/usr/bin/env bash
# Sourced by ship-batch.sh and its tests: the commit the post-merge check is measured from.

base_file() {
  echo "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/ship-batch-base"
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
