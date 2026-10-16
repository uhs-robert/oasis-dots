#!/usr/bin/env bash
# Routes every phrase in phrases.tsv with `voxcmd explain` inside the sandbox and fails when one lands somewhere
# other than its expected column: "Integration/action" for a single option that runs, "picker", "none" or "builtin";
# for a phrase of several steps, those per step joined by " > ", or "refused".
# The fixtures (phrase-fixtures.sh, plus a Firefox profile's tabs and history) stand in for the desktop, so the result
# does not depend on what is open.
#
#   home/voxcmd/tests/run-phrases.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
fixtures_dir="$tests_dir/fixtures"
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$tests_dir/../../../lib/check/lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"

if [ -z "${SANDBOX_DIR:-}" ]; then
  # shellcheck source-path=SCRIPTDIR source=phrase-fixtures.sh
  . "$tests_dir/phrase-fixtures.sh"
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

# Prints where a phrase goes, read from the dry run's result line and its first option; a sequence's steps are joined
# by " > ", and a refused one is "refused". awk reads to the end rather than exiting at the answer: a dry run still
# printing would die of SIGPIPE, and under pipefail that fails the job, which `wait -n` below turns into the whole
# script exiting.
route_of() {
  voxcmd explain "$1" 2>/dev/null | awk '
    function add(route) { routes = routes (routes == "" ? "" : " > ") route; found = 1 }
    /^step [0-9]+ of [0-9]+$/ { found = 0; next }
    /^result: +refused/ { refused = 1 }
    found { next }
    /^result: +built-in/ { add("builtin") }
    /^result: +no match/ { add("none") }
    /^result: +ask with the picker/ { add("picker") }
    /^option 1: / {
      name = $0; sub(/^option 1: +/, "", name); sub(/ \(.*/, "", name)
      match($0, / action=[^ ]+/)
      add(name "/" substr($0, RSTART + 8, RLENGTH - 8))
    }
    END { if (refused) print "refused"; else if (routes != "") print routes }'
}

# Firefox's tabs and places, in the sandbox's own HOME.
"$tests_dir/firefox-profile" "$HOME/.config/mozilla/firefox"

phrases=() expected=()
while IFS=$'\t' read -r phrase expected_route _; do
  [ -n "$phrase" ] && [ "$phrase" != phrase ] || continue
  phrases+=("$phrase") expected+=("$expected_route")
done <"$tests_dir/phrases.tsv"

# A dry run is dozens of short jq and fzf processes, so several run at once.
routes_dir="$SANDBOX_DIR/routes"
mkdir -p "$routes_dir"
parallel_runs=$(nproc 2>/dev/null || echo 4)
for index in "${!phrases[@]}"; do
  [ "$(jobs -rp | wc -l)" -lt "$parallel_runs" ] || wait -n
  route_of "${phrases[index]}" >"$routes_dir/$index" &
done
wait

failures=0
for index in "${!phrases[@]}"; do
  actual=$(cat "$routes_dir/$index")
  [ "$actual" = "${expected[index]}" ] && continue
  printf '%s: expected %s, got %s\n' "${phrases[index]}" "${expected[index]}" "${actual:-no dry-run result}"
  failures=$((failures + 1))
done
if [ "$failures" != 0 ]; then
  printf '%s of %s phrases routed differently\n' "$failures" "${#phrases[@]}"
  exit 1
fi
printf '%s phrases routed as expected\n' "${#phrases[@]}"
