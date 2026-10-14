#!/usr/bin/env bash
# Runs git commands between the PreToolUse snapshot and the PostToolUse run of restart-qs-after-git.sh, against a
# throwaway repo standing in for the live checkout and stub qs process tools: the bar restarts only when the live
# checkout's own Quickshell files change.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../restart-qs-after-git.sh
pass=0 fail=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
g() { git -c user.name=t -c user.email=t@t "$@"; }

stubs=$root/stubs
mkdir -p "$stubs" "$root/home/.config" "$root/run"
# pgrep -af looks for a test bar (none); pgrep -x qs sees the bar gone between pkill and the relaunch.
cat >"$stubs/pgrep" <<STUB
#!/bin/sh
[ "\$1" = -af ] && exit 1
[ -e "$root/killed" ] && [ ! -e "$root/relaunched" ] && exit 1
exit 0
STUB
printf '#!/bin/sh\ntouch "%s/killed"\n' "$root" >"$stubs/pkill"
printf '#!/bin/sh\ntouch "%s/relaunched"\n' "$root" >"$stubs/hyprctl"
printf '#!/bin/sh\necho unlocked\n' >"$stubs/qs-ipc"
printf '#!/bin/sh\n' >"$stubs/sleep"
chmod +x "$stubs"/*

repo=$root/live
qs_file=home/quickshell/.config/quickshell/shell.qml
git init -q -b main "$repo"
mkdir -p "$repo/home/quickshell/.config/quickshell" "$repo/home/other"
echo v1 >"$repo/$qs_file"
echo a >"$repo/home/other/file"
g -C "$repo" add -A
g -C "$repo" commit -qm base
ln -s "$repo/home/quickshell/.config/quickshell" "$root/home/.config/quickshell"
g -C "$repo" switch -qc qs-change
echo v2 >"$repo/$qs_file"
g -C "$repo" commit -qam qs
g -C "$repo" switch -qc other-change main
echo b >"$repo/home/other/file"
g -C "$repo" commit -qam other
g -C "$repo" switch -q main
git -C "$repo" worktree add -q -b topic "$root/wt"

call=0
# expect <restart|none> <description> <dir> <command>: the command runs in dir between the two hook runs.
expect() {
  local json
  call=$((call + 1))
  rm -f "$root/killed" "$root/relaunched"
  json=$(jq -n --arg c "$4" --arg id "toolu_$call" '{tool_use_id: $id, tool_input: {command: $c}}')
  hook_env=(HOME="$root/home" XDG_RUNTIME_DIR="$root/run" QS_IPC="$stubs/qs-ipc" PATH="$stubs:$PATH")
  env "${hook_env[@]}" "$hook" snapshot <<<"$json"
  (cd "$3" && eval "$4") >/dev/null 2>&1
  env "${hook_env[@]}" "$hook" <<<"$json" >"$root/said"
  if [[ $1 == restart && -e $root/killed && -e $root/relaunched ]] || [[ $1 == none && ! -e $root/killed ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 ($(cat "$root/said"))"
    fail=$((fail + 1))
  fi
}

expect restart "a merge in the live checkout that changes Quickshell" "$repo" "git -c user.name=t -c user.email=t@t merge -q --no-edit qs-change"
# The live checkout just moved and changed Quickshell, which used to restart the bar again for any git command in the
# next two minutes, wherever it ran.
expect none "a commit of Quickshell files in a worktree" "$root/wt" "echo w >$qs_file && git -c user.name=t -c user.email=t@t commit -qam wt"
expect none "a rebase in a worktree onto a Quickshell change" "$root/wt" "git -c user.name=t -c user.email=t@t rebase -q main"
expect none "a merge in the live checkout that leaves Quickshell alone" "$repo" "git -c user.name=t -c user.email=t@t merge -q --no-edit other-change"
expect none "a commit in the live checkout, which leaves the files as they were" "$repo" "echo v3 >$qs_file && git -c user.name=t -c user.email=t@t commit -qam v3"
echo v4 >"$repo/$qs_file"
expect restart "a stash of an uncommitted Quickshell edit in the live checkout" "$repo" "git stash -q"
expect none "a git command that moves nothing" "$repo" "git status"
expect none "a Quickshell change with no snapshot from before the command" "$repo" "git stash pop -q && rm -rf '$root/run/claude-restart-qs'"

# Two sessions' commands overlap one pull of the live checkout: both snapshots predate it, both runs see it.
rm -f "$root/killed" "$root/relaunched"
hook_env=(HOME="$root/home" XDG_RUNTIME_DIR="$root/run" QS_IPC="$stubs/qs-ipc" PATH="$stubs:$PATH")
for id in pull rebase; do
  jq -n --arg c "git rebase main" --arg id "$id" '{tool_use_id: $id, tool_input: {command: $c}}' | env "${hook_env[@]}" "$hook" snapshot
done
git -C "$repo" stash -q
restarts=0
for id in pull rebase; do
  rm -f "$root/killed"
  jq -n --arg c "git rebase main" --arg id "$id" '{tool_use_id: $id, tool_input: {command: $c}}' | env "${hook_env[@]}" "$hook" >/dev/null
  [[ ! -e $root/killed ]] || restarts=$((restarts + 1))
done
if ((restarts == 1)); then
  echo "ok   commands overlapping one move restart the bar once"
  pass=$((pass + 1))
else
  echo "FAIL commands overlapping one move restarted the bar $restarts times"
  fail=$((fail + 1))
fi

check_stale=$(find "$root/run/claude-restart-qs" -type f 2>/dev/null | wc -l)
if ((check_stale == 0)); then
  echo "ok   every snapshot is removed once compared"
  pass=$((pass + 1))
else
  echo "FAIL $check_stale snapshots left behind"
  fail=$((fail + 1))
fi

echo "$pass passed, $fail failed"
((fail == 0))
