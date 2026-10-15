#!/usr/bin/env bash
# Usage: overlap.sh <path>...; run from anywhere in the repo. Prints every other worktree and open PR whose changes
# touch one of the paths (a file, or a directory as a prefix), so a plan can be checked against work already in flight.
# Read-only; exits 0 whether or not anything overlaps.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0

(($#)) || {
  echo "usage: overlap.sh <path>..." >&2
  exit 2
}
top=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "overlap: not inside a git repository" >&2
  exit 2
}
# Paths are taken relative to the current directory, like git's own pathspecs, and compared repo-relative; "."
# at the top is the whole repo.
wanted=()
for path in "$@"; do
  wanted+=("$(realpath -m --relative-to="$top" "$path")")
done

default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
default=${default#origin/}
base="origin/${default:-main}"

# Prints the files on stdin that are one of the wanted paths or under one.
matching() {
  local file path
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    for path in "${wanted[@]}"; do
      if [[ $path == . || $file == "$path" || $file == "$path"/* ]]; then
        echo "$file"
        break
      fi
    done
  done | sort -u
}

# report <label> <files>: prints the label and the files, when there are any. Runs in the main shell, not a pipeline,
# so it can record that something overlapped.
report() {
  [[ -n $2 ]] || return 0
  local -a files
  mapfile -t files <<<"$2"
  found=1
  echo "$1"
  printf '  %s\n' "${files[@]}"
}

found=0
here=$(git rev-parse --show-toplevel)
seen_branches=" "
while IFS=$'\t' read -r path branch; do
  [[ $path != "$here" ]] || continue
  seen_branches+="$branch "
  # Committed work since the branch left the default branch, plus anything not committed yet: another session's
  # change is usually uncommitted while it is being built.
  report "worktree $path (${branch:-detached})" "$({
    git -C "$path" diff --name-only "$base...HEAD" 2>/dev/null
    git -C "$path" diff --name-only HEAD 2>/dev/null
    git -C "$path" ls-files --others --exclude-standard 2>/dev/null
  } | matching)"
done < <(git worktree list --porcelain | awk '
  /^worktree / { if (path != "") print path "\t" branch; path = substr($0, 10); branch = "" }
  /^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
  END { if (path != "") print path "\t" branch }')

if prs=$(gh pr list --state open --limit 100 --json number,title,headRefName,files \
  --jq '.[] | [.number, .headRefName, .title, ([.files[].path] | join(" "))] | @tsv' 2>/dev/null); then
  while IFS=$'\t' read -r number branch title files; do
    [[ -n $number ]] || continue
    also=""
    [[ $seen_branches != *" $branch "* ]] || also=", also a worktree above"
    report "PR #$number $title [$branch]$also" "$(tr ' ' '\n' <<<"$files" | matching)"
  done <<<"$prs"
else
  echo "overlap: gh unavailable, open PRs not checked" >&2
fi

((found)) || echo "no overlap: no other worktree or open PR touches ${wanted[*]}"
