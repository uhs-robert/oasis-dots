#!/usr/bin/env bash
# Starts a fleet: a detached tmux session with one window per bundle, each running a full-auto Claude session.
# Usage: launch.sh <fleet-session> <context-budget> <name>=<prompt-file>...
#   <fleet-session>   the new tmux session; refused when a session of that name exists
#   <context-budget>  tokens, exported as CLAUDE_CONTEXT_BUDGET so the context-budget hook sees it
#   <name>=<file>     one window per pair, named <name>, which is also the `claude -n` name; the prompt file is the
#                     filled launch-prompt.txt
# Exit 0 when every window shows its prompt, 2 on a bad argument, a single bundle or a clash (nothing was created),
# 3 when tmux failed
# part way (the new session is killed again), 4 when a window did not show its prompt within the confirm time (the
# fleet keeps running; look at the panes).
#
# It only creates the one new session and kills it again on failure. It never touches another one. (guard-tmux-socket.sh
# blocks only a bare `tmux kill-server`, so no script needs an exception to it.)
#
# A fleet is two or more bundles. For one orchestrator use ../orchestrator-handoff/spawn-orchestrator.sh: it keeps
# the caller's tmux session and lets the owner choose the model and the permission mode, which this script does not.
#
# The first bundle is the session's first window, so there is no spare empty window to name or close.
# The window command reads the prompt with $(cat 'file') instead of quoting the text, so it works under any
# default shell. The path is single-quoted with the POSIX escape, not printf %q, whose $'...' form is not POSIX.
set -uo pipefail
# shellcheck source=../orchestrator-handoff/window-names.sh
source "$(dirname "${BASH_SOURCE[0]}")/../orchestrator-handoff/window-names.sh"

usage() {
  echo "usage: launch.sh <fleet-session> <context-budget> <name>=<prompt-file>..." >&2
  exit 2
}
refuse() {
  echo "launch.sh: $*" >&2
  exit 2
}

# valid_session_name also allows . and :, which tmux reads as target separators in -t session:window.
tmux_safe_name() { valid_session_name "$1" && [[ $1 != *[.:]* ]]; }

[[ $# -ge 3 ]] || usage
fleet=$1 budget=$2
shift 2
tmux_safe_name "$fleet" || refuse "bad fleet session name: $fleet"
[[ $budget =~ ^[1-9][0-9]*$ ]] || refuse "the budget must be a number of tokens: $budget"

names=() files=()
for pair in "$@"; do
  name=${pair%%=*} file=${pair#*=}
  [[ $pair == *=* ]] || usage
  tmux_safe_name "$name" || refuse "bad window name: $name"
  # The name must also pass the grammar of `plans` session names (validate.py SESSION), so the session can claim.
  [[ $name =~ ^[a-z0-9][a-z0-9.]*(-[a-z0-9.]+)*-[a-z0-9]+$ ]] || refuse "not a plans session name (like df-help): $name"
  [[ $name != "$fleet" ]] || refuse "window name equals the fleet session name: $name"
  [[ " ${names[*]:-} " != *" $name "* ]] || refuse "name given twice: $name"
  [[ $file == /* && $file != *$'\n'* ]] || refuse "the prompt path must be absolute and on one line: $file"
  { [[ -s $file ]] && grep -q . "$file"; } || refuse "no prompt file, or it has no text: $file"
  names+=("$name")
  files+=("$file")
done

[[ ${#names[@]} -ge 2 ]] || refuse "a fleet needs two or more bundles; for one orchestrator run ~/.claude/skills/orchestrator-handoff/spawn-orchestrator.sh <name> <prompt-file>"

tmux has-session -t "=$fleet" 2>/dev/null && refuse "a tmux session named $fleet exists"
if existing=$(tmux list-windows -a -F '#{window_name}' 2>/dev/null); then
  for name in "${names[@]}"; do
    grep -qxF -- "$name" <<<"$existing" && refuse "a tmux window named $name exists"
  done
fi

git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir) || refuse "not in a git repository"
main_checkout=$(dirname "$git_common_dir")

command_for() { # <name> <prompt-file>
  local quoted=${2//\'/\'\\\'\'}
  echo "CLAUDE_CONTEXT_BUDGET=$budget claude -n $1 --permission-mode auto \"\$(cat '$quoted')\"; exec \${SHELL:-bash}"
}

# Only after new-session succeeded is the session ours to kill. If new-session fails, a session of that name can
# exist because another process made it in the gap since the check above, and it must stay.
abort() {
  echo "launch.sh: $* ; killing session $fleet" >&2
  tmux kill-session -t "=$fleet" 2>/dev/null
  exit 3
}

tmux new-session -d -s "$fleet" -n "${names[0]}" -c "$main_checkout" "$(command_for "${names[0]}" "${files[0]}")" || {
  echo "launch.sh: could not create the session" >&2
  exit 3
}
# A reused fleet name must not inherit the old watcher's state. A held lock means a watcher still runs: leave it.
for state in "$main_checkout"/.logs/*/fleet-watch-"$fleet".state; do
  [[ -e $state ]] || continue
  (flock -n 9 && rm -f "$state") 9>"${state%.state}.lock"
done
for i in "${!names[@]}"; do
  ((i == 0)) && continue
  tmux new-window -d -t "=$fleet:" -n "${names[i]}" -c "$main_checkout" "$(command_for "${names[i]}" "${files[i]}")" ||
    abort "could not create window ${names[i]}"
done

# Confirm each window started claude: a claude process runs under the pane's shell, or the pane shows the start of the
# prompt. The prompt alone is not enough, because a working session scrolls or redraws it away. #{pane_current_command}
# is no help: the window shell runs claude without job control, so tmux reports the shell. A window whose claude
# exited, or that shows neither signal after the wait, is reported, not fixed: the owner or planner looks at the pane.
confirm_seconds=${FLEET_CONFIRM_SECONDS:-45}
unconfirmed=0
for i in "${!names[@]}"; do
  # The first non-empty line: an empty marker would match any pane.
  head_of_prompt=$(grep -m1 . "${files[i]}" | cut -c1-20)
  seen=0
  for ((waited = 0; waited < confirm_seconds * 2; waited++)); do
    target="=$fleet:=${names[i]}"
    if pgrep -x -P "$(tmux display-message -p -t "$target" '#{pane_pid}' 2>/dev/null)" claude >/dev/null 2>&1 ||
      tmux capture-pane -p -t "$target" 2>/dev/null | grep -qF -- "$head_of_prompt"; then
      seen=1
      break
    fi
    sleep 0.5
  done
  if ((seen)); then
    echo "started ${names[i]}"
  else
    echo "UNCONFIRMED ${names[i]}: no claude runs in it and its pane does not show the prompt" >&2
    unconfirmed=1
  fi
done
echo "tmux switch-client -t $fleet"
exit $((unconfirmed ? 4 : 0))
