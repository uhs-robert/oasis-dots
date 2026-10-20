#!/usr/bin/env bash
# Usage: main-check.sh run [--notify] <after> <check_from> | wait | status
# The check of main after a merge. ship-batch.sh starts `run` detached (systemd-run, else setsid) and returns; an agent that
# needs a green main runs `wait`. Stopped mid-run (SIGTERM, which a newer batch does), `run` writes no result, settles
# nothing and exits 143, so the owed base stays and the next check starts from it. `run` exits 1 when the check fails, 3
# when another check already runs and 4 when it passed but the main checkout's tracked files did not match `after`.
set -uo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
# shellcheck source=base.sh
source "$(dirname "$0")/base.sh"

log=$(main_check_path "$repo" log)
result=$(main_check_path "$repo" result)

write_result() {
  printf '%s\n' "$*" >"$result.tmp.$$" && mv -f "$result.tmp.$$" "$result"
}

# Checks from the oldest base still owed, so a rerun after a failed or interrupted check costs only the steps that did not
# pass. Whether a pass made in a branch worktree counts for main depends on repos/: a worktree has none, so
# lib/check/steps/symlinks.sh skipped the links into it. Such a pass vouches for everything but those links, so main runs only
# that step; lib/check/passed.sh is-passed accepts the pass outright only when it was made with repos/.
# Inductive: a full pass of the base plus a scoped pass over everything changed since vouches for `after`. A base main
# does not descend from or not recorded as passed, or CHECK_FULL=1, falls back to the full check.
# The skips vouch for main's commit, not its working tree, so local edits or untracked files in the main checkout rule them out.
run_checks() {
  local after=$1 check_from=$2 main_clean=false
  [[ -z $(git status --porcelain) ]] && main_clean=true
  if $main_clean && [[ -z ${CHECK_FULL:-} ]] && lib/check/passed.sh is-passed "$after"; then
    echo "main-check: main's tree already passed the check; not checking it again"
  elif $main_clean && [[ -z ${CHECK_FULL:-} ]] && lib/check/passed.sh passed-somewhere "$after"; then
    echo "main-check: main's tree passed the check in a worktree; checking only the links into repos/"
    sh lib/check/steps/symlinks.sh
  elif [[ -z ${CHECK_FULL:-} ]] && base_is_ancestor "$repo" "$check_from" "$after" && lib/check/passed.sh is-passed "$check_from"; then
    lib/check.sh --changed "$check_from"
  else
    just check
  fi
}

# True when the check is only a lookup or the symlinks step, which costs seconds: ship-batch runs it in the foreground.
is_quick() {
  [[ -z ${CHECK_FULL:-} && -z $(git -C "$repo" status --porcelain) ]] &&
    (cd "$repo" && { lib/check/passed.sh is-passed "$1" || lib/check/passed.sh passed-somewhere "$1"; })
}

cmd_run() {
  local notify=false after check_from checks_passed=true ship_lock
  [[ ${1:-} != --notify ]] || {
    notify=true
    shift
  }
  after=${1:?after} check_from=${2:?check_from}
  exec 8<>"$(main_check_path "$repo" lock)"
  flock -n 8 || {
    echo "main-check: a check of main is already running" >&2
    exit 3
  }
  echo $$ >"$(main_check_path "$repo" pid)"
  # bash runs this once the foreground command ends, so a stopped check exits before it can record a failure.
  trap 'exit 143' TERM INT
  # The run lock is closed for everything this starts: a daemon a step leaves behind (a shadow's Hyprland or qs) would
  # otherwise hold it and read as a check running forever. Such a daemon also keeps the log open, so the log is truncated
  # once and then only appended to: a write at the old offset would leave the next check's log full of NULs.
  : >"$log"
  if $notify; then
    exec >>"$log" 2>&1
  else
    # The foreground check also shows on ship-batch's output. tee ignores the stop's TERM, which reaches the whole group:
    # dead, it would turn bash's "Terminated" report on the killed step into a SIGPIPE that ends this shell before the
    # trap runs. It still ends with this shell, at end of file.
    exec > >(
      trap '' TERM INT
      exec tee -a "$log" 8>&-
    ) 2>&1
  fi
  cd "$repo" || exit 1
  echo "main-check: checking ${after:0:12} from ${check_from:0:12}"
  run_checks "$after" "$check_from" 8>&- || checks_passed=false

  # Under the ship lock, so a batch cannot owe a newer base between the HEAD test and the settle. A batch that holds the
  # lock stops this process first, which ends the wait.
  ship_lock="$(dirname "$log")/ship-batch.lock"
  exec 6<>"$ship_lock"
  flock 6
  if [[ $(git rev-parse HEAD) != "$after" ]]; then
    # Another batch may have merged and pulled while this check ran, changing the files under it: the result says nothing
    # about main and the debt stays.
    echo "main-check: main moved during the check; the check from ${check_from:0:12} is still owed, and the next ship-batch run makes it"
  elif $checks_passed && lib/check/passed.sh record; then
    settle_check "$repo"
    write_result "pass $after $(date +%s)"
    echo "main-check: passed"
  elif $checks_passed; then
    # The helper refuses a tree whose tracked files differ from HEAD's: work in the main checkout, before or during the
    # check, means the pass was of that working tree, not of `after`.
    write_result "unrecorded $after $(date +%s) $log"
    echo "main-check: passed, but not as ${after:0:12}: tracked files in the main checkout differ from it; the check of ${check_from:0:12} stays owed"
    exit 4
  else
    write_result "fail $after $(date +%s) $log"
    echo "main-check: FAILED; the check of ${check_from:0:12} stays owed"
    # Released first: a notification daemon that is slow to activate would hold up every batch.
    exec 6>&-
    ! $notify || notify-send -u critical "main check failed" "${after:0:12}: $log" 8>&- 2>/dev/null || true
    exit 1
  fi
}

# Blocks until no check runs (at most MAIN_CHECK_WAIT_SECS for each lock, and for a suspension), then reports whether main
# is green: 0 when nothing is owed, 1 when the last check failed or a check is owed but not running. The ship lock is taken
# once as a barrier, since a batch stops and restarts the check while holding it and the gap in between must not read as
# "not running"; a batch that stopped it for its branch checks holds no lock, and its suspended marker stands in for it.
cmd_wait() {
  local owed wait_s=${MAIN_CHECK_WAIT_SECS:-1800} suspended_until=''
  while :; do
    flock -w "$wait_s" "$(main_check_path "$repo" lock)" true || {
      echo "main-check: the check of main has run for too long; see $log" >&2
      return 1
    }
    flock -w "$wait_s" "$(dirname "$log")/ship-batch.lock" true || {
      echo "main-check: a ship-batch has held the main checkout for too long" >&2
      return 1
    }
    main_check_is_running "$repo" && continue
    [[ -n $(main_check_suspended_by "$repo") ]] || break
    : "${suspended_until:=$((SECONDS + wait_s))}"
    ((SECONDS < suspended_until)) || {
      echo "main-check: a ship-batch has kept the check of main stopped for too long" >&2
      return 1
    }
    sleep 1
  done
  owed=$(owed_check "$repo")
  [[ -n $owed ]] || {
    echo "main-check: nothing owed; main's last check passed or none was needed"
    return 0
  }
  if [[ -s $result && $(cut -d' ' -f1 "$result") == fail ]]; then
    main_check_failure_notice "$repo"
    tail -n 20 "$log" 2>/dev/null
  elif [[ -s $result && $(cut -d' ' -f1 "$result") == unrecorded ]]; then
    echo "main-check: the last check passed a main checkout with local changes to tracked files, which says nothing about main; the check from ${owed:0:12} is still owed. Commit or revert them, then run ship-batch.sh with no arguments"
  else
    echo "main-check: a check from ${owed:0:12} is owed but none is running; run ship-batch.sh with no arguments to start it"
  fi
  return 1
}

cmd_status() {
  local owed suspended_by
  suspended_by=$(main_check_suspended_by "$repo")
  if main_check_is_running "$repo"; then
    echo "running; log $log"
  elif [[ -n $suspended_by ]]; then
    echo "stopped while ship-batch (pid $suspended_by) checks its branches; it starts the check again"
  else
    echo "not running"
  fi
  owed=$(owed_check "$repo")
  echo "owed from: ${owed:-nothing}"
  echo "last result: $(cat "$result" 2>/dev/null || echo none)"
}

case ${1:-} in
run)
  shift
  cmd_run "$@"
  ;;
quick)
  shift
  is_quick "$@"
  ;;
wait) cmd_wait ;;
status) cmd_status ;;
*)
  echo "usage: main-check.sh run [--notify] <after> <check_from> | quick <after> | wait | status" >&2
  exit 2
  ;;
esac
