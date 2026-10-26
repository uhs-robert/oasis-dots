#!/usr/bin/env bash
# Runs act_global.lua, the check that the global window, workspace and media keys keep their keys, labels, flags and
# effects now that they are actions. It runs from a temp dir and fails if the repo's `git status` differs afterwards.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

# Compared with the state before, not with empty: a checkout being edited is not clean, and a check run's is.
before=$(git -C "$repo" status --porcelain)
status=0
lua "$here/act_global.lua" || status=1
if [[ $(git -C "$repo" status --porcelain) != "$before" ]]; then
  echo "FAIL the test changed the repo" >&2
  status=1
fi
exit "$status"
