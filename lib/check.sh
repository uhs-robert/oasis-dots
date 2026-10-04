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

# Optional tooling: skip when absent so validation stays dependency-light.
if command -v shellcheck >/dev/null 2>&1; then
  step shellcheck shellcheck install.sh uninstall.sh lib/*.sh demo/*.sh
  step shellcheck shellcheck -x -P SCRIPTDIR home/quickshell/.config/quickshell/scripts/lib/*.sh home/quickshell/.config/quickshell/scripts/ff7-audio home/quickshell/.config/quickshell/scripts/goldeneye-audio home/quickshell/.config/quickshell/scripts/mgs2-audio home/quickshell/.config/quickshell/scripts/ocarina-audio
else
  echo 'skip: shellcheck not installed'
fi

if command -v shfmt >/dev/null 2>&1; then
  step shfmt shfmt -i 2 -d install.sh uninstall.sh lib/*.sh demo/*.sh home/quickshell/.config/quickshell/scripts/lib/*.sh home/quickshell/.config/quickshell/scripts/ff7-audio home/quickshell/.config/quickshell/scripts/goldeneye-audio home/quickshell/.config/quickshell/scripts/mgs2-audio home/quickshell/.config/quickshell/scripts/ocarina-audio
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
