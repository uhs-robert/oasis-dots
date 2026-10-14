# shellcheck shell=sh
# The machine-wide check lock, shared by lib/check.sh and the voxcmd suites (home/voxcmd/tests/run*.sh). Sourced, not run.
#
# check_lock_take <owner>: holds the lock on fd 7 for the rest of the calling shell. It waits at most CHECK_LOCK_WAIT_SECS
# (default 1200) for a holder, then returns 1 naming it. It returns 0 at once when CHECK_LOCK_HELD is set (an ancestor holds
# the lock), CHECK_NO_LOCK is set, or flock is missing. The lock file stays in the real runtime dir inside the voxcmd
# sandbox, whose XDG_RUNTIME_DIR is its own.
#
# check_lock_gate <owner> <script> [args...]: for a suite's entry. When the lock is not already held here, it takes the lock,
# runs <script> again as a child with fd 7 closed, and exits with the child's status. The child finds CHECK_LOCK_HELD set and
# returns at once. Closing fd 7 for the body means a daemon the suite leaves behind cannot keep the lock: the holder is the
# parent, which exits only after the child has.
check_lock_take() {
  owner=$1
  [ -z "${CHECK_LOCK_HELD:-}" ] && [ -z "${CHECK_NO_LOCK:-}" ] && command -v flock >/dev/null || return 0
  lock_file=${SANDBOX_REAL_XDG_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}/dotfiles-check.lock
  lock_wait=${CHECK_LOCK_WAIT_SECS:-1200}
  exec 7>>"$lock_file"
  if ! flock -n 7; then
    holder=$(cat "$lock_file.owner" 2>/dev/null || echo 'owner unknown')
    echo "check: waiting up to ${lock_wait}s for the check already running ($holder)" >&2
    flock -w "$lock_wait" 7 || {
      echo "check: gave up after ${lock_wait}s; the lock is still held by the check running ($holder)" >&2
      return 1
    }
  fi
  printf 'pid %s in %s\n' "$$" "$owner" >"$lock_file.owner"
  export CHECK_LOCK_HELD=1
}

check_lock_gate() {
  owner=$1 script=$2
  shift 2
  [ -z "${CHECK_LOCK_HELD:-}" ] && [ -z "${CHECK_NO_LOCK:-}" ] && command -v flock >/dev/null || return 0
  check_lock_take "$owner" || exit 1
  "$script" "$@" 7>&-
  exit
}
