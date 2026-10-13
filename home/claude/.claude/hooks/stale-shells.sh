#!/usr/bin/env bash
# SubagentStop: refuse to let an agent finish while one of this session's Bash shells has sat for a long time with a
# process blocked reading a pipe or terminal that nothing will ever write to (a `cat` waiting on a heredoc that never
# came). Such a shell kept two agents listed as running for hours after their work was done.
# A shell that is sleeping (a deliberate wait loop) or waiting on the network is not stuck, and is left alone.
set -u
input=$(cat)
# One nudge per stop: if the agent was already sent back once, let it finish.
[[ $(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null) == true ]] && exit 0

min_age=${STALE_SHELLS_MIN_AGE:-900}

# The Claude Code process this hook runs under owns every Bash shell of the session, its agents' included.
claude_pid() {
  local pid=$$ comm
  while ((pid > 1)); do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
    [[ $comm == claude ]] && { echo "$pid"; return 0; }
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  done
  return 1
}
root=${STALE_SHELLS_ROOT_PID:-$(claude_pid)} || exit 0
[[ -n $root ]] || exit 0

descendants() {
  local child
  for child in $(pgrep -P "$1"); do
    echo "$child"
    descendants "$child"
  done
}

report=""
for shell in $(pgrep -P "$root"); do
  args=$(tr '\0' ' ' <"/proc/$shell/cmdline" 2>/dev/null) || continue
  [[ $args == *shell-snapshots* ]] || continue
  age=$(ps -o etimes= -p "$shell" | tr -d ' ')
  [[ -n $age ]] || continue
  ((age >= min_age)) || continue
  for pid in $(descendants "$shell"); do
    wchan=$(cat "/proc/$pid/wchan" 2>/dev/null)
    # Kernel versions name the wait differently: pipe_read, anon_pipe_read, pipe_wait_readable, n_tty_read.
    [[ $wchan == *pipe_read* || $wchan == *pipe_wait_readable* || $wchan == *tty_read* ]] || continue
    what=$(ps -o args= -p "$pid" | cut -c1-60)
    started=$(grep -oE "eval '[^']{0,80}" <<<"$args" | cut -c7-)
    report+="  shell $shell, $((age / 60)) min old, '$what' blocked reading input; started as: ${started:-unknown}"$'\n'
    break
  done
done

[[ -n $report ]] || exit 0
printf 'Background shells from this session are stuck waiting for input that will never come:\n%sStop them (kill the shell pid, or TaskStop the background task) before finishing, so nothing is left running.\n' \
  "$report" >&2
exit 2
