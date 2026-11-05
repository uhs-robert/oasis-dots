#!/usr/bin/env bash
# PreToolUse(Bash): keep subagents off `git stash`. Every worktree of a repo shares one stash stack, so a subagent that
# pops or drops a stash can destroy another worktree's work. Only subagents are checked (the payload has .agent_id,
# as in context-budget.sh); the main session passes. Read-only `list` and `show` pass; every other stash form is
# denied, which also covers `git stash -u` and a bare `git stash`, both of which push.
set -u
input=$(cat)
[[ -n $(jq -r '.agent_id // empty' <<<"$input") ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd == *stash* ]] || exit 0

while IFS= read -r segment; do
  read -ra words <<<"$segment"
  ((${#words[@]})) || continue
  words[0]=${words[0]#[({]}
  i=0
  while ((i < ${#words[@]})) && [[ ${words[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ((i++)); done
  [[ ${words[i]:-} == git ]] || continue
  ((i++))
  # Global options before the subcommand; these four take a separate value.
  while ((i < ${#words[@]})) && [[ ${words[i]} == -* ]]; do
    case ${words[i]} in
    -C | -c | --git-dir | --work-tree | --namespace) ((i += 2)) ;;
    *) ((i++)) ;;
    esac
  done
  [[ ${words[i]:-} == stash ]] || continue
  case ${words[i + 1]:-} in
  list | show) continue ;;
  esac
  reason='Blocked: all worktrees of a repo share one stash stack, so a stash from here can clobber another worktree'"'"'s work. Instead: test old code with `git show <commit>:<path> > <path>`, commit before a merge, and do throwaway work in a temporary worktree (`git worktree add`).'
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
done < <(sed -E 's/&&|;|\|/\n/g' <<<"$cmd")
