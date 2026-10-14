#!/usr/bin/env bash
# PostToolUse(Bash): after a git command moves the live checkout, restart the stowed Quickshell if its files changed.
set -u
cmd=$(jq -r '.tool_input.command // empty')
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
# When HEAD moved here (the reflog entry), not the commit's own date: a PR merged on GitHub
# an hour ago and pulled now must still count.
moved_at=$(git -C "$repo" log -g -1 --date=unix --format=%gd HEAD 2>/dev/null) || exit 0
moved_at=${moved_at//[^0-9]/}
[[ -n $moved_at ]] && ((moved_at >= $(date +%s) - 120)) || exit 0
git -C "$repo" diff --quiet 'HEAD@{1}' HEAD -- home/quickshell 2>/dev/null && exit 0
# Any git command in any session lands here within those 120 s, worktree commands included, so the same move of the
# live checkout would restart the bar once per command. Each HEAD is handled once, by whichever command sees it first.
handled_file=$(git -C "$repo" rev-parse --git-path claude-qs-restarted-head 2>/dev/null) || exit 0
head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || exit 0
[[ $(cat "$handled_file" 2>/dev/null) == "$head" ]] && exit 0

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

printf '%s\n' "$head" >"$handled_file"
pkill -x qs
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x qs >/dev/null || break
  sleep 0.2
done
hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" >/dev/null 2>&1
sleep 3
if pgrep -x qs >/dev/null; then
  say "Quickshell files changed in the live checkout ($repo), so the stowed bar was restarted: hot-reload can keep stale code after a git checkout or merge. Check 'qs log' for load errors before telling the owner it is live."
else
  say "Quickshell files changed and the bar was restarted, but qs is not running now: it probably failed to load. Read 'qs log' for the error and relaunch with hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"."
fi
