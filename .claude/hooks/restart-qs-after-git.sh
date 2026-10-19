#!/usr/bin/env bash
# PostToolUse(Bash): after a git command moves the live checkout, restart the stowed Quickshell if its files changed.
# PreToolUse(Bash) runs it with `snapshot`, recording the live checkout's Quickshell files before the command, so the
# PostToolUse run compares that checkout alone: a commit or rebase in a worktree shares the repository but never
# touches the files the stowed bar loads.
set -u
mode=${1:-compare}
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd == *git* || $cmd == *merge-prs* ]] || exit 0

# Commit messages, PR bodies and heredocs often say "merge" or "switch"; only command words count. Drop quoted
# heredoc bodies and every quoted span (tracking quote state per character), then look for a git subcommand.
words=$(awk '
  skip { line = $0; if (tabs) sub(/^\t+/, "", line); if (line == word) skip = 0; next }
  {
    out = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (sq) { if (c == "\047") sq = 0; continue }
      if (dq) {
        if (c == "\\") i++;
        else if (c == "\"") dq = 0;
        else if (c == "$" && substr($0, i + 1, 1) == "(") {
          # Command substitutions run even inside double quotes, so they stay; nested parens are counted.
          depth = 0
          for (; i <= n; i++) { ch = substr($0, i, 1); out = out ch; if (ch == "(") depth++; else if (ch == ")" && --depth == 0) break }
          out = out " "
        } else if (c == "`") {
          for (i++; i <= n && substr($0, i, 1) != "`"; i++) out = out substr($0, i, 1)
          out = out " "
        }
        continue
      }
      if (c == "\\") { i++; continue }
      if (c == "\047") { sq = 1; continue }
      if (c == "\"") { dq = 1; continue }
      out = out c
    }
    print out
  }
  match($0, /<<[-~]?[ ]*["\047]?[A-Za-z_][A-Za-z_0-9]*["\047]?/) {
    w = substr($0, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\047]?/, "", w); sub(/["\047]$/, "", w); word = w; skip = 1
  }' <<<"$cmd")
git_opts='([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]*)?|-[a-zA-Z]))*'
moves="(^|[;&|(\`[:space:]])git${git_opts}[[:space:]]+(switch|checkout|merge|pull|rebase|reset|restore|stash)([[:space:];&|)\`]|$)"
# merge-prs.sh fast-forwards the main checkout itself after merging, so running it (not naming it) counts.
merge_prs="(^|[;&|(\`])[[:space:]]*([^[:space:]]*/)?merge-prs\.sh([[:space:]]|$)"
[[ $words =~ $moves || $words =~ $merge_prs ]] || exit 0

live=$(readlink -f "$HOME/.config/quickshell" 2>/dev/null) || exit 0
repo=$(git -C "$live" rev-parse --show-toplevel 2>/dev/null) || exit 0

# The Quickshell files the bar loads, without hashing every one: the staged blobs, the unstaged changes on top of them,
# and the untracked names. Read from the index rather than HEAD, so a commit in the live checkout, which leaves the
# files as they were, does not count as a change.
live_quickshell_state() {
  git -C "$repo" ls-files -s -- home/quickshell | sha1sum
  git -C "$repo" diff --no-ext-diff --binary -- home/quickshell | sha1sum
  git -C "$repo" ls-files -o --exclude-standard -- home/quickshell
}

# Commands that overlap one move of the live checkout (a pull in one session while another rebases a worktree) all see
# it change, so the state the bar was restarted for is recorded and not restarted for again. A snapshot that finds the
# files elsewhere forgets it, so moving back to that state later (stashing a hand edit) still restarts.
handled_file=$(git -C "$repo" rev-parse --path-format=absolute --git-path claude-qs-restarted-state 2>/dev/null) || exit 0

# Keyed by the tool call, so concurrent sessions and calls never read each other's snapshot.
snapshots=${XDG_RUNTIME_DIR:-/tmp}/claude-restart-qs
key=$(jq -r '.tool_use_id // ((.session_id // "") + .tool_input.command)' <<<"$input" | sha1sum | cut -c1-40)
if [[ $mode == snapshot ]]; then
  mkdir -p "$snapshots" || exit 0
  # Calls that never reach PostToolUse (denied, interrupted) leave their snapshot behind.
  find "$snapshots" -type f -mmin +1440 -delete 2>/dev/null
  live_quickshell_state >"$snapshots/$key" 2>/dev/null
  [[ $(cat "$handled_file" 2>/dev/null) == "$(<"$snapshots/$key")" ]] || rm -f "$handled_file"
  exit 0
fi
# No snapshot means the command was not seen starting; restarting the owner's bar on a guess is worse than missing one.
[[ -f $snapshots/$key ]] || exit 0
before=$(<"$snapshots/$key")
rm -f "$snapshots/$key"
after=$(live_quickshell_state 2>/dev/null)
[[ $before != "$after" ]] || exit 0
[[ $(cat "$handled_file" 2>/dev/null) != "$after" ]] || exit 0

say() { jq -n --arg c "$1" '{systemMessage: $c, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'; }

if pgrep -af '^qs .*-p ' >/dev/null; then
  say "Quickshell files changed in the live checkout ($repo), but a worktree test bar is running (qs -p ...), so the stowed bar was not restarted. Restore it with the owner-test-bar skill when testing is done."
  exit 0
fi
state=$(timeout 3 "${QS_IPC:-$HOME/.config/hypr/scripts/qs-ipc}" call lock state 2>/dev/null)
if [[ $state != unlocked ]] && pgrep -x qs >/dev/null; then
  say "Quickshell files changed in the live checkout, but the lock state is '${state:-unknown}', so the bar was not restarted (killing it could drop the lock). Restart it once the owner is unlocked: pkill -x qs; hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"."
  exit 0
fi

# This session's HYPRLAND_INSTANCE_SIGNATURE can be stale (the owner logged in again since it started), and then the
# relaunch below fails silently after pkill has already taken the bar down. The newest instance that answers is the
# live one, by its socket: a directory's mtime moves whenever a child like .hyprpaper.sock is recreated. With none, nothing is killed.
live_signature=
while read -r socket; do
  instance=$(basename "$(dirname "$socket")")
  if HYPRLAND_INSTANCE_SIGNATURE=$instance timeout 3 hyprctl monitors >/dev/null 2>&1; then
    live_signature=$instance
    break
  fi
done < <(ls -1t "${XDG_RUNTIME_DIR:-/run/user/$UID}"/hypr/*/.socket.sock 2>/dev/null)
if [[ -z $live_signature ]]; then
  say "Quickshell files changed in the live checkout, but no running Hyprland instance answers 'hyprctl monitors', so the bar was not killed. Restart it by hand from a shell inside the owner's session: pkill -x qs; hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"."
  exit 0
fi
export HYPRLAND_INSTANCE_SIGNATURE=$live_signature

# Recorded only now, so a restart withheld above is not marked as done.
printf '%s\n' "$after" >"$handled_file"
pkill -x qs
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x qs >/dev/null || break
  sleep 0.2
done
hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" >/dev/null 2>&1
for _ in $(seq 25); do
  pgrep -x qs >/dev/null && break
  sleep 0.2
done
if pgrep -x qs >/dev/null; then
  say "Quickshell files changed in the live checkout ($repo), so the stowed bar was restarted: hot-reload can keep stale code after a git checkout or merge. Check 'qs log' for load errors before telling the owner it is live."
else
  say "Quickshell files changed and the bar was killed, but qs did not come back within 5 s (Hyprland instance $live_signature): it probably failed to load, or the relaunch was not delivered. Read 'qs log', then relaunch with HYPRLAND_INSTANCE_SIGNATURE=$live_signature hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"."
fi
