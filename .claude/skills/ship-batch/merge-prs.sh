#!/usr/bin/env bash
# Merge PRs in the given order, retargeting stacked PRs off each head branch first so its deletion cannot close them.
set -euo pipefail

die() {
  echo "merge-prs: $*" >&2
  exit 1
}

(($# > 0)) || die "usage: merge-prs.sh <pr>..."
default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name) || die "cannot read the default branch"

for pr in "$@"; do
  head=$(gh pr view "$pr" --json headRefName --jq .headRefName) || die "cannot read PR $pr"
  children=$(gh pr list --base "$head" --state open --json number --jq '.[].number') || die "cannot list PRs based on $head"
  for child in $children; do
    gh pr edit "$child" --base "$default" >/dev/null || die "cannot retarget $child"
    echo "$child retargeted from $head to $default"
  done
  gh pr merge "$pr" --merge --delete-branch || die "merge of $pr failed"
  state=$(gh pr view "$pr" --json state --jq .state) || die "cannot read state of $pr"
  echo "$pr $state"
  [[ $state == MERGED ]] || die "$pr is $state, stopping"
done
