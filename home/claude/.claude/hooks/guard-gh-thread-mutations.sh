#!/usr/bin/env bash
# PreToolUse(Bash): route PR review-thread replies and resolves through resolve-thread.sh instead of hand-written
# `gh api graphql` mutations. Creating a review or review comment stays allowed.
#
# Inverted on purpose: wrappers (`timeout 5 gh`, `bash -c`, `\gh`, `$GH`, ...) cannot be enumerated, so any command that
# names a thread mutation together with `graphql` is denied. The one exception is trivially safe prose: a segment
# (split on ; & | newline) that starts with git commit/tag/notes or gh pr|issue comment|edit|create (gh pr review too)
# and names the mutation only inside a quoted argument, in a command with no heredoc, no pipe, no `<` input redirect,
# no `>(`, and no `$(` or backtick anywhere. No VAR=val prefix is allowed: GIT_EDITOR=... would run the mutation.
# echo and printf are not prose commands: their text can be piped into a shell. Long messages go in by file
# (-F file, --body-file). Fail-closed, so a mention in grep or echo is denied too.
# Known limits: a mutation name built at run time (`m=resolve; ...${m}ReviewThread`) or split by quotes or ANSI-C
# (`resolve''ReviewThread`, `$'\x72esolve...'`); case variants (GraphQL names are case-sensitive, so likely harmless);
# a query fed from outside the command text through `-f query="$(cat f)"`; a file written by an earlier call. An unreadable `--input F` / `query=@F` file is denied, since its content cannot be seen; so is any relative one (give query files by absolute
# path), and `--input -` / `query=@-` fed by a pipe or `<` (a bare heredoc is covered by the text checks above).
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *graphql* ]] || exit 0

mutations='addPullRequestReviewThreadReply|resolveReviewThread|unresolveReviewThread'
prose_lead="^[[:space:]]*(git[[:space:]]+(commit|tag|notes)|gh[[:space:]]+pr[[:space:]]+(comment|edit|create|review)|gh[[:space:]]+issue[[:space:]]+(comment|edit|create))([[:space:]]|\$)"

# shellcheck disable=SC2020 # three separators, each to a newline
segments=$(tr ';&|' '\n\n\n' <<<"$cmd")

# The command as the shell sees it outside quotes: a pipe, input redirect or process substitution there can carry a
# quoted message into a shell or gh, so such a command gets no prose exception.
unquoted=$cmd
while [[ $unquoted =~ \'[^\']*\' ]]; do unquoted=${unquoted/"${BASH_REMATCH[0]}"/}; done
while [[ $unquoted =~ \"[^\"]*\" ]]; do unquoted=${unquoted/"${BASH_REMATCH[0]}"/}; done
prose_possible=true
# shellcheck disable=SC2016 # a literal $(
[[ $unquoted == *'|'* || $unquoted == *'<'* || $unquoted == *'>('* || $cmd == *'$('* || $cmd == *'`'* ]] && prose_possible=false

# True when the mutation name in this segment sits only inside quotes of a prose command.
is_prose_mention() {
  local rest
  $prose_possible || return 1
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

# A query read from a file (`-F query=@F`, `-f query=@F`, `--input F`) is checked by its content. Only segments that
# mention graphql are scanned. F must be absolute or start with ~/: a relative path cannot be located (`cd`, `env -C`,
# ... change where gh reads it), so it is denied. `-` reads stdin, which is the command's own heredoc unless a pipe or
# `<` feeds it.
quote=$'\''
file_arg="(query=@|--input[[:space:]=]+)[$quote\"]?([^[:space:]$quote\"]+)"
stdin_fed=false
[[ $unquoted == *'|'* || ${unquoted//<</} == *'<'* ]] && stdin_fed=true
while ! $denied && IFS= read -r segment; do
  [[ $segment == *graphql* ]] || continue
  while ! $denied && [[ $segment =~ $file_arg ]]; do
    path=${BASH_REMATCH[2]}
    segment=${segment#*"${BASH_REMATCH[0]}"}
    if [[ $path == - ]]; then
      ! $stdin_fed || denied=true
      continue
    fi
    path=${path/#\~\//$HOME/}
    if [[ $path == /* && -r $path && -f $path ]]; then
      ! grep -Eq "$mutations" "$path" || denied=true
    else
      denied=true
    fi
  done
done <<<"$segments"
$denied || exit 0

reason='Blocked: use ~/.claude/skills/merge-prs/resolve-thread.sh <PRRT_id> "<reply>" (list ids with --list <pr>); raw gh api graphql thread mutations are denied.'
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
