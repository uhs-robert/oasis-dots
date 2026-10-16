# shellcheck shell=sh
# The machine-wide limit on heavy check steps, shared by lib/check.sh and the voxcmd suites (home/voxcmd/tests/run*.sh),
# and the low priority every check runs at. Sourced, not run.
#
# Only the long, timing-sensitive voxcmd suites are limited: at most CHECK_HEAVY_SLOTS (default 1) run at once on this
# machine, each holding one slot, a flock'd file. The cheap steps take no slot; the low CPU and IO priority keeps them off
# the desktop's back instead.
#
# check_lower_priority: puts the calling shell, and so everything it starts, at nice 19 and in the idle IO class.
#
# check_lock_take <owner>: holds a free slot on fd 7 for the rest of the calling shell. It waits at most
# CHECK_LOCK_WAIT_SECS (default 1200) for one to free, then returns 1 naming the holders. It returns 0 at once when
# CHECK_LOCK_HELD is set (an ancestor holds a slot), CHECK_NO_LOCK is set, or flock is missing. The slot files stay in the
# real runtime dir inside the voxcmd sandbox, whose XDG_RUNTIME_DIR is its own. A suite run directly takes a slot too, and
# one under a check or another suite skips it; a sandboxed one-off such as `sandbox.sh voxcmd --dry-run` takes none.
#
# check_lock_gate <owner> <script> [args...]: for a suite's entry. It lowers the priority, and when no slot is held here,
# takes one, runs <script> again as a child with fd 7 closed, and exits with the child's status. The child finds
# CHECK_LOCK_HELD set and returns at once. Closing fd 7 for the body means a daemon the suite leaves behind cannot keep
# the slot: the holder is the parent, which exits only after the child has. A holder that dies frees its slot with it.
check_lower_priority() {
  if command -v renice >/dev/null; then renice -n 19 -p "$$" >/dev/null 2>&1; fi
  if command -v ionice >/dev/null; then ionice -c 3 -p "$$" >/dev/null 2>&1; fi
  return 0
}

# Slot 1 keeps the name of the single lock this replaced, so a check still running the old code counts as one holder.
check_slot_file() {
  slot_dir=${SANDBOX_REAL_XDG_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}
  if [ "$1" = 1 ]; then echo "$slot_dir/dotfiles-check.lock"; else echo "$slot_dir/dotfiles-check.lock.$1"; fi
}

check_slot_holders() {
  slot=1
  while [ "$slot" -le "$slot_count" ]; do
    cat "$(check_slot_file "$slot").owner" 2>/dev/null || echo 'owner unknown'
    slot=$((slot + 1))
  done | paste -sd ';' -
}

check_lock_take() {
  owner=$1
  [ -z "${CHECK_LOCK_HELD:-}" ] && [ -z "${CHECK_NO_LOCK:-}" ] && command -v flock >/dev/null || return 0
  slot_count=${CHECK_HEAVY_SLOTS:-1}
  lock_wait=${CHECK_LOCK_WAIT_SECS:-1200}
  give_up_at=$(($(date +%s) + lock_wait))
  announced=''
  # flock cannot wait on "any of N", so this polls each slot without blocking.
  while :; do
    slot=1
    while [ "$slot" -le "$slot_count" ]; do
      slot_file=$(check_slot_file "$slot")
      exec 7>>"$slot_file"
      if flock -n 7; then
        printf 'pid %s in %s\n' "$$" "$owner" >"$slot_file.owner"
        export CHECK_LOCK_HELD=1
        return 0
      fi
      exec 7>&-
      slot=$((slot + 1))
    done
    if [ "$(date +%s)" -ge "$give_up_at" ]; then
      echo "check: gave up after ${lock_wait}s; all $slot_count heavy-step slots are still held ($(check_slot_holders))" >&2
      return 1
    fi
    if [ -z "$announced" ]; then
      echo "check: waiting up to ${lock_wait}s for one of the $slot_count heavy-step slots ($(check_slot_holders))" >&2
      announced=1
    fi
    sleep 1
  done
}

check_lock_gate() {
  owner=$1 script=$2
  shift 2
  check_lower_priority
  [ -z "${CHECK_LOCK_HELD:-}" ] && [ -z "${CHECK_NO_LOCK:-}" ] && command -v flock >/dev/null || return 0
  check_lock_take "$owner" || exit 1
  "$script" "$@" 7>&-
  exit
}
