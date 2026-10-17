#!/bin/bash
# Tests which steps `lib/check.sh --changed` picks for a change, through `check.sh --plan`, so no linter runs.
# Each case edits a scratch clone of this checkout (with the working tree's lib/check.sh, lib/check/, lib/common/ and lib/install/ on top) and reads the plan.
set -u
# A hook or an outer check can leave these pointing at another repository, or skipping steps (the commit hook skips the
# voxcmd ones).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CHECK_SKIP_STEPS

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

git clone -q "$repo_dir" "$scratch/clone" || exit 1
cd "$scratch/clone" || exit 1
git config user.name scope-test
git config user.email scope-test@example.invalid
cp "$repo_dir"/lib/check.sh lib/
mkdir -p lib/check
cp -R "$repo_dir"/lib/check/. lib/check/
mkdir -p lib/common lib/install
cp -R "$repo_dir"/lib/common/. lib/common/
cp -R "$repo_dir"/lib/install/. lib/install/
git add -A
git commit -q --allow-empty -m 'scratch base' || exit 1

# Paths are looked up in the clone so renaming a file does not leave a case pointing at nothing; a case
# whose file is missing fails and names what it looked for.
first_tracked() {
  local found
  found=$(git ls-files -- "$1" | grep -v -e "${2:-^$}" | head -n 1)
  [ -n "$found" ] || {
    printf 'FAIL %s: no tracked file matching %s\n' "$case_name" "$1" >&2
    failures=$((failures + 1))
    return 1
  }
  printf '%s\n' "$found"
}

failures=0
case_name=''
plan_line=''
plan_lists=''
ran=''
skipped=''
requested=''

start_case() {
  case_name=$1
  git reset -q --hard HEAD
  git clean -qfdx
}

# Reads the summary line and shellcheck lists out of a plan's output.
parse_plan() {
  plan_line=$(printf '%s\n' "$1" | grep '^check:')
  plan_lists=$(printf '%s\n' "$1" | grep '^shellcheck ')
  ran=${plan_line#*; ran:}
  ran=${ran%%; skipped by scope:*}
  skipped=${plan_line#*skipped by scope:}
  skipped=${skipped%%; skipped by request:*}
  requested=${plan_line#*skipped by request:}
  [ "$requested" != "$plan_line" ] || requested=''
  read -r ran <<<"$ran"
  read -r skipped <<<"$skipped"
  read -r requested <<<"$requested"
}

# Runs the plan for the scratch change made so far.
plan() {
  # CHECK_FULL is cleared because an outer `CHECK_FULL=1 just check` would otherwise make every plan full.
  parse_plan "$(env -u CHECK_FULL "$@" sh lib/check.sh --plan --changed HEAD 2>&1)"
}

# Like plan, for a change given as a path list ($1) instead of read from git.
plan_paths() {
  local paths=$1
  shift
  parse_plan "$(printf '%s\n' "$paths" | env -u CHECK_FULL "$@" sh lib/check.sh --plan --paths-from - 2>&1)"
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
  expect_ran_exactly packages symlinks git-diff-check whitespace conflicts ignored-integrations
}

case_home_qml() {
  start_case 'QML under home/quickshell'
  local qml
  qml=$(first_tracked 'home/quickshell/*.qml') || return 0
  echo '// x' >>"$qml"
  plan
  expect_ran qmllint qml-paths notification-markup
  expect_skipped voxcmd-phrases voxcmd-click voxcmd-calendar luacheck stylua shellcheck check-scope
}

case_shader_source() {
  start_case 'shader source'
  local frag
  frag=$(first_tracked 'home/quickshell/*.frag') || return 0
  echo '// x' >>"$frag"
  plan
  expect_ran shaders
  expect_skipped qmllint notification-markup voxcmd-click check-scope
}

case_outside_quickshell_consumer() {
  start_case 'a file outside the Quickshell tree that names a path in it'
  echo '# x' >>home/hypr/.config/hypr/scripts/lock-screen.sh
  plan
  expect_ran qml-paths lock-skins
  expect_skipped voxcmd-click
}

case_greeter_lua() {
  start_case 'Lua under system/etc/greetd/quickshell'
  local lua
  lua=$(first_tracked 'system/etc/greetd/quickshell/*.lua') || return 0
  echo '-- x' >>"$lua"
  plan
  expect_ran luacheck stylua qmllint
  expect_skipped voxcmd-click shellcheck
}

case_voxcmd_runner() {
  start_case 'voxcmd test runner only'
  local runner lib
  lib=$(first_tracked 'home/voxcmd/tests/lib.sh') || return 0
  runner=$(first_tracked 'home/voxcmd/tests/*.sh' '/lib\.sh$') || return 0
  echo '# x' >>"$runner"
  plan
  expect_ran voxcmd-phrases voxcmd-click voxcmd-calendar voxcmd-wake shellcheck shfmt
  expect_skipped luacheck qmllint
  expect_list_has plain "$runner"
  expect_list_has plain "$lib"
}

case_voxcmd_rust_source() {
  start_case 'voxcmd Rust source'
  local source
  source=$(first_tracked 'home/voxcmd/src/cli.rs') || return 0
  echo '// x' >>"$source"
  plan
  expect_ran voxcmd-rust voxcmd-click
  expect_skipped luacheck qmllint
}

case_deleted_sourced_helper() {
  start_case 'deleted helper another script sources'
  local helper sourcing
  helper=$(first_tracked 'home/quickshell/*/scripts/lib/*.sh') || return 0
  sourcing=$(git grep -l -F "${helper##*/}" -- 'home/quickshell/*/scripts/*' ":!$helper" | head -n 1)
  [ -n "$sourcing" ] || {
    fail "a tracked script under home/quickshell scripts that sources ${helper##*/}"
    return 0
  }
  git rm -q "$helper"
  plan
  expect_ran shellcheck
  expect_list_has sourcing "$sourcing"
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
  plan CHECK_FULL=1
  expect_everything
}

case_check_py() {
  start_case 'change to a lib/check/ Python module'
  echo '# x' >>lib/check/passed.py
  plan
  expect_everything
}

case_check_scope_for_check_script() {
  start_case 'check-scope runs for a lib/check/ change'
  echo '# x' >>lib/check/steps/qml.py
  plan
  expect_ran check-scope
}

case_check_scope_for_own_test() {
  start_case 'check-scope runs for its own test'
  echo '# x' >>lib/check/tests/scope.sh
  plan
  expect_ran check-scope
  expect_skipped voxcmd-click qmllint
}

case_firefox_extension() {
  start_case 'Firefox extension script'
  local script
  script=$(first_tracked 'extras/voxcmd-firefox/*.js') || return 0
  echo '// x' >>"$script"
  plan
  expect_ran voxcmd-firefox
  expect_skipped qmllint luacheck shellcheck
}

case_firefox_policy() {
  start_case 'Firefox policy installer'
  echo '# x' >>lib/install/voice.sh
  plan
  expect_ran firefox-policy shellcheck
  expect_skipped qmllint luacheck voxcmd-click check-scope
}

case_greeter_keyring() {
  start_case 'greetd keyring unlock installer'
  echo '# x' >>lib/install/greeter.sh
  plan
  expect_ran greeter-keyring shellcheck
  expect_skipped firefox-policy qmllint luacheck check-scope
}

case_install_loader() {
  start_case 'install library loader'
  echo '# x' >>lib/install/fonts.sh
  plan
  expect_ran install-load shellcheck
  expect_skipped firefox-policy greeter-keyring qmllint luacheck check-scope
}

case_install_loader_reached_through_earlier_arms() {
  start_case 'install libraries claimed by earlier arms still reach the loader test'
  plan_paths "$(printf '%s\n' lib/install/voice.sh lib/install/greeter.sh)"
  expect_ran install-load firefox-policy greeter-keyring
  plan_paths lib/common/greeter-files.sh
  expect_ran install-load qmllint
}

case_paths_list() {
  start_case 'path list from stdin'
  plan_paths 'README.md'
  expect_ran_exactly packages symlinks git-diff-check whitespace conflicts ignored-integrations
  [ "$plan_line" = "${plan_line/listed files/}" ] && fail 'the label to say listed files'
  local qml
  qml=$(first_tracked 'home/quickshell/*.qml') || return 0
  plan_paths "$qml"
  expect_ran qmllint
  expect_skipped voxcmd-click luacheck
}

case_paths_list_unclaimed_skip_voxcmd() {
  start_case 'unclaimed listed path with the voxcmd steps skipped'
  local voxcmd='voxcmd-phrases voxcmd-click voxcmd-calendar voxcmd-wake voxcmd-firefox'
  plan_paths 'newdir/file' CHECK_SKIP_STEPS="$voxcmd"
  expect_ran qmllint shellcheck shfmt luacheck packages
  for step in $voxcmd; do
    case " $ran " in *" $step "*) fail "$step not to run" ;; esac
    case " $requested " in *" $step "*) ;; *) fail "$step to be listed as skipped by request" ;; esac
  done
  [ "$skipped" = none ] || fail 'nothing skipped by scope'
}

case_paths_list_deleted_script() {
  start_case 'listed path that is gone lints the shell groups'
  plan_paths 'lib/does-not-exist.sh'
  expect_ran shellcheck
}

case_skip_steps_with_changed() {
  start_case 'CHECK_SKIP_STEPS drops an in-scope step'
  echo '# x' >>lib/check/steps/qml.py
  plan CHECK_SKIP_STEPS='check-scope shfmt'
  case " $ran " in *" check-scope "* | *" shfmt "*) fail 'check-scope and shfmt not to run' ;; esac
  [ "$requested" = 'check-scope shfmt' ] || fail "requested to list check-scope shfmt, got: $requested"
}

for case_fn in case_readme case_home_qml case_shader_source case_outside_quickshell_consumer case_greeter_lua case_voxcmd_runner case_voxcmd_rust_source case_deleted_sourced_helper \
  case_unmapped_path case_check_sh case_check_py case_full_override case_check_scope_for_check_script case_check_scope_for_own_test case_firefox_extension case_firefox_policy case_greeter_keyring case_install_loader case_install_loader_reached_through_earlier_arms \
  case_paths_list case_paths_list_unclaimed_skip_voxcmd case_paths_list_deleted_script case_skip_steps_with_changed; do
  report "$case_fn"
done

[ "$failures" -eq 0 ] || exit 1
