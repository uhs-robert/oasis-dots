#!/usr/bin/env bash
# Status lines: running test bars and whether the installed greeter differs from the repo.
set -uo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
bars_dir="$HOME/.cache/dotfiles/test-bars"

running=$(pgrep -af '^qs -n' | sed -n 's/.* -p \([^ ]*\).*/\1/p' | head -1)
echo "qs: ${running:-stowed bar}"
for bar in "$bars_dir"/*/; do
  [[ -d $bar ]] || continue
  name=$(basename "$bar")
  mark=""
  [[ -n $running && $running == "${bar%/}"* ]] && mark=" (running)"
  echo "test bar: $name$mark"
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
