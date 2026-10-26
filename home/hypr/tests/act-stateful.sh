#!/usr/bin/env bash
# Runs act_stateful.lua, the check that the Windows, Cursor, Quick Click, Groups, Move, Resize and Delete rows keep
# their keys, labels, flags and effects now that they name actions, and that the state those actions share holds up. It runs from a temp dir and fails if the repo's `git status` differs afterwards.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

# The menus name the user's shell in their commands.
export SHELL=/bin/zsh
# Selection.toggle() loads the theme module, which reads and writes the theme state file. A HOME under the temp dir keeps
# that off the user's files; the file is seeded so the module takes its restore branch and the recorded effects do not
# carry the random temp path (its first-run branch records a mkdir of it).
export HOME="$work/home"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$XDG_STATE_HOME/hypr"
echo oasis_moonlight >"$XDG_STATE_HOME/hypr/theme"
# Compared with the state before, not with empty: a checkout being edited is not clean, and a check run's is.
before=$(git -C "$repo" status --porcelain)
status=0
lua "$here/act_stateful.lua" || status=1
if [[ $(git -C "$repo" status --porcelain) != "$before" ]]; then
  echo "FAIL the test changed the repo" >&2
  status=1
fi
exit "$status"
