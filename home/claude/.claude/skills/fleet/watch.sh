#!/usr/bin/env bash
# Watches the sessions of a fleet: logs each one's state, nudges one that has stalled, stops when all are finished.
# Usage: watch.sh [--once] <fleet-session> <project>
#   default  loops until every fleet session is finished or a signal arrives (run it through Monitor)
#   --once   one pass, for /loop where the loop supplies the timing; the state carries over in a file
# Settings (environment): FLEET_STUCK_SECONDS (1800), FLEET_INTERVAL_SECONDS (600), FLEET_NUDGE_TEXT.
# Output: one line per event, nothing for a quiet pass, so Monitor wakes the model only for these:
#   NUDGED <name>   a stalled session got the nudge text
#   STALL <name>    a stalled session could not be nudged (text waiting in its prompt box, or no prompt box)
#   PROMPT <name>   a session waits on a permission prompt; the watchdog never answers it
#   EXITED <name>   a session left claude with no unfinished pieces
#   LOST <name>     a session left claude while it still owns unfinished pieces; it never counts as finished
#   FINISHED        every fleet session is finished; the watchdog has stopped
#   STOPPED         the fleet's tmux session is gone; the watchdog has stopped
#   INTERRUPTED     a signal arrived, as when Monitor expires; start the watchdog again, its state carries over
# The full per-session state goes to <main checkout>/.logs/<project>/fleet-watch.md, a line per session per pass and a
# line per nudge. The state between passes is fleet-watch-<fleet>.state beside it, with a lock of the same stem.
#
# Stuck means: the pane shows an empty prompt box, nothing moved in the pane, no commit on the session's branches and
# no change to its plan docs, .logs folders or branch worktree for the stuck time, and the session owns a piece in
# `building` status that is not waiting on anything (`waiting_on` empty).
# One stall gets one nudge: the stall ends only when the pane or the progress moves again.
#
# Watch only. It reads panes and plan docs, types only the nudge text, and only into an idle pane of the named fleet
# session where a claude process runs, found by pane id from that session's own window list. It never claims a
# piece, merges or answers a prompt.
# Like launch.sh, a sanctioned use of the owner's tmux server, since guard-tmux-socket.sh does not look inside scripts.
set -uo pipefail

once=0
if [[ ${1:-} == --once ]]; then
  once=1
  shift
fi
[[ $# -eq 2 ]] || {
  echo "usage: watch.sh [--once] <fleet-session> <project>" >&2
  exit 2
}
fleet=$1 project=$2
[[ $fleet =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ && $project =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "watch.sh: bad fleet session or project name" >&2
  exit 2
}
stuck_seconds=${FLEET_STUCK_SECONDS:-1800}
interval=${FLEET_INTERVAL_SECONDS:-600}
nudge_text=${FLEET_NUDGE_TEXT:-"Fleet watchdog: you look idle while a piece of yours is in building status. Continue it, or set waiting_on and say why you are held."}

main_checkout=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)") || {
  echo "watch.sh: not in a git repository" >&2
  exit 2
}
log_dir=$main_checkout/.logs/$project
mkdir -p "$log_dir"
log_file=$log_dir/fleet-watch.md
state_file=$log_dir/fleet-watch-$fleet.state
[[ -e $log_file ]] || printf '# Fleet watch: %s\n\n' "$fleet" >"$log_file"

# One watcher per fleet, so two of them never nudge the same stall. State and lock are per fleet, because two fleets
# can work on the same project.
lock_file=$log_dir/fleet-watch-$fleet.lock
exec 9>"$lock_file"
flock -n 9 || {
  echo "watch.sh: another watcher holds $lock_file" >&2
  exit 0
}

log() { printf -- '- %s %s\n' "$(date +%FT%T)" "$*" >>"$log_file"; }

sleeper=
on_signal() {
  [[ -z $sleeper ]] || kill "$sleeper" 2>/dev/null
  log "interrupted by a signal"
  echo INTERRUPTED
  exit 0
}
trap on_signal INT TERM

# Per window, from the state file: the pane hash, when it last changed, whether the session ever owned a piece, and
# the hash and time at which a stall event was last handled (acted_*).
declare -A hash changed_at ever_owned acted_hash acted_at
load_state() {
  local name h c e ah aa
  [[ -f $state_file ]] || return 0
  while IFS=$'\t' read -r name h c e ah aa; do
    [[ -n $name ]] || continue
    hash[$name]=$h changed_at[$name]=$c ever_owned[$name]=$e acted_hash[$name]=$ah acted_at[$name]=$aa
  done <"$state_file"
}
save_state() {
  local name
  for name in "${!changed_at[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "${hash[$name]:-}" "${changed_at[$name]:-0}" "${ever_owned[$name]:-0}" "${acted_hash[$name]:-}" "${acted_at[$name]:-0}"
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

# Claude is the pane's process or runs below it. A shell prompt or a shell with background jobs is not claude.
claude_runs_in() { # <pid>
  local pid=$1 child
  [[ $(ps -o comm= -p "$pid" 2>/dev/null) == claude ]] && return 0
  for child in $(pgrep -P "$pid"); do
    claude_runs_in "$child" && return 0
  done
  return 1
}

hash_of() { printf '%s' "$1" | cksum | cut -d' ' -f1; }

nudge() { # <pane id> <name>
  tmux send-keys -t "$1" -l "$nudge_text" || return 1
  # Text and Enter in one call leaves the text unsent in the prompt box, so Enter follows after a pause.
  sleep 0.5
  tmux send-keys -t "$1" Enter
}

pass() {
  local now windows pane name dead pane_pid text new_hash docs ids active building state quiet progress
  now=$(date +%s)
  windows=$(tmux list-windows -t "=$fleet" -F '#{pane_id}|#{window_name}|#{pane_dead}|#{pane_pid}' 2>/dev/null) || return 2
  load_state
  all_finished=1
  while IFS='|' read -r pane name dead pane_pid; do
    [[ -n $name ]] || continue
    text=$(tmux capture-pane -p -t "$pane" 2>/dev/null)
    new_hash=$(hash_of "$text")
    # A failed lookup is not an empty list: an empty list would read as "owns nothing" and let the fleet finish.
    if ! docs=$(plans ls --owner "$name" --project "$project" --json 2>/dev/null) || [[ -z $docs ]]; then
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
          echo "LOST $name"
        else
          log "$name EXITED claude exited, no unfinished pieces"
          echo "EXITED $name"
        fi
        acted_hash[$name]=$new_hash acted_at[$name]=$now
      fi
      ;;
    prompt)
      if [[ -z ${acted_hash[$name]:-} ]]; then
        log "$name PROMPT waits on a permission prompt; not answered"
        echo "PROMPT $name"
        acted_hash[$name]=$new_hash acted_at[$name]=$now
      fi
      ;;
    stuck)
      if [[ -z ${acted_hash[$name]:-} ]]; then
        if prompt_box_empty "$text" && nudge "$pane" "$name"; then
          log "$name NUDGE sent: $nudge_text"
          echo "NUDGED $name"
        else
          log "$name STALL not nudged: text in the prompt box, no prompt box or send failed"
          echo "STALL $name"
        fi
        # The nudge changes the pane, so the stall is keyed to the pane as it is after the nudge.
        sleep 1
        acted_hash[$name]=$(hash_of "$(tmux capture-pane -p -t "$pane" 2>/dev/null)")
        acted_at[$name]=$(date +%s)
        hash[$name]=${acted_hash[$name]}
      fi
      ;;
    esac

    # Finished: left claude with nothing unfinished, or went idle after owning pieces that are all merged, closed or
    # held for the owner. A session that left claude with unfinished pieces is lost, not finished.
    if [[ $state == exited ]]; then
      ((active == 0)) || all_finished=0
    elif [[ $state != idle ]] || [[ ${ever_owned[$name]:-0} != 1 ]] || ((active > 0)); then
      all_finished=0
    fi
    state=
  done <<<"$windows"
  save_state
  return 0
}

while :; do
  pass
  rc=$?
  if ((rc == 2)); then
    log "fleet session $fleet is gone"
    echo STOPPED
    exit 0
  fi
  if ((all_finished)); then
    log "all fleet sessions finished"
    echo FINISHED
    exit 0
  fi
  ((once)) && exit 0
  sleep "$interval" &
  sleeper=$!
  wait "$sleeper"
  sleeper=
done
