#!/usr/bin/env bash
# Stages the greeter from bash and from zsh with the user's state isolated and requires identical trees: zsh does not
# expand an unquoted glob or ${var^}, has no mapfile or BASH_SOURCE, and treats a bare VERSION? as a glob.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

export HOME=$scratch/home XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CONFIG_HOME=$scratch/config
export HYPR_MACHINES_DIR=$scratch/machines GREETER_USER=tester DOTFILES_DIR=$repo_dir
mkdir -p "$HOME" "$HYPR_MACHINES_DIR"

# shellcheck disable=SC2016 # expanded by the child shell
stage='source "$DOTFILES_DIR/lib/install/load.sh" && stage_greeter "$1" "$DOTFILES_DIR"'
bash -c "$stage" _ "$scratch/bash" >"$scratch/bash.out" 2>&1 || {
  cat "$scratch/bash.out" >&2
  echo "FAIL: bash staging failed" >&2
  exit 1
}
zsh -c "$stage" _ "$scratch/zsh" >"$scratch/zsh.out" 2>&1 || {
  cat "$scratch/zsh.out" >&2
  echo "FAIL: zsh staging failed" >&2
  exit 1
}
[[ -n $(ls "$scratch/zsh/assets/fonts/"*.ttf 2>/dev/null) ]] || {
  echo "FAIL: zsh staged no fonts" >&2
  exit 1
}
if ! diff -r "$scratch/bash" "$scratch/zsh" >&2 || ! diff "$scratch/bash.out" "$scratch/zsh.out" >&2; then
  echo "FAIL: bash and zsh staged different trees" >&2
  exit 1
fi
echo "greeter zsh staging: ok"
