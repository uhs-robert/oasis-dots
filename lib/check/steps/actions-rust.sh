#!/bin/sh
# Formats, lints and tests the actions Rust crate (`act` and its library): cargo fmt --check, clippy with warnings
# denied, then cargo test. Like voxcmd-rust.sh it takes no heavy-step slot and the target dir stays per-checkout.
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

cd "$repo_dir/home/actions" || exit 1
cargo fmt --check && cargo clippy --all-targets --locked -- -D warnings && cargo test --locked
