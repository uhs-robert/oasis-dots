#!/usr/bin/env bash
# Status lines: running test bars and whether the installed greeter differs from the repo.
set -uo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
bars_dir="$HOME/.cache/dotfiles/test-bars"

running=$(pgrep -af '^qs -n' | sed -n 's/.* -p \([^ ]*\).*/\1/p' | head -1)
echo "qs: ${running:-stowed bar}"
# "branch STATE #n" per PR, newest first, so a branch reused for a later PR reads as its latest one.
pr_states=$(gh pr list --state all --limit 300 --json number,state,headRefName \
  --jq '.[] | "\(.headRefName) \(.state) #\(.number)"' 2>/dev/null) || pr_states=""
for bar in "$bars_dir"/*/; do
  [[ -d $bar ]] || continue
  name=$(basename "$bar")
  mark=""
  [[ -n $running && $running == "${bar%/}"* ]] && mark=" (running)"
  notes=()
  open=0
  while IFS= read -r branch; do
    [[ -n $branch ]] || continue
    pr=$(awk -v b="$branch" '$1 == b { print $3 " " $2; exit }' <<<"$pr_states")
    [[ $pr == *OPEN || -z $pr ]] && open=1
    notes+=("$branch: ${pr:-no PR}")
  done <"${bar%/}.branches" 2>/dev/null
  line="test bar: $name$mark"
  if ((${#notes[@]})); then
    joined=$(printf ', %s' "${notes[@]}")
    line+=" [${joined:2}]"
  fi
  # Every branch merged or closed: nothing left to test on it.
  ((${#notes[@]} && !open)) && [[ -n $pr_states ]] && line+=" -> stale; run: .claude/skills/test-bar/test-bar.sh remove $name"
  echo "$line"
done

dest=/etc/greetd/quickshell
if [[ ! -d $dest ]] || ! command -v jq >/dev/null; then
  echo "greeter: unknown"
  exit 0
fi
scratch=$(mktemp -d) || exit 0
trap 'rm -rf "$scratch"' EXIT
# shellcheck disable=SC2016
if ! timeout 2 bash -c 'source "$1"; stage_greeter "$2" "$3" >/dev/null' _ "$repo/lib/greeter.sh" "$scratch/stage" "$repo" 2>/dev/null; then
  echo "greeter: unknown"
  exit 0
fi
diffs=$(diff -rq "$scratch/stage" "$dest" 2>&1)
if [[ -z $diffs ]]; then
  echo "greeter: up to date"
else
  echo "greeter: differs ($(wc -l <<<"$diffs") files); run: just greeter-sync --install"
fi
