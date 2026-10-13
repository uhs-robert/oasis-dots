#!/bin/bash
# Tests which steps `lib/check.sh --changed` picks for a change, through CHECK_PLAN_ONLY=1 so no linter runs.
# Each case edits a scratch clone of this checkout (with the working tree's lib/check*.sh on top) and reads the plan.
set -u

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

git clone -q "$repo_dir" "$scratch/clone" || exit 1
cd "$scratch/clone" || exit 1
git config user.name scope-test
git config user.email scope-test@example.invalid
cp "$repo_dir"/lib/check*.sh lib/
mkdir -p lib/tests
cp "$repo_dir"/lib/tests/check-scope.sh lib/tests/
git add -A
git commit -q --allow-empty -m 'scratch base' || exit 1

failures=0
case_name=''
plan_line=''
plan_lists=''
ran=''
skipped=''

start_case() {
  case_name=$1
  git reset -q --hard HEAD
  git clean -qfdx
}

# Runs the plan for the scratch change made so far.
plan() {
  local output
  output=$(CHECK_PLAN_ONLY=1 sh lib/check.sh --changed HEAD 2>&1)
  plan_line=$(printf '%s\n' "$output" | grep '^check:')
  plan_lists=$(printf '%s\n' "$output" | grep '^shellcheck ')
  ran=${plan_line#*; ran:}
  ran=${ran%%; skipped by scope:*}
  skipped=${plan_line#*skipped by scope:}
  read -r ran <<<"$ran"
  read -r skipped <<<"$skipped"
}

fail() {
  printf 'FAIL %s: expected %s\n  ran:%s\n  skipped by scope:%s\n' "$case_name" "$1" "$ran" "$skipped" >&2
  failures=$((failures + 1))
}

expect_ran() {
  local step
  for step in "$@"; do
    case " $ran " in
    *" $step "*) ;;
    *) fail "$step to run" ;;
    esac
  done
}

expect_skipped() {
  local step
  for step in "$@"; do
    case " $skipped " in
    *" $step "*) ;;
    *) fail "$step to be skipped" ;;
    esac
  done
}

expect_ran_exactly() {
  [ "$ran" = "$*" ] || fail "exactly:$(printf ' %s' "$@")"
}

expect_everything() {
  [ "$skipped" = none ] || fail 'nothing skipped'
  expect_ran qmllint shellcheck shfmt luacheck stylua voxcmd-click packages check-scope
}

expect_list_has() {
  printf '%s\n' "$plan_lists" | grep -Fxq "shellcheck $1: $2" || fail "shellcheck's $1 list to hold $2"
}

report() {
  local before=$failures
  "$@"
  [ "$failures" -ne "$before" ] || printf 'ok   %s\n' "$case_name"
}

case_readme() {
  start_case 'README-only change'
  echo >>README.md
  plan
  expect_ran_exactly packages symlinks git-diff-check whitespace conflicts
}

case_home_qml() {
  start_case 'QML under home/quickshell'
  echo '// x' >>home/quickshell/.config/quickshell/shell.qml
  plan
  expect_ran qmllint notification-markup
  expect_skipped voxcmd-phrases voxcmd-click voxcmd-calendar luacheck stylua shellcheck check-scope
}

case_greeter_lua() {
  start_case 'Lua under system/etc/greetd/quickshell'
  echo '-- x' >>system/etc/greetd/quickshell/safe-hyprland.lua
  plan
  expect_ran luacheck stylua qmllint
  expect_skipped voxcmd-click shellcheck
}

case_voxcmd_runner() {
  start_case 'voxcmd tests/run.sh only'
  echo '# x' >>home/voxcmd/tests/run.sh
  plan
  expect_ran voxcmd-phrases voxcmd-click voxcmd-calendar shellcheck shfmt
  expect_skipped luacheck qmllint
  expect_list_has plain home/voxcmd/tests/run.sh
  expect_list_has plain home/voxcmd/tests/lib.sh
}

case_deleted_sourced_helper() {
  start_case 'deleted helper another script sources'
  git rm -q home/quickshell/.config/quickshell/scripts/lib/audio-loop.sh
  plan
  expect_ran shellcheck
  expect_list_has sourcing home/quickshell/.config/quickshell/scripts/ff7-audio
}

case_unmapped_path() {
  start_case 'unmapped new top-level path'
  mkdir newdir
  echo x >newdir/file
  plan
  expect_everything
}

case_check_sh() {
  start_case 'change to lib/check.sh'
  echo '# x' >>lib/check.sh
  plan
  expect_everything
}

case_full_override() {
  start_case 'CHECK_FULL=1 with --changed'
  echo >>README.md
  CHECK_FULL=1 plan
  expect_everything
}

case_check_scope_in_scope() {
  start_case 'check-scope runs for a check script or its own test'
  echo '# x' >>lib/check-qml.sh
  plan
  expect_ran check-scope
  start_case 'check-scope runs for its own test'
  echo '# x' >>lib/tests/check-scope.sh
  plan
  expect_ran check-scope
  expect_skipped voxcmd-click qmllint
}

for case_fn in case_readme case_home_qml case_greeter_lua case_voxcmd_runner case_deleted_sourced_helper \
  case_unmapped_path case_check_sh case_full_override case_check_scope_in_scope; do
  report "$case_fn"
done

[ "$failures" -eq 0 ] || exit 1
