#!/usr/bin/env bash
# Feeds commands to warn-direct-voxcmd-suite.sh: a voxcmd suite or the crate's cargo test/clippy run by hand gets a
# warning naming its check step; the check itself, mentions, other crates and the escape hatches stay silent.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../warn-direct-voxcmd-suite.sh
pass=0 fail=0

# expect <warn|silent> <command> [cwd] [step the warning names]
expect() {
  local context got
  context=$(jq -n --arg c "$2" --arg d "${3:-/home/u/dotfiles}" '{tool_input: {command: $c}, cwd: $d}' | "$hook" |
    jq -r '.hookSpecificOutput.additionalContext // empty')
  got=silent
  [[ -z $context ]] || got=warn
  if [[ $got == "$1" && (-z ${4:-} || $context == *"Mapped step for this command: $4"*) ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $got: $context)"
    fail=$((fail + 1))
  fi
}

expect warn 'home/voxcmd/tests/run.sh' '' voxcmd-click
expect warn './home/voxcmd/tests/run-phrases.sh' '' voxcmd-phrases
expect warn 'bash home/voxcmd/tests/run-calendar.sh 2>&1 | tail' '' voxcmd-calendar
expect warn 'home/voxcmd/tests/sandbox.sh home/voxcmd/tests/run-wake.sh' '' voxcmd-wake
expect warn 'VOXCMD_BIN=rs home/voxcmd/tests/run-firefox-extension.sh' '' voxcmd-firefox
expect warn 'timeout 900 home/voxcmd/tests/run-sessions.sh' '' 'none of its own'
expect warn 'cd home/voxcmd && tests/run.sh' '' voxcmd-click
expect warn 'cd home/voxcmd && cargo test' '' voxcmd-rust
expect warn 'cargo clippy --manifest-path home/voxcmd/Cargo.toml --all-targets' '' voxcmd-rust
expect warn 'env RUST_LOG=1 cargo test --locked' /home/u/dotfiles/home/voxcmd voxcmd-rust
expect warn 'tests/run-phrases.sh' /home/u/dotfiles/home/voxcmd voxcmd-phrases
expect silent 'lib/check.sh --changed origin/main'
expect silent 'lib/check.sh --only voxcmd-click'
expect silent '.claude/skills/ship-batch/ship-batch.sh 12'
expect silent 'just check'
expect silent 'shellcheck home/voxcmd/tests/run.sh'
expect silent 'git diff origin/main -- home/voxcmd/tests/run.sh'
expect silent 'grep -n section home/voxcmd/tests/run-wake.sh'
expect silent 'cd home/voxcmd && cargo fmt'
expect silent 'cd home/voxcmd && cargo build'
expect silent 'cd ~/src/other && cargo test'
expect silent 'cargo test' /home/u/src/other
expect silent 'VOXCMD_ONLY_SECTIONS="wake word" home/voxcmd/tests/run-wake.sh'
expect silent 'CHECK_ALLOW_DIRECT=1 home/voxcmd/tests/run.sh'

echo "$pass passed, $fail failed"
((fail == 0))
