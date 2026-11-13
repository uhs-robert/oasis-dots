#!/usr/bin/env bash
# One check of a fleet's sessions, for a planner that sleeps between checks and wakes only on a problem.
# Usage: watch.sh <fleet-session> <project>
#        watch.sh --nudge <fleet-session> <project> <name>
# Output, and the exit status is 0 for all of these:
#   ok             every session is moving or already handled; the planner's loop keeps sleeping
#   all finished   every fleet session is finished
#   one line per problem, each wakes the planner once per stall:
#     STUCK <name>    idle with an empty prompt box, no activity for the stuck time, a `building` piece with
#                     `waiting_on` empty
#     PROMPT <name>   waits on a permission prompt; never answered by this script
#     EXITED <name>   left claude with no unfinished pieces
#     LOST <name>     left claude while it still owns unfinished pieces; never counts as finished
#     STOPPED <fleet> the fleet's tmux session is gone
# A stall that was reported prints `ok` on later checks until the pane or the progress moves again, so a loop that
# restarts after the planner handled it does not wake on it twice. The state between checks is
# <main checkout>/.logs/<project>/fleet-watch-<fleet>.state, with a lock of the same stem. The log is fleet-watch.md
# beside it: a line per session per check, and each problem.
# Settings (environment): FLEET_STUCK_SECONDS (1800), FLEET_NUDGE_TEXT, FLEET_ALL_PROJECTS (set to 1 to find a
# session's docs in every plan project, for a fleet whose pieces span projects; <project> still names the log).
#
# Stuck means: the pane shows an empty prompt box, nothing moved in the pane, no commit on the session's branches and
# no change to its plan docs, .logs folders or branch worktree for the stuck time, and the session owns a piece in
# `building` status that is not waiting on anything (`waiting_on` empty). The stuck time spans several checks, so the
# state file carries when the pane last changed.
#
# Never types into a pane by default. The planner nudges through SendMessage. `--nudge` is the fallback for a session
# that holds SendMessage for approval: it types the nudge text into the named window, only when that window is idle
# with an empty prompt box and a claude process below it, and logs the nudge.
# Like launch.sh, a sanctioned use of the owner's tmux server, since guard-tmux-socket.sh does not look inside scripts.
set -uo pipefail
# shellcheck source=claude-runs-in.sh
source "$(dirname "${BASH_SOURCE[0]}")/claude-runs-in.sh"

mode=check
if [[ ${1:-} == --nudge ]]; then
  mode=nudge
  shift
fi
usage() {
  echo "usage: watch.sh <fleet-session> <project> | watch.sh --nudge <fleet-session> <project> <name>" >&2
  exit 2
}
if [[ $mode == nudge ]]; then
  [[ $# -eq 3 ]] || usage
  target=$3
  [[ $target =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || {
    echo "watch.sh: bad window name" >&2
    exit 2
  }
else
  [[ $# -eq 2 ]] || usage
fi
fleet=$1 project=$2
[[ $fleet =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ && $project =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "watch.sh: bad fleet session or project name" >&2
  exit 2
}
stuck_seconds=${FLEET_STUCK_SECONDS:-1800}
nudge_text=${FLEET_NUDGE_TEXT:-"Fleet watchdog: you look idle while a piece of yours is in building status. Continue it, or set waiting_on and say why you are held."}

git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir) || {
  echo "watch.sh: not in a git repository" >&2
  exit 2
}
main_checkout=$(dirname "$git_common_dir")
log_dir=$main_checkout/.logs/$project
# --owner already scopes the docs to one session, so dropping --project loses nothing.
project_filter=(--project "$project")
[[ ${FLEET_ALL_PROJECTS:-} == 1 ]] && project_filter=()
mkdir -p "$log_dir"
log_file=$log_dir/fleet-watch.md
state_file=$log_dir/fleet-watch-$fleet.state
[[ -e $log_file ]] || printf '# Fleet watch: %s\n\n' "$fleet" >"$log_file"

# One check per fleet at a time, so two of them never report the same stall. State and lock are per fleet, because
# two fleets can work on the same project.
lock_file=$log_dir/fleet-watch-$fleet.lock
exec 9>"$lock_file"
flock -n 9 || {
  if [[ $mode == nudge ]]; then
    echo "NOT NUDGED: a check holds the lock, try again"
    exit 1
  fi
  # The other check reports the problems, so this one has nothing to add.
  echo ok
  exit 0
}

log() { printf -- '- %s %s\n' "$(date +%FT%T)" "$*" >>"$log_file"; }

# Per window, from the state file: the pane hash, when it last changed, whether the session ever owned a piece, and
# the hash and time at which a stall event was last handled (acted_*).
declare -A hash changed_at ever_owned acted_hash acted_at
load_state() {
  local name h c e ah aa
  [[ -f $state_file ]] || return 0
  while IFS=$'\t' read -r name h c e ah aa; do
    [[ -n $name ]] || continue
    # An empty field is stored as "-": read with a tab separator folds empty fields and shifts the rest.
    [[ $ah != - ]] || ah=
    hash[$name]=$h changed_at[$name]=$c ever_owned[$name]=$e acted_hash[$name]=$ah acted_at[$name]=$aa
  done <"$state_file"
}
save_state() {
  local name
  for name in "${!changed_at[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "${hash[$name]:-}" "${changed_at[$name]:-0}" "${ever_owned[$name]:-0}" "${acted_hash[$name]:--}" "${acted_at[$name]:-0}"
  done >"$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# The newest sign of work by the owner of these docs: a commit on its branch, or a change to a plan doc or .logs file.
# The worktree where a branch is checked out, if any.
worktree_of() { # <branch>
  git -C "$main_checkout" worktree list --porcelain 2>/dev/null |
    awk -v b="refs/heads/$1" '/^worktree /{p=substr($0, 10)} $1 == "branch" && $2 == b {print p; exit}'
}

# A session can wait on its own background build for longer than the stuck time with no commit, so a file changed
# in the worktree of its branch counts as work too. One recent file is enough, so find stops at the first.
latest_progress() { # <json of the session's docs>
  local best=0 t id branch path worktree
  while IFS=$'\t' read -r id branch path; do
    worktree=
    [[ -z $branch || $branch == none ]] || worktree=$(worktree_of "$branch")
    for t in $(stat -c %Y "$path" 2>/dev/null) \
      $(find "$log_dir/$id" -type f -printf '%Ts\n' 2>/dev/null) \
      $([[ -n $branch && $branch != none ]] && git -C "$main_checkout" log -1 --format=%ct "$branch" -- 2>/dev/null) \
      $([[ -n $worktree ]] && find "$worktree" \( -name .git -o -name node_modules \) -prune -o -type f -newermt "@$(($(date +%s) - stuck_seconds))" -printf '%Ts\n' -quit 2>/dev/null); do
      ((t > best)) && best=$t
    done
  done < <(jq -r '.[] | [.id, .branch, .path] | @tsv' <<<"$1")
  echo "$best"
}

# The last prompt box line of the pane is empty: the owner or the session left no typed text there.
prompt_box_empty() {
  local line
  line=$(grep '^❯' <<<"$1" | tail -n 1) || return 1
  # The real prompt box follows the ❯ with a no-break space, which [[:space:]] does not match in every locale.
  line=${line#❯}
  line=${line//$'\xc2\xa0'/ }
  [[ $line =~ ^[[:space:]]*$ ]]
}

hash_of() { printf '%s' "$1" | cksum | cut -d' ' -f1; }

# The fallback for SendMessage: the guarded typing of the nudge text into one window of the fleet session.
nudge() { # <window name>
  local row pane dead pane_pid text
  load_state
  row=$(tmux list-windows -t "=$fleet" -F '#{pane_id}|#{window_name}|#{pane_dead}|#{pane_pid}' 2>/dev/null |
    awk -F'|' -v n="$1" '$2 == n {print; exit}')
  [[ -n $row ]] || {
    echo "NOT NUDGED $1: no such window in $fleet"
    return 1
  }
  IFS='|' read -r pane _ dead pane_pid <<<"$row"
  text=$(tmux capture-pane -p -t "$pane" 2>/dev/null)
  if [[ $dead == 1 ]] || ! claude_runs_in "$pane_pid"; then
    echo "NOT NUDGED $1: no claude process in the pane"
  elif grep -qE 'Do you want to|❯ 1\. |\(y/n\)' <<<"$(tail -n 15 <<<"$text")"; then
    echo "NOT NUDGED $1: a permission prompt is on screen"
  elif grep -qE '… \([0-9]+(m [0-9]+)?s' <<<"$text"; then
    echo "NOT NUDGED $1: the session is busy"
  elif ! prompt_box_empty "$text"; then
    echo "NOT NUDGED $1: text in the prompt box, or no prompt box"
  elif [[ -z ${acted_hash[$1]:-} || ${acted_hash[$1]} != "$(hash_of "$text")" ]]; then
    # The check that reported the stall stored the pane as it saw it. Any other pane is not that stall.
    echo "NOT NUDGED $1: the pane is not as the last check reported it stuck"
  else
    tmux send-keys -t "$pane" -l "$nudge_text" || return 1
    # Text and Enter in one call leaves the text unsent in the prompt box, so Enter follows after a pause.
    sleep 0.5
    tmux send-keys -t "$pane" Enter
    log "$1 NUDGE sent: $nudge_text"
    echo "NUDGED $1"
    return 0
  fi
  log "$1 NOT NUDGED"
  return 1
}

pass() {
  local now windows pane name dead pane_pid text new_hash docs ids active building state quiet progress
  now=$(date +%s)
  windows=$(tmux list-windows -t "=$fleet" -F '#{pane_id}|#{window_name}|#{pane_dead}|#{pane_pid}' 2>/dev/null) || return 2
  load_state
  all_finished=1
  declare -A seen=()
  while IFS='|' read -r pane name dead pane_pid; do
    [[ -n $name ]] || continue
    seen[$name]=1
    text=$(tmux capture-pane -p -t "$pane" 2>/dev/null)
    new_hash=$(hash_of "$text")
    # A failed lookup is not an empty list: an empty list would read as "owns nothing" and let the fleet finish.
    if ! docs=$(plans ls --owner "$name" "${project_filter[@]}" --json 2>/dev/null) || [[ -z $docs ]]; then
      log "$name plans ls failed; session skipped this pass"
      all_finished=0
      continue
    fi
    ids=$(jq -r '[.[].id] | join(",")' <<<"$docs")
    building=$(jq '[.[] | select(.status == "building" and .waiting_on == "")] | length' <<<"$docs")
    active=$(jq '[.[] | select(.status == "approved" or .status == "building" or (.status == "review" and .waiting_on == ""))] | length' <<<"$docs")
    [[ -z $ids ]] || ever_owned[$name]=1
    progress=$(latest_progress "$docs")

    # Moved since the last pass, or since a handled stall: the pane changed, or the piece's files did.
    if [[ ${hash[$name]:-} != "$new_hash" ]]; then
      [[ -z ${hash[$name]:-} ]] || state=busy
      changed_at[$name]=$now
    fi
    if [[ -n ${acted_hash[$name]:-} ]] && { [[ ${acted_hash[$name]} != "$new_hash" ]] || ((progress > ${acted_at[$name]:-0})); }; then
      acted_hash[$name]='' acted_at[$name]=0
    fi
    hash[$name]=$new_hash

    # tmux names the foreground process group by its leader, which for `sh -c "claude ...; exec zsh"` is the shell
    # even while claude runs, so the pane command says nothing. Only a claude process below the pane makes it a
    # session. Without one, the pane is the `exec zsh` after claude exited, and nothing is typed into it.
    if [[ $dead == 1 ]] || ! claude_runs_in "$pane_pid"; then
      state=exited
    elif grep -qE 'Do you want to|❯ 1\. |\(y/n\)' <<<"$(tail -n 15 <<<"$text")"; then
      state=prompt
    elif grep -qE '… \([0-9]+(m [0-9]+)?s' <<<"$text"; then
      state=busy
    elif [[ ${state:-} != busy ]]; then
      state=idle
    fi

    quiet=$((now - changed_at[$name]))
    ((progress > now - quiet)) && quiet=$((now - progress))
    if [[ $state == idle ]] && ((building > 0 && quiet >= stuck_seconds)); then
      state=stuck
    fi
    log "$name $state pieces=${ids:--} active=$active quiet=$((quiet / 60))m"

    case $state in
    exited)
      if [[ -z ${acted_hash[$name]:-} ]]; then
        if ((active > 0)); then
          log "$name LOST claude exited with unfinished pieces: $ids"
          problems+=("LOST $name: claude exited with unfinished pieces: $ids")
        elif [[ ${ever_owned[$name]:-0} != 1 ]]; then
          log "$name LOST claude exited before its first claim"
          problems+=("LOST $name: claude exited before its first claim")
        else
          log "$name EXITED claude exited, no unfinished pieces"
          problems+=("EXITED $name: claude exited, no unfinished pieces")
        fi
        acted_hash[$name]=$new_hash acted_at[$name]=$now
      fi
      ;;
    prompt)
      if [[ -z ${acted_hash[$name]:-} ]]; then
        log "$name PROMPT waits on a permission prompt; not answered"
        problems+=("PROMPT $name: waits on a permission prompt, not answered")
        acted_hash[$name]=$new_hash acted_at[$name]=$now
      fi
      ;;
    stuck)
      if [[ -z ${acted_hash[$name]:-} ]]; then
        log "$name STUCK idle ${quiet}s with a building piece: $ids"
        problems+=("STUCK $name: idle $((quiet / 60))m with a building piece: $ids")
        acted_hash[$name]=$new_hash acted_at[$name]=$now
      fi
      ;;
    esac

    # Finished: left claude with nothing unfinished, or went idle after owning pieces that are all merged, closed or
    # held for the owner. A session that left claude with unfinished pieces is lost, not finished.
    if [[ $state == exited ]]; then
      ((active == 0)) && [[ ${ever_owned[$name]:-0} == 1 ]] || all_finished=0
    elif [[ $state != idle ]] || [[ ${ever_owned[$name]:-0} != 1 ]] || ((active > 0)); then
      all_finished=0
    fi
    state=
  done <<<"$windows"
  # A window that was there on an earlier check and is gone now: its pieces still count, so the fleet is not
  # finished on the windows that remain.
  for name in "${!changed_at[@]}"; do
    [[ -z ${seen[$name]:-} ]] || continue
    if ! docs=$(plans ls --owner "$name" "${project_filter[@]}" --json 2>/dev/null) || [[ -z $docs ]]; then
      log "$name window gone and plans ls failed"
      all_finished=0
      continue
    fi
    ids=$(jq -r '[.[].id] | join(",")' <<<"$docs")
    active=$(jq '[.[] | select(.status == "approved" or .status == "building" or (.status == "review" and .waiting_on == ""))] | length' <<<"$docs")
    [[ -z $ids ]] || ever_owned[$name]=1
    if ((active > 0)) || [[ ${ever_owned[$name]:-0} != 1 ]]; then
      all_finished=0
      if [[ -z ${acted_hash[$name]:-} ]]; then
        log "$name GONE window closed; unfinished pieces: ${ids:--}"
        problems+=("GONE $name: its window is closed, unfinished pieces: ${ids:--}")
        acted_hash[$name]=gone acted_at[$name]=$(date +%s)
      fi
    else
      acted_hash[$name]='' acted_at[$name]=0
    fi
  done
  save_state
  return 0
}

problems=()
if [[ $mode == nudge ]]; then
  nudge "$target"
  exit $?
fi
pass
if (($? == 2)); then
  log "fleet session $fleet is gone"
  echo "STOPPED $fleet: the fleet's tmux session is gone"
  exit 0
fi
if ((${#problems[@]})); then
  printf '%s\n' "${problems[@]}"
elif ((all_finished)); then
  log "all fleet sessions finished"
  echo "all finished"
else
  echo ok
fi
