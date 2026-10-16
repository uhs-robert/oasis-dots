#!/usr/bin/env bash
# Samples the running voxcmd-wake listener every 10 s for N minutes (default 60) and prints its resident memory (MB)
# and CPU use over the window. Read-only from /proc: needs neither the sandbox nor a check slot, and the machine
# should be idle so the numbers are the listener's own cost.
#
#   home/voxcmd/tests/wake-sample.sh [minutes]
set -euo pipefail

minutes=${1:-60}
interval_s=10
[[ $minutes =~ ^[1-9][0-9]*$ ]] || {
  echo "usage: ${0##*/} [minutes]" >&2
  exit 2
}

pid=$(pgrep -f '^[^ ]*python3 .*/voxcmd-wake$' | head -n 1 || true)
[ -n "$pid" ] || {
  echo 'wake-sample: voxcmd-wake is not running (voxcmd wake on)' >&2
  exit 1
}

# utime + stime in clock ticks; the command name in /proc/<pid>/stat may hold spaces, so cut after its closing paren.
cpu_ticks() {
  local stat fields
  stat=$(<"/proc/$pid/stat") || return 1
  read -ra fields <<<"${stat##*) }"
  echo $((fields[11] + fields[12]))
}
rss_kb() { awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status"; }

ticks_per_s=$(getconf CLK_TCK)
samples=$((minutes * 60 / interval_s))
first_ticks=$(cpu_ticks)
started=$EPOCHREALTIME
rss_samples=()
for ((i = 0; i < samples; i++)); do
  sleep "$interval_s"
  kb=$(rss_kb) || break
  rss_samples+=("$kb")
done
[ "${#rss_samples[@]}" -gt 0 ] || {
  echo 'wake-sample: voxcmd-wake exited before the first sample' >&2
  exit 1
}
last_ticks=$(cpu_ticks) || {
  echo 'wake-sample: voxcmd-wake exited during the window' >&2
  exit 1
}

printf 'pid\tminutes\trss_min_mb\trss_mean_mb\trss_max_mb\tcpu_percent\n'
printf '%s\n' "${rss_samples[@]}" | awk -v pid="$pid" -v from="$started" -v to="$EPOCHREALTIME" \
  -v ticks="$((last_ticks - first_ticks))" -v hz="$ticks_per_s" '
  NR == 1 || $1 < min { min = $1 }
  $1 > max { max = $1 }
  { sum += $1 }
  END {
    window = to - from
    printf "%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.2f\n", pid, window / 60, min / 1024, sum / NR / 1024, max / 1024, 100 * ticks / hz / window
  }'
