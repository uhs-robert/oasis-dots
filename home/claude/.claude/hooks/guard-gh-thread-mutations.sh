#!/usr/bin/env bash
# PreToolUse(Bash): route PR review-thread replies and resolves through resolve-thread.sh instead of hand-written
# `gh api graphql` mutations. Creating a review or review comment stays allowed.
#
# Inverted on purpose: wrappers (`timeout 5 gh`, `bash -c`, `\gh`, `$GH`, ...) cannot be enumerated, so any command that
# names a thread mutation together with `graphql` is denied. The one exception is a segment (split on ; & | newline)
# that is led by a command known to carry prose (git commit/tag/notes, gh pr/issue comment|edit|create, echo, printf)
# after any VAR=val assignments, and names the mutation only inside a quoted argument or the quoted heredoc body of
# that command. Fail-closed, so a mention in grep, a multi-line message, or an unquoted heredoc is denied too.
# Known limits: a mutation name built at run time (`m=resolve; ...${m}ReviewThread`), a query fed from outside the
# command text (`-f query="$(cat f)"`, `cat q | gh api graphql --input -`), and a file written by an earlier call.
# An unreadable `--input F` / `query=@F` file is denied, since its content cannot be seen.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *graphql* ]] || exit 0

mutations='addPullRequestReviewThreadReply|resolveReviewThread|unresolveReviewThread'
assignments='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
prose_lead="^[[:space:]]*${assignments}(git[[:space:]]+(commit|tag|notes)|gh[[:space:]]+pr[[:space:]]+(comment|edit|create|review)|gh[[:space:]]+issue[[:space:]]+(comment|edit|create)|echo|printf)([[:space:]]|\$)"
quoted_heredoc=$'<<-?[[:space:]]*\'([A-Za-z_][A-Za-z0-9_]*)\''

# Drops the body of a quoted heredoc fed to a prose command: its text is never expanded or run.
scrubbed=''
heredoc_end=''
while IFS= read -r line; do
  if [[ -n $heredoc_end ]]; then
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ $trimmed == "$heredoc_end" ]] && heredoc_end=''
    continue
  fi
  scrubbed+=$line$'\n'
  if [[ $line =~ $prose_lead && $line =~ $quoted_heredoc ]]; then
    heredoc_end=${BASH_REMATCH[1]}
  fi
done <<<"$cmd"

# shellcheck disable=SC2020 # three separators, each to a newline
segments=$(tr ';&|' '\n\n\n' <<<"$scrubbed")

# True when the mutation name in this segment sits only inside quotes of a prose command.
is_prose_mention() {
  local rest
  [[ $1 =~ $prose_lead ]] || return 1
  rest=${1#"${BASH_REMATCH[0]}"}
  # Anything that expands or runs inside the message is no prose.
  # shellcheck disable=SC2016 # a literal $(
  [[ $rest != *'$('* && $rest != *'`'* ]] || return 1
  while [[ $rest =~ \'[^\']*\' ]]; do rest=${rest/"${BASH_REMATCH[0]}"/}; done
  while [[ $rest =~ \"[^\"]*\" ]]; do rest=${rest/"${BASH_REMATCH[0]}"/}; done
  [[ ! $rest =~ $mutations ]]
}

denied=false
while IFS= read -r segment; do
  if [[ $segment =~ $mutations ]] && ! is_prose_mention "$segment"; then
    denied=true
    break
  fi
done <<<"$segments"

# A query read from a file (`-F query=@F`, `-f query=@F`, `--input F`) is checked by its content; `--input -` is the
# command's own heredoc, already covered above. Only segments that mention graphql are scanned.
quote=$'\''
file_arg="(query=@|--input[[:space:]=]+)[$quote\"]?([^[:space:]$quote\"]+)"
while ! $denied && IFS= read -r segment; do
  [[ $segment == *graphql* ]] || continue
  while ! $denied && [[ $segment =~ $file_arg ]]; do
    path=${BASH_REMATCH[2]}
    segment=${segment#*"${BASH_REMATCH[0]}"}
    [[ $path == - ]] && continue
    path=${path/#\~\//$HOME/}
    if [[ -r $path && -f $path ]]; then
      ! grep -Eq "$mutations" "$path" || denied=true
    else
      denied=true
    fi
  done
done <<<"$segments"
$denied || exit 0

reason='Blocked: use ~/.claude/skills/merge-prs/resolve-thread.sh <PRRT_id> "<reply>" (list ids with --list <pr>); raw gh api graphql thread mutations are denied.'
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
