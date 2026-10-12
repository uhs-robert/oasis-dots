#!/bin/sh
set -u

# Runs every validation step and reports all failures, rather than stopping at
# the first one: a single run should show everything that needs fixing.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

cd "$repo_dir" || exit 1

logs=$(mktemp -d) || exit 1
trap 'rm -rf "$logs"' EXIT
trap 'exit 1' INT TERM

failed=''

record() {
  case " $failed " in
  *" $1 "*) ;;
  *) failed="$failed $1" ;;
  esac
}

# Shows a step's output live and keeps it, so a failure can be repeated after the summary.
step() {
  name=$1
  shift
  { "$@" 2>&1 || echo "$?" >"$logs/$name.failed"; } | tee -a "$logs/$name.log"
  [ ! -e "$logs/$name.failed" ] || record "$name"
}

# Agent tooling shell scripts: tracked *.sh plus extension-less files with a
# sh/bash shebang. Symlinks are skipped (their target is linted itself).
# worktrees/ holds other agents' scratch copies and skills/synced/ is vendored.
agent_scripts() {
  git ls-files -- .claude home/claude/.claude ':!:.claude/worktrees' ':!:home/claude/.claude/skills/synced' |
    while IFS= read -r file; do
      [ -f "$file" ] && [ ! -L "$file" ] || continue
      case "${file##*/}" in
      *.sh) printf '%s\n' "$file" ;;
      *.*) ;;
      *) head -n 1 "$file" | grep -Eq '^#!.*[/ ](ba|da|z)?sh( |$)' && printf '%s\n' "$file" ;;
      esac
    done
}
agent_script_files=$(agent_scripts)

# Optional tooling: skip when absent so validation stays dependency-light.
if command -v shellcheck >/dev/null 2>&1; then
  step shellcheck shellcheck install.sh uninstall.sh lib/*.sh demo/*.sh home/hypr/.config/hypr/scripts/state-write home/voxcmd/tests/*.sh home/calendar/tests/*.sh
  step shellcheck shellcheck -x -P SCRIPTDIR home/quickshell/.config/quickshell/scripts/lib/*.sh home/quickshell/.config/quickshell/scripts/ff7-audio home/quickshell/.config/quickshell/scripts/goldeneye-audio home/quickshell/.config/quickshell/scripts/mgs2-audio home/quickshell/.config/quickshell/scripts/ocarina-audio
  # shellcheck disable=SC2086 # newline-separated tracked paths, none contain spaces
  [ -z "$agent_script_files" ] || step shellcheck shellcheck -x -P SCRIPTDIR $agent_script_files
else
  echo 'skip: shellcheck not installed'
fi

if command -v shfmt >/dev/null 2>&1; then
  step shfmt shfmt -i 2 -d install.sh uninstall.sh lib/*.sh demo/*.sh home/hypr/.config/hypr/scripts/state-write home/voxcmd/tests/*.sh home/quickshell/.config/quickshell/scripts/lib/*.sh home/quickshell/.config/quickshell/scripts/ff7-audio home/quickshell/.config/quickshell/scripts/goldeneye-audio home/quickshell/.config/quickshell/scripts/mgs2-audio home/quickshell/.config/quickshell/scripts/ocarina-audio
  # shellcheck disable=SC2086 # newline-separated tracked paths, none contain spaces
  [ -z "$agent_script_files" ] || step shfmt shfmt -i 2 -d $agent_script_files
else
  echo 'skip: shfmt not installed'
fi

if command -v stylua >/dev/null 2>&1; then
  step stylua stylua --respect-ignores --check home/hypr/.config/hypr
else
  echo 'skip: stylua not installed'
fi

step luacheck sh ./lib/check-lua.sh
step qmllint sh ./lib/check-qml.sh
step lock-skins sh ./lib/check-lock-skins.sh
step style-exports sh ./lib/check-style-exports.sh
step time-format sh ./lib/check-time-format.sh
# voxcmd routes with jq and fzf, so without them every phrase would read as no match.
if command -v jq >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
  step voxcmd-phrases bash ./home/voxcmd/tests/run-phrases.sh
else
  echo 'skip: voxcmd phrases need jq and fzf'
fi
# calendar-sync needs its two Python libraries; the test stubs rbw and qs-ipc.
if python3 -c 'import icalendar, recurring_ical_events' >/dev/null 2>&1; then
  step calendar-sync bash ./home/calendar/tests/run.sh
else
  echo 'skip: calendar-sync tests need python-icalendar and python-recurring-ical-events'
fi
step packages sh ./lib/check-packages.sh
step symlinks sh ./lib/check-symlinks.sh
step git-diff-check git diff --check HEAD
step whitespace sh ./lib/check-whitespace.sh
step conflicts sh ./lib/check-conflicts.sh

if [ -n "$failed" ]; then
  printf 'FAILED:%s\n' "$failed" >&2
  for name in $failed; do
    printf '\n== %s (last 25 lines)\n' "$name" >&2
    tail -n 25 "$logs/$name.log" >&2
  done
  exit 1
fi

echo 'All checks passed'
