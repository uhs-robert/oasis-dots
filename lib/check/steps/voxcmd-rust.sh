#!/bin/sh
# Formats, lints and tests the voxcmd Rust crate: cargo fmt --check, clippy with warnings denied, then cargo test.
# It takes no heavy-step slot (lib/check/lock.sh): it is short, its timing-sensitive tests wait on events instead of
# fixed windows, and a slot would queue it behind the minutes-long voxcmd suites and other agents' checks. It runs in
# the ordinary pool, not the serial lane. The target dir stays per-checkout: a shared one serialises worktrees on
# cargo's lock and saves little for a crate this size.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)

command -v cargo >/dev/null 2>&1 || {
  echo 'skip: cargo not installed'
  exit 0
}

# shellcheck source-path=SCRIPTDIR source=../lock.sh
. "$repo_dir/lib/check/lock.sh"
check_lower_priority

cd "$repo_dir/home/voxcmd" || exit 1
cargo fmt --check && cargo clippy --all-targets --locked -- -D warnings && cargo test --locked
