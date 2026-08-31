#!/bin/sh
set -eu

# `git diff --check` only inspects uncommitted changes, so it passes trivially on
# a clean checkout. Scan the tracked files this repository owns instead; the rest
# of home/ is vendored upstream and is not ours to reformat.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

cd "$repo_dir" || exit 1

# git grep exits 1 when nothing matches and >1 on a real failure, so the two
# cases have to be told apart or an error would read as a clean scan.
status=0
offenders=$(
  git grep -nIE '[[:blank:]]+$' -- \
    install.sh \
    uninstall.sh \
    justfile \
    lib \
    packages \
    home/hypr/.config/hypr
) || status=$?

if [ "$status" -gt 1 ]; then
  echo "Failed to scan for trailing whitespace (git grep exit $status)" >&2
  exit 1
fi

if [ -n "$offenders" ]; then
  printf 'Trailing whitespace:\n%s\n' "$offenders" >&2
  exit 1
fi
