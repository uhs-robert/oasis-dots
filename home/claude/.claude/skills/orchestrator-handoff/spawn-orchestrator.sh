#!/usr/bin/env bash
# Starts one new orchestrator session: a new window in the caller's own tmux session, in the main checkout of the
# current repo, running `claude -n <name>` with the prompt read from a file. Any agent may run it.
# Usage: spawn-orchestrator.sh <name> <prompt-file> [--model M] [--budget N]
#   <name>         the window name and the `claude -n` name; a `plans` session name such as df-help
#   <prompt-file>  absolute path to the first prompt; it must have text
#   --model M      passed to claude's --model. Pass the model the owner asked for. Without it claude picks its default.
#   --budget N     context budget in tokens, exported as CLAUDE_CONTEXT_BUDGET as launch.sh does
# No permission mode flag: the new session asks as any session does. For two or more full-auto sessions in one
# new tmux session use ../fleet/launch.sh instead.
# Exit 0 on success, 2 on a bad argument or a name clash (nothing was created), 3 outside tmux, 4 when tmux failed.
#
# The caller's window keeps its name. guard-tmux-socket.sh blocks only a bare `tmux kill-server`, so this script
# needs no exception to it.
# The window command reads the prompt with $(cat 'file') instead of quoting the text, so it works under any
# default shell. The path is single-quoted with the POSIX escape, not printf %q, whose $'...' form is not POSIX.
set -uo pipefail
# shellcheck source=window-names.sh
source "$(dirname "${BASH_SOURCE[0]}")/window-names.sh"

usage() {
  echo "usage: spawn-orchestrator.sh <name> <prompt-file> [--model M] [--budget N]" >&2
  echo "  Pass --model with the model the owner asked for; without it claude uses its default." >&2
  exit 2
}
refuse() {
  echo "spawn-orchestrator.sh: $*" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
name=$1 file=$2
shift 2
model="" budget=""
while (($#)); do
  case $1 in
    --model) [[ $# -ge 2 ]] || usage; model=$2; shift 2 ;;
    --budget) [[ $# -ge 2 ]] || usage; budget=$2; shift 2 ;;
    *) usage ;;
  esac
done

# valid_session_name also allows . and :, which tmux reads as target separators in -t session:window.
valid_session_name "$name" && [[ $name != *[.:]* ]] || refuse "bad window name: $name"
# The name must also pass the grammar of `plans` session names (validate.py SESSION), so the session can claim.
[[ $name =~ ^[a-z0-9][a-z0-9.]*(-[a-z0-9.]+)*-[a-z0-9]+$ ]] || refuse "not a plans session name (like df-help): $name"
[[ -z $model ]] || [[ $model =~ ^[A-Za-z0-9][]A-Za-z0-9._:/[-]*$ ]] || refuse "bad model: $model"
[[ -z $budget ]] || [[ $budget =~ ^[1-9][0-9]*$ ]] || refuse "the budget must be a number of tokens: $budget"
[[ $file == /* && $file != *$'\n'* ]] || refuse "the prompt path must be absolute and on one line: $file"
{ [[ -s $file ]] && grep -q . "$file"; } || refuse "no prompt file, or it has no text: $file"
[[ -n ${TMUX:-} && -n ${TMUX_PANE:-} ]] || {
  echo "spawn-orchestrator.sh: not inside tmux; ask the owner to start the session by hand" >&2
  exit 3
}

git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir) || refuse "not in a git repository"
main_checkout=$(dirname "$git_common_dir")
session=$(tmux display-message -p -t "$TMUX_PANE" '#S') || {
  echo "spawn-orchestrator.sh: could not read the tmux session" >&2
  exit 4
}

if existing=$(tmux list-windows -a -F '#{window_name}' 2>/dev/null); then
  ! grep -qxF -- "$name" <<<"$existing" || refuse "a tmux window named $name exists"
fi

quoted=${file//\'/\'\\\'\'}
command="claude -n $name"
[[ -z $model ]] || command="$command --model $model"
command="$command \"\$(cat '$quoted')\"; exec \${SHELL:-bash}"
[[ -z $budget ]] || command="CLAUDE_CONTEXT_BUDGET=$budget $command"

tmux new-window -d -t "$session:" -n "$name" -c "$main_checkout" "$command" || {
  echo "spawn-orchestrator.sh: could not create the window" >&2
  exit 4
}
echo "opened window $name in tmux session $session"
