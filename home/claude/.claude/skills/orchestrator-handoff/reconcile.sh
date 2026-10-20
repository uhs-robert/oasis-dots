#!/usr/bin/env bash
# Usage: reconcile.sh <doc>...
# Compares each tracking doc's "Resume here" section with the live PRs and worktrees, printing one line per mismatch.
# Exits 1 on any mismatch, 0 when clean.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: reconcile.sh <doc>..." >&2
  exit 2
fi

# Prints the section from its heading to the next heading of the same or higher level.
resume_section() {
  awk '
    /^#+[ \t]/ {
      match($0, /^#+/)
      level = RLENGTH
      if (in_section && level <= section_level) exit
      if (!in_section && tolower($0) ~ /resume here/) {
        in_section = 1
        section_level = level
      }
    }
    in_section { print }
  ' "$1"
}

# PR numbers the section lists as open: "Open PRs: #1, #2" up to the first ";" or "(", and "#N open" or "PR #N is open".
# A clause that says DONE, MERGED or closed is skipped.
open_prs() {
  local line clause rest
  while IFS= read -r line; do
    # Splitting on ";" and "(" keeps a trailing "(#N merged; ...)" aside out of the open list.
    while IFS= read -r clause; do
      if [[ $clause =~ (DONE|MERGED|[Mm]erged|[Cc]losed|CLOSED) ]]; then continue; fi
      rest=$clause
      if [[ $rest =~ [Oo]pen\ PRs?:(.*) ]]; then
        rest=${BASH_REMATCH[1]}
        grep -oE '#[0-9]+' <<<"$rest"
      fi
      grep -oE '#[0-9]+[^#]{0,12}[ ]open\b' <<<"$clause" | grep -oE '^#[0-9]+'
    done < <(tr ';(' '\n' <<<"$line")
  done
}

# Absolute paths under /home/roberth that look like worktrees: dotfiles-* siblings and .claude/worktrees/* entries.
worktree_paths() {
  grep -oE '/home/roberth/(dotfiles-[A-Za-z0-9._-]+|dotfiles/\.claude/worktrees/[A-Za-z0-9._-]+)' | sed -E 's/[.]+$//'
}

mismatches=0
report() {
  echo "$1"
  mismatches=$((mismatches + 1))
}

listed_prs=""
listed_paths=""
for doc in "$@"; do
  if [ ! -r "$doc" ]; then
    report "doc $doc unreadable"
    continue
  fi
  section=$(resume_section "$doc")
  if [ -z "$section" ]; then
    report "doc $doc has no Resume here section"
    continue
  fi
  listed_prs+=$(open_prs <<<"$section")$'\n'
  listed_paths+=$(worktree_paths <<<"$section")$'\n'
done

while IFS= read -r number; do
  [ -n "$number" ] || continue
  state=$(gh pr view "${number#\#}" --json state --jq .state 2>/dev/null)
  case $state in
  MERGED | CLOSED) report "PR $number listed open but $state" ;;
  esac
done < <(sort -u <<<"$listed_prs")

# Porcelain blocks: "worktree <path>" then "branch refs/heads/<name>" or "detached"; the first block is the main checkout.
worktree_list=$(git worktree list --porcelain)
live_paths=""
declare -A branch_of
main_path=""
current=""
while IFS= read -r line; do
  case $line in
  "worktree "*)
    current=${line#worktree }
    [ -n "$main_path" ] || main_path=$current
    live_paths+=$current$'\n'
    branch_of[$current]="detached"
    ;;
  "branch "*) branch_of[$current]=${line#branch refs/heads/} ;;
  esac
done <<<"$worktree_list"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  grep -qxF "$path" <<<"$live_paths" || report "worktree $path listed but missing"
done < <(sort -u <<<"$listed_paths")

while IFS= read -r path; do
  [ -n "$path" ] && [ "$path" != "$main_path" ] || continue
  grep -qxF "$path" <<<"$listed_paths" || report "worktree $path (${branch_of[$path]}) exists but no doc lists it"
done <<<"$live_paths"

[ "$mismatches" -eq 0 ]
