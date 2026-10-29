#!/usr/bin/env bash
# Usage: rebase-branch.sh <branch>
# Rebases a PR branch onto origin's default branch and pushes it with --force-with-lease. It is the one force-push agents
# may make: the owner's settings deny `git push --force` (which also catches --force-with-lease, by prefix), and an
# allow rule names this script. A rebase keeps a PR's history to its own commits, so the review gate in merge-prs.sh
# sees only the fixes since Codex's review.
# Refuses the default branch, a branch with no open PR, a branch whose remote copy has commits the local one lacks
# (the lease would overwrite them), and a worktree with local changes. A conflicting rebase is aborted and nothing pushed.
set -euo pipefail

die() {
  echo "rebase-branch: $*" >&2
  exit 1
}

(($# == 1)) || die "usage: rebase-branch.sh <branch>"
branch=$1
git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"
default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
default=${default#origin/}
default=${default:-main}
[[ $branch != "$default" && $branch != HEAD ]] || die "refusing to rewrite $branch"
git show-ref -q --verify "refs/heads/$branch" || die "no local branch $branch"
pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty') || die "cannot list the PRs of $branch"
[[ -n $pr ]] || die "$branch has no open PR"

git fetch -q origin "$default" "$branch" || die "cannot fetch $default and $branch from origin"
remote=$(git rev-parse -q --verify "refs/remotes/origin/$branch") || die "$branch is not on origin"
git merge-base --is-ancestor "$remote" "refs/heads/$branch" ||
  die "origin/$branch has commits the local branch lacks; bring them in first"
if git merge-base --is-ancestor "origin/$default" "refs/heads/$branch"; then
  echo "rebase-branch: $branch (#$pr) already contains origin/$default; nothing pushed"
  exit 0
fi

# A branch can be checked out in one worktree only, so one that has a worktree is rebased there.
dir=$(git worktree list --porcelain | awk -v ref="branch refs/heads/$branch" '/^worktree /{w = substr($0, 10)} $0 == ref {print w}')
if [[ -n $dir ]]; then
  [[ -z $(git -C "$dir" status --porcelain --untracked-files=no) ]] || die "$dir has local changes; commit or stash them first"
else
  tmp=$(mktemp -d)
  trap 'git worktree remove --force "$tmp/wt" 2>/dev/null; rm -rf "$tmp"' EXIT
  git worktree add -q "$tmp/wt" "$branch"
  dir=$tmp/wt
fi

if ! git -C "$dir" rebase -q "origin/$default" >/dev/null 2>&1; then
  git -C "$dir" rebase --abort
  die "$branch conflicts with origin/$default; nothing pushed, rebase it by hand"
fi
git -C "$dir" push -q --force-with-lease="$branch:$remote" origin "$branch"
echo "rebase-branch: $branch (#$pr) rebased onto origin/$default and pushed"
