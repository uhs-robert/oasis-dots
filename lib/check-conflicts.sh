#!/bin/sh
# Fails on merge conflict markers left in tracked text files.
# A bare ======= also underlines Markdown headings, so it only counts in a file that has a <<<<<<< line.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
cd "$repo_dir" || exit 1

status=0
hits=$(git grep -nIE '^(<{7}|\|{7}|={7}|>{7})( |$)') || status=$?
if [ "$status" -gt 1 ]; then
  echo "Failed to scan for conflict markers (git grep exit $status)" >&2
  exit 1
fi
[ -n "$hits" ] || exit 0

offenders=$(printf '%s\n' "$hits" | awk '
  {
    split($0, part, ":")
    n++
    file[n] = part[1]
    line[n] = part[2]
    marker[n] = substr($0, length(part[1]) + length(part[2]) + 3, 7)
    if (marker[n] == "<<<<<<<") opened[part[1]] = 1
  }
  END {
    for (i = 1; i <= n; i++)
      if (marker[i] != "=======" || opened[file[i]]) printf "unresolved conflict marker in %s:%s\n", file[i], line[i]
  }
')
[ -n "$offenders" ] || exit 0
printf '%s\n' "$offenders" >&2
exit 1
