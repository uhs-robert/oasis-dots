#!/usr/bin/env bash
# Times how long voxcmd takes to route a phrase, inside the sandbox against the phrase fixtures, so nothing on the desktop
# acts. Prints one TSV row per phrase and mode (p50, p95, mean and max in ms) and an "all" row over every sample. For
# comparing builds and changes, not a check: lib/check.sh never runs it.
#
#   home/voxcmd/tests/bench.sh [--runs N] [--live]   bench-phrases.tsv, N timed runs each (default 20) after 2 warmups;
#                                                    --live also runs the phrases marked live, with stubs for what acts
#   home/voxcmd/tests/bench.sh --all                 every phrase in phrases.tsv once, dry run: the overall spread and the
#                                                    10 slowest
#
# VOXCMD_DRY_RUN_CMD (default "voxcmd explain") and VOXCMD_RUN_CMD (default "voxcmd run") are the commands a phrase is
# appended to. `voxcmd` is the sandbox's: the new CLI, through the bash shim until the Rust build is a VOXCMD_BIN. Another
# build is timed with the same phrases by setting both. Needs hyperfine (not for --all) and jq.
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

runs=20 live=0 all=0
while [ $# -gt 0 ]; do
  case $1 in
  --runs) runs=$2 && shift ;;
  --live) live=1 ;;
  --all) all=1 ;;
  *) echo "usage: ${0##*/} [--runs N] [--live] | --all" >&2 && exit 2 ;;
  esac
  shift
done
dry_run_cmd=${VOXCMD_DRY_RUN_CMD:-voxcmd explain}
run_cmd=${VOXCMD_RUN_CMD:-voxcmd run}

"$tests_dir/firefox-profile" "$HOME/.config/mozilla/firefox"

# Reads one sample in seconds per line; prints "p50 p95 mean max" in ms. Nearest rank, so p95 of 20 samples is the 19th.
summarize() {
  jq -sr 'sort | length as $n
    | [.[(($n * 0.5) | ceil) - 1], .[(($n * 0.95) | ceil) - 1], (add / $n), .[-1]]
    | map(. * 1000 | round) | @tsv'
}

if [ "$all" = 1 ]; then
  samples="$SANDBOX_DIR/all.tsv"
  while IFS=$'\t' read -r phrase _; do
    [ -n "$phrase" ] && [ "$phrase" != phrase ] || continue
    started=$EPOCHREALTIME
    # shellcheck disable=SC2086 # the command is words
    $dry_run_cmd "$phrase" >/dev/null 2>&1 || true
    printf '%s\t%s\n' "$(awk -v from="$started" -v to="$EPOCHREALTIME" 'BEGIN { print to - from }')" "$phrase"
  done <"$tests_dir/phrases.tsv" >"$samples"
  printf 'phrases\tp50_ms\tp95_ms\tmean_ms\tmax_ms\n'
  printf '%s\t%s\n' "$(wc -l <"$samples")" "$(cut -f1 "$samples" | summarize)"
  printf '\nslowest_ms\tphrase\n'
  sort -rn "$samples" | head -n 10 | awk -F'\t' '{ printf "%d\t%s\n", $1 * 1000, $2 }'
  exit 0
fi

command -v hyperfine >/dev/null || {
  echo 'bench: needs hyperfine' >&2
  exit 1
}

results_dir="$SANDBOX_DIR/bench"
# Seconds per run from hyperfine's --export-json: 1.x lists them as times, 2.x as measurements.
sample_times() { jq '.results[0] | (.times // [.measurements[].time_wall_clock.value])[]' "$@"; }
mkdir -p "$results_dir"
printf 'mode\tphrase\tp50_ms\tp95_ms\tmean_ms\tmax_ms\n'
bench_one() {
  local mode=$1 phrase=$2 cmd=$3
  local result="$results_dir/$mode-$4.json"
  # -N runs the command without a shell, splitting it on spaces, so a phrase must not hold quotes.
  hyperfine -N --style none --warmup 2 --runs "$runs" -i --export-json "$result" "$cmd $phrase" >/dev/null 2>&1
  printf '%s\t%s\t%s\n' "$mode" "$phrase" "$(sample_times "$result" | summarize)"
}
index=0
while IFS=$'\t' read -r phrase is_live _; do
  [ -n "$phrase" ] && [ "$phrase" != phrase ] || continue
  index=$((index + 1))
  bench_one dry "$phrase" "$dry_run_cmd" "$index"
  if [ "$live" = 1 ] && [ "$is_live" = yes ]; then bench_one live "$phrase" "$run_cmd" "$index"; fi
done <"$tests_dir/bench-phrases.tsv"
for mode in dry live; do
  compgen -G "$results_dir/$mode-*.json" >/dev/null || continue
  printf '%s\tall\t%s\n' "$mode" "$(sample_times "$results_dir/$mode"-*.json | summarize)"
done
