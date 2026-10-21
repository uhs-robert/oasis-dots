#!/usr/bin/env bash
# Repro for the keeptabs restart priming on a shadow bar: after the keeptabs-status stream restarts, its first
# line (the priming line) must not fire waiting_started and the next waiting rise must, even when that first line
# repeats the old last line. Fails on a bar that keeps last_line across the restart, passes with it cleared.
# It also asserts that a stream exit empties runs, tooltip and the counts, so the module hides instead of freezing.
# Usage: keeptabs-seq.sh [--name SHADOW] [<branch>...]   (branches as for `shadow.sh up`; none tests the main checkout)
# The shadow's PATH hides ~/.local/bin, so a stub keeptabs-status is installed in the shadow HOME and fed from
# files, and the shadow's copy of KeeptabsState.qml is patched to log each waiting_started; the repo is untouched.
set -euo pipefail

shadow="$(dirname "$0")/shadow.sh"
name=ktseq
if [[ ${1:-} == --name ]]; then
  name=${2:?--name needs a shadow name}
  shift 2
fi

base="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow/$name"
control="$base/ktseq-control"
failures=0
cleanup() { "$shadow" down "$name" >/dev/null 2>&1 || true; }

# Armed only after `up` succeeds, so a name already in use is never torn down by this script.
"$shadow" up "$name" "$@"
trap cleanup EXIT

# Run N of the stub echoes every line appended to $control/feed.N and exits on the line EXIT.
mkdir -p "$control" "$base/home/.local/bin"
cat >"$base/home/.local/bin/keeptabs-status" <<STUB
#!/usr/bin/env bash
dir=$control
n=\$(( \$(cat "\$dir/runs" 2>/dev/null || echo 0) + 1 ))
echo "\$n" >"\$dir/runs"
: >"\$dir/feed.\$n"
while read -r line; do
  [[ \$line == EXIT ]] && exit 0
  echo "\$line"
done < <(tail --pid=\$\$ -n +1 -f "\$dir/feed.\$n")
STUB
chmod +x "$base/home/.local/bin/keeptabs-status"

# The probe ran at bar start and found no stub; the edit makes Quickshell reload the copy and probe again.
state_qml="$base/qs/features/keeptabs/KeeptabsState.qml"
# Rewritten in place: Quickshell stops watching a file whose inode was replaced, as `sed -i` does.
patched=$(sed 's|if (wait_rose) root.waiting_started();|if (wait_rose) { console.log("KTSEQ waiting_started seq=" + data.waiting_seq); root.waiting_started(); }|' "$state_qml")
printf '%s\n' "$patched" >"$state_qml"
patched=$(sed 's|^\( *\)root.last_line = "";|&\n\1console.log("KTSEQ exited runs=" + root.runs.length + " tooltip=[" + root.tooltip + "] counts=" + root.done_count + root.running_count + root.waiting_count + " class=" + root.state_class);|' "$state_qml")
printf '%s\n' "$patched" >"$state_qml"
grep -q KTSEQ "$state_qml" || {
  echo "keeptabs-seq: could not patch the shadow copy" >&2
  exit 1
}

wait_for_run() { # <n>
  for _ in $(seq 400); do
    [[ $(cat "$control/runs" 2>/dev/null || echo 0) -ge $1 && -e $control/feed.$1 ]] && return 0
    sleep 0.1
  done
  echo "keeptabs-seq: stream run $1 never started" >&2
  exit 1
}
feed() { echo "{\"text\":\"\",\"class\":\"idle\",\"tooltip\":\"t$2\",\"finished_seq\":0,\"waiting_seq\":$2}" >>"$control/feed.$1"; }
fired() { grep -c 'KTSEQ waiting_started' "$base/logs/qs.log" || true; }
settle() { sleep 1; }

expect_fired() { # <description> <expected total count>
  local got
  got=$(fired)
  if [[ $got == "$2" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 (want $2 waiting_started so far, got $got)"
    failures=$((failures + 1))
  fi
}

echo "== first stream: priming line, then a rise"
wait_for_run 1
feed 1 5
settle
expect_fired "priming line does not fire" 0
feed 1 6
settle
expect_fired "rise fires" 1

echo "== stream exits and restarts with its counters at 0"
echo EXIT >>"$control/feed.1"
wait_for_run 2
feed 2 0
settle
expect_fired "priming line after the restart does not fire" 1
feed 2 1
settle
expect_fired "rise after the restart fires" 2

echo "== quiet stream restarts and repeats its old last line, then a rise"
echo EXIT >>"$control/feed.2"
wait_for_run 3
feed 3 1
settle
expect_fired "repeated line after the restart primes without firing" 2
feed 3 2
settle
expect_fired "rise after the repeated line fires" 3

echo "== exit with a visible run clears the state, so the module hides"
printf '%s\n' '{"text":"<span color=\"#fff\">2</span>","class":"running","tooltip":"RUNNING\tfixture","finished_seq":0,"waiting_seq":0}' >>"$control/feed.3"
settle
echo EXIT >>"$control/feed.3"
wait_for_run 4
settle
if grep -q 'KTSEQ exited runs=0 tooltip=\[\] counts=000 class=idle' "$base/logs/qs.log"; then
  echo "PASS  exit clears runs, tooltip, counts and class"
else
  echo "FAIL  exit left state behind: $(grep 'KTSEQ exited' "$base/logs/qs.log" | tail -1)"
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  echo "keeptabs-seq: $failures failed"
  exit 1
fi
echo "keeptabs-seq: all passed"
