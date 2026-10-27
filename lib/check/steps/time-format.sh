#!/bin/sh
# Fails when Quickshell QML/JS builds am/pm text by hand instead of going through TimeFormat, which follows Settings > Date & time.
# Flags `? "AM" : "PM"` style ternaries (also am/pm and A/P, either quote) and " AM" / " PM" literals; parsing such as `=== "pm"` is fine.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
cd "$repo_dir" || exit 1

qs_dir=home/quickshell/.config/quickshell

quote="[\"']"
ternary="\\?[[:space:]]*${quote}(AM|am|A)${quote}[[:space:]]*:[[:space:]]*${quote}(PM|pm|P)${quote}"
literal="${quote} (AM|PM)${quote}"

# git grep exits 1 when nothing matches and >1 on a real failure, so the two
# cases have to be told apart or an error would read as a clean scan.
status=0
offenders=$(
  git grep --untracked -nIE "${ternary}|${literal}" -- \
    "$qs_dir/*.qml" "$qs_dir/*.js" \
    ":(exclude)$qs_dir/features/clock/TimeFormat.qml"
) || status=$?

if [ "$status" -gt 1 ]; then
  echo "Failed to scan for hand-built meridiem text (git grep exit $status)" >&2
  exit 1
fi

if [ -n "$offenders" ]; then
  printf '%s\n' "$offenders" | cut -d: -f1,2 | while IFS= read -r location; do
    printf 'hand-built am/pm text at %s: use TimeFormat (hour, hour_of, clock_of, meridiem) so Settings > Date & time applies; see AGENTS.md\n' "$location"
  done >&2
  exit 1
fi
