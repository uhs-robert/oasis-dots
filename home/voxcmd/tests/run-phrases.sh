#!/usr/bin/env bash
# Routes every phrase in phrases.tsv with `voxcmd --dry-run` inside the sandbox and fails when one lands somewhere
# other than its expected column: "Integration/action" for a single option that runs, "picker", "none" or "builtin".
# The fixtures stand in for the windows (Firefox, Slack and kitty), binds, audio devices, apps, agents, timers, tmux
# sessions and the text OCR reads in the focused window, so the result does not depend on what is open; no private integration is loaded.
#
#   home/voxcmd/tests/run-phrases.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
fixtures_dir="$tests_dir/fixtures"

if [ -z "${SANDBOX_DIR:-}" ]; then
  SANDBOX_CLIENTS_JSON=$(cat "$fixtures_dir/clients.json")
  SANDBOX_ACTIVEWINDOW_JSON=$(jq -c '.[] | select(.focusHistoryID == 0)' <<<"$SANDBOX_CLIENTS_JSON")
  SANDBOX_MONITORS_JSON=$(cat "$fixtures_dir/monitors.json")
  SANDBOX_ACTIVEWORKSPACE_JSON=$(jq -c '.[] | select(.focused) | .activeWorkspace' <<<"$SANDBOX_MONITORS_JSON")
  SANDBOX_BINDS_JSON=$(cat "$fixtures_dir/binds.json")
  SANDBOX_PW_DUMP_JSON=$(cat "$fixtures_dir/pw-dump.json")
  SANDBOX_TESSERACT_TSV=$(cat "$fixtures_dir/ocr.tsv")
  SANDBOX_AGENTS_JSON='[]'
  SANDBOX_TIMERS_JSON='[]'
  SANDBOX_TMUX_SESSIONS='dotfiles'
  export SANDBOX_CLIENTS_JSON SANDBOX_ACTIVEWINDOW_JSON SANDBOX_ACTIVEWORKSPACE_JSON SANDBOX_MONITORS_JSON \
    SANDBOX_BINDS_JSON SANDBOX_PW_DUMP_JSON SANDBOX_TESSERACT_TSV SANDBOX_AGENTS_JSON SANDBOX_TIMERS_JSON SANDBOX_TMUX_SESSIONS
  # Installed apps come from the fixture's desktop entries alone.
  export XDG_DATA_HOME="$fixtures_dir" XDG_DATA_DIRS="$fixtures_dir"
  unset VOXCMD_EXTRA_INTEGRATIONS
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

# Prints where a phrase goes, read from the dry run's result line and its first option.
route_of() {
  voxcmd --dry-run "$1" 2>/dev/null | awk '
    /^result: +built-in/ { print "builtin"; exit }
    /^result: +no match/ { print "none"; exit }
    /^result: +ask with the picker/ { print "picker"; exit }
    /^option 1: / {
      name = $0; sub(/^option 1: +/, "", name); sub(/ \(.*/, "", name)
      match($0, / action=[^ ]+/)
      print name "/" substr($0, RSTART + 8, RLENGTH - 8)
      exit
    }'
}

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
