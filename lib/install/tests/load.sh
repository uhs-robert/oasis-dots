#!/usr/bin/env bash
# Tests that sourcing the install libraries prints nothing and never exits, so any caller can load them.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
failures=0

# Sources $3 in a clean environment after `set $2`; fails when it prints or exits, even with status 0.
# $4 is sourced first, if given.
expect_silent() {
  local name=$1 flags=$2 file=$3 first=${4:-} out status
  # shellcheck disable=SC2016  # $SET_ARGS and the positionals expand in the child shell
  out=$(env -i PATH="$PATH" HOME="$HOME" DOTFILES_DIR="$repo_dir" SET_ARGS="$flags" \
    bash -c 'set $SET_ARGS; [[ -z $2 ]] || source "$2"; source "$1"; echo sourced' _ "$file" "$first" 2>&1)
  status=$?
  if [[ $status -ne 0 ]]; then
    printf 'FAIL %s exited %s: %s\n' "$name" "$status" "$out" >&2
    failures=$((failures + 1))
  fi
  if [[ $status -eq 0 && $out != *sourced ]]; then
    printf 'FAIL %s exited before the end of sourcing\n' "$name" >&2
    failures=$((failures + 1))
  fi
  out=${out%sourced}
  if [[ -n $out ]]; then
    printf 'FAIL %s printed: %s\n' "$name" "$out" >&2
    failures=$((failures + 1))
  fi
}

# Each file alone with only output.sh before it, the least a caller could have loaded.
for file in "$repo_dir"/lib/install/*.sh; do
  [[ $file == */load.sh ]] && continue
  expect_silent "${file#"$repo_dir"/}" -u "$file" "$repo_dir/lib/common/output.sh"
done

expect_silent lib/install/load.sh '-euo pipefail' "$repo_dir/lib/install/load.sh"

[[ $failures -eq 0 ]] || exit 1
echo "load: ok"
