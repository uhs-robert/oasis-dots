#!/usr/bin/env bash
# Merge PRs in the given order, retargeting stacked PRs off each head branch first so its deletion cannot close them.
set -euo pipefail

die() {
  echo "merge-prs: $*" >&2
  exit 1
}

(($# > 0)) || die "usage: merge-prs.sh <pr>..."
default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)

for pr in "$@"; do
  head=$(gh pr view "$pr" --json headRefName --jq .headRefName)
  while read -r child; do
    [[ -n $child ]] || continue
    gh pr edit "$child" --base "$default" >/dev/null
    echo "$child retargeted from $head to $default"
  done < <(gh pr list --base "$head" --state open --json number --jq '.[].number')
  gh pr merge "$pr" --merge --delete-branch
  state=$(gh pr view "$pr" --json state --jq .state)
  echo "$pr $state"
  [[ $state == MERGED ]] || die "$pr is $state, stopping"
done
