#!/usr/bin/env bash
# After PRs are merged: update main, check it, restart the stowed bar if Quickshell changed, and clean up worktrees and branches.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
ipc="$HOME/.config/hypr/scripts/qs-ipc"

die() {
  echo "ship-batch: $*" >&2
  exit 1
}

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"
before=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" pull -q --ff-only
after=$(git -C "$repo" rev-parse HEAD)
(cd "$repo" && just check) || die "just check fails on main after the merge; fix it before anything else"

qs_dir=home/quickshell/.config/quickshell
greeter_paths="^($qs_dir/(lock/skins/|lock/Tints\.js$|theme/|fonts/|VERSION$)|system/etc/greetd/|system/usr/local/bin/qs-greeter$)"
if git -C "$repo" diff --name-only "$before" "$after" | grep -Eq "$greeter_paths"; then
  if sudo -n true 2>/dev/null; then
    (cd "$repo" && just greeter-sync --install) || die "greeter-sync failed"
    echo "ship-batch: synced the greeter"
  else
    echo "ship-batch: greeter files changed; run: just greeter-sync --install"
  fi
fi

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

git -C "$repo" worktree prune
while read -r path branch; do
  [[ $path == "$repo" ]] && continue
  if [[ -n $branch ]] && git -C "$repo" merge-base --is-ancestor "$branch" main; then
    git -C "$repo" worktree remove --force "$path" && echo "ship-batch: removed merged worktree $path"
  fi
done < <(git -C "$repo" worktree list --porcelain | awk '/^worktree /{p=$2} /^branch /{sub("refs/heads/","",$2); print p, $2} /^detached/{print p, ""}')
git -C "$repo" worktree prune
git -C "$repo" branch --merged main --format='%(refname:short)' | grep -v -e '^main$' -e '^assets$' | xargs -r git -C "$repo" branch -d
echo "ship-batch: main is at $(git -C "$repo" log --oneline -1)"
