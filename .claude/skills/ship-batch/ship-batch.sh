#!/usr/bin/env bash
# Usage: ship-batch.sh [<pr>...]; merges the PRs in order, then updates main, checks it and restarts what changed.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
ipc="$HOME/.config/hypr/scripts/qs-ipc"

die() {
  echo "ship-batch: $*" >&2
  exit 1
}

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"
before=$(git -C "$repo" rev-parse HEAD)
(($# == 0)) || (cd "$repo" && "$HOME/.claude/skills/merge-prs/merge-prs.sh" "$@") || die "merge-prs failed; nothing after the merge ran"
git -C "$repo" pull -q --ff-only
after=$(git -C "$repo" rev-parse HEAD)
(cd "$repo" && just check) || die "just check fails on main after the merge; fix it before anything else"

qs_dir=home/quickshell/.config/quickshell
greeter_paths="^($qs_dir/(lock/skins/|lock/Tints\.js$|theme/|fonts/|VERSION$)|system/etc/greetd/(quickshell/|hyprland\.lua$)|system/usr/local/bin/qs-greeter$|lib/greeter\.sh$|justfile$)"
changed=$(git -C "$repo" diff --name-only "$before" "$after")
if grep -Eq "$greeter_paths" <<<"$changed"; then
  if sudo -n true 2>/dev/null; then
    (cd "$repo" && just greeter-sync --install) || die "greeter-sync failed"
    echo "ship-batch: synced the greeter"
  else
    echo "ship-batch: greeter files changed; run: just greeter-sync --install"
  fi
fi
other_greetd=$(grep -E '^system/etc/greetd/' <<<"$changed" | grep -Ev "$greeter_paths" | paste -sd' ' || true)
[[ -z $other_greetd ]] || echo "ship-batch: $other_greetd changed; deploy with: just system-apply"

if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/hypr; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors)
  [[ -z ${errors//[[:space:]]/} ]] || die "Hyprland config errors after reload: $errors"
fi

if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/quickshell; then
  if pgrep -af '^qs .*-p ' >/dev/null; then
    echo "ship-batch: a test bar is running; restore it with the test-bar skill"
  else
    state=$(timeout 3 "$ipc" call lock state 2>/dev/null || true)
    [[ $state == unlocked ]] || die "Quickshell changed but the lock state is '${state:-unknown}'; restart the bar once unlocked"
    hyprctl version >/dev/null 2>&1 || die "hyprctl cannot reach Hyprland (stale HYPRLAND_INSTANCE_SIGNATURE?); restart the bar by hand"
    pkill -x qs || true
    for _ in $(seq 20); do
      pgrep -x qs >/dev/null || break
      sleep 0.2
    done
    hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" >/dev/null
    sleep 6
    pgrep -x qs >/dev/null || die "qs did not come back; read 'qs log'"
    echo "ship-batch: restarted the stowed bar"
  fi
fi

echo "ship-batch: main is at $(git -C "$repo" log --oneline -1)"
(cd "$repo" && "$HOME/.claude/skills/merge-prs/status.sh") || true
