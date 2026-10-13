#!/usr/bin/env bash
# Usage: ship-batch.sh [<pr>...]; merges the PRs in order, then updates main, checks it and restarts what changed.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
ipc="$HOME/.config/hypr/scripts/qs-ipc"
# shellcheck source=base.sh
source "$(dirname "$0")/base.sh"

die() {
  echo "ship-batch: $*" >&2
  exit 1
}

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"
# Commands below that can leave a daemon behind run with fd 9 closed so it cannot hold the lock after this run.
take_lock "$repo" || die "another ship-batch is running in this repository; wait for it to finish"
before=$(select_base "$repo")
# The owner already said to merge, so a Codex review still running is waited out rather than failing the batch.
(($# == 0)) || (cd "$repo" && "$HOME/.claude/skills/merge-prs/merge-prs.sh" --wait-review "$@") 9>&- || die "merge-prs failed; nothing after the merge ran"
git -C "$repo" pull -q --ff-only
after=$(git -C "$repo" rev-parse HEAD)
# A recorded base that main no longer descends from (rewritten history, pruned commit) vouches for nothing: check
# everything, and treat every file as changed so no reload or restart is skipped.
base_ok=true
if ! base_is_ancestor "$repo" "$before" "$after"; then
  base_ok=false
  echo "ship-batch: ${before:0:12} is not an ancestor of main; running the full check"
  before=$(git -C "$repo" hash-object -t tree /dev/null)
fi
# Inductive, like the Stop hook's last_ok: a full pass of `before` plus a scoped pass over everything changed since
# vouches for `after`. A `before` not recorded as passed (check-passed.sh also ignores a worktree's no-repos pass,
# which skipped this checkout's repos/ symlinks) or CHECK_FULL=1 falls back to the full check.
if [[ $before != "$after" ]]; then
  if $base_ok && [[ -z ${CHECK_FULL:-} ]] && (cd "$repo" && lib/check-passed.sh is-passed "$before"); then
    (cd "$repo" && lib/check.sh --changed "$before") 9>&- || die "the check fails on main after the merge; fix it before anything else"
  else
    (cd "$repo" && just check) 9>&- || die "just check fails on main after the merge; fix it before anything else"
  fi
  # With uncommitted changes in the main checkout the pass was of its working tree, not `after`'s, and the helper
  # refuses to record it; that must not stop the reloads and restarts below.
  (cd "$repo" && lib/check-passed.sh record) || true
fi

qs_dir=home/quickshell/.config/quickshell
greeter_paths="^($qs_dir/(lock/skins/|lock/Tints\.js$|theme/|fonts/|VERSION$)|system/etc/greetd/(quickshell/|hyprland\.lua$)|system/usr/local/bin/qs-greeter$|lib/greeter\.sh$|justfile$)"
changed=$(git -C "$repo" diff --name-only "$before" "$after")
if grep -Eq "$greeter_paths" <<<"$changed"; then
  if sudo -n true 2>/dev/null; then
    (cd "$repo" && just greeter-sync --install) 9>&- || die "greeter-sync failed"
    echo "ship-batch: synced the greeter"
  else
    echo "ship-batch: greeter files changed; run: just greeter-sync --install"
  fi
fi
other_greetd=$(grep -E '^system/etc/greetd/' <<<"$changed" | grep -Ev "$greeter_paths" | paste -sd' ' || true)
[[ -z $other_greetd ]] || echo "ship-batch: $other_greetd changed; deploy with: just system-apply"

if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/hypr; then
  hyprctl reload 9>&- >/dev/null
  errors=$(hyprctl configerrors 9>&-)
  [[ -z ${errors//[[:space:]]/} ]] || die "Hyprland config errors after reload: $errors"
fi

if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/quickshell; then
  if pgrep -af '^qs .*-p ' >/dev/null; then
    echo "ship-batch: a test bar is running; restore it with the owner-test-bar skill"
  else
    state=$(timeout 3 "$ipc" call lock state 9>&- 2>/dev/null || true)
    [[ $state == unlocked ]] || die "Quickshell changed but the lock state is '${state:-unknown}'; restart the bar once unlocked"
    hyprctl version 9>&- >/dev/null 2>&1 || die "hyprctl cannot reach Hyprland (stale HYPRLAND_INSTANCE_SIGNATURE?); restart the bar by hand"
    pkill -x qs || true
    for _ in $(seq 20); do
      pgrep -x qs >/dev/null || break
      sleep 0.2
    done
    hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" 9>&- >/dev/null
    sleep 6
    pgrep -x qs >/dev/null || die "qs did not come back; read 'qs log'"
    echo "ship-batch: restarted the stowed bar"
  fi
fi

# Only now: a failure or interruption anywhere above keeps the base, so a rerun repeats the check and the reloads.
finish_base "$repo"
echo "ship-batch: main is at $(git -C "$repo" log --oneline -1)"
(cd "$repo" && "$HOME/.claude/skills/merge-prs/status.sh") 9>&- || true
