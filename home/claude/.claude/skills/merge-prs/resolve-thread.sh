#!/usr/bin/env bash
# Reply to one PR review thread and resolve it; the only thread mutation an agent is allowed to run (the raw
# `gh api graphql` mutations are denied by hooks/guard-gh-thread-mutations.sh).
# shellcheck disable=SC2016 # the $variables in the queries are GraphQL's, not the shell's
set -euo pipefail

usage="usage: resolve-thread.sh <PRRT_id> <reply-body | ->    ('-' reads the reply from stdin)
       resolve-thread.sh --list <pr>                          (unresolved threads, read-only)"

die() {
  echo "resolve-thread: $*" >&2
  exit 1
}

# The body travels as -f (a literal string), never -F, which would read a body starting with @ as a file.
reply_mutation='mutation($thread: ID!, $body: String!) { addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $thread, body: $body}) { comment { id } } }'
resolve_mutation='mutation($thread: ID!) { resolveReviewThread(input: {threadId: $thread}) { thread { id } } }'
state_query='query($thread: ID!) { node(id: $thread) { ... on PullRequestReviewThread { isResolved } } }'
list_query='query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { id isResolved path line comments(first: 1) { nodes { author { login } body } } } } } } }'
# First line of the opening comment, tabs flattened and cut to 80 characters.
list_jq='.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | .comments.nodes[0] as $c
  | [.id, .path, (.line // "-" | tostring), ($c.author.login // "-"), ($c.body | split("\n")[0] | gsub("\t"; " ") | .[0:80])] | @tsv'

list_threads() {
  local pr=$1 slug page cursor_args=() cursor='' previous_cursor
  [[ $pr =~ ^[0-9]+$ ]] || die "$usage"
  slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die "cannot read the repository"
  while :; do
    page=$(gh api graphql -F owner="${slug%%/*}" -F name="${slug#*/}" -F number="$pr" -f query="$list_query" "${cursor_args[@]}") ||
      die "cannot read the review threads of #$pr"
    jq -r "$list_jq" <<<"$page" || die "cannot parse the review threads of #$pr"
    [[ $(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page") == true ]] || break
    previous_cursor=$cursor
    cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // empty' <<<"$page")
    [[ -n $cursor ]] || die "the review thread list of #$pr has another page but no cursor"
    [[ $cursor != "$previous_cursor" ]] || die "the review thread list of #$pr repeats cursor $cursor"
    cursor_args=(-f after="$cursor")
  done
}

case ${1:-} in
-h | --help)
  echo "$usage"
  exit 0
  ;;
--list)
  (($# == 2)) || die "$usage"
  list_threads "$2"
  exit 0
  ;;
esac

(($# == 2)) || die "$usage"
id=$1
body=$2
[[ $id =~ ^PRRT_[A-Za-z0-9_-]+$ ]] || die "not a review thread id (PRRT_...): $id"
[[ $body != - ]] || body=$(cat)
[[ $body =~ [^[:space:]] ]] || die "the reply is empty"

resolved=$(gh api graphql -f query="$state_query" -f thread="$id" --jq '.data.node.isResolved') ||
  die "cannot read thread $id"
[[ $resolved == true || $resolved == false ]] || die "no such review thread: $id"

# Reply first: a thread is only resolved once the reply is on it.
gh api graphql -f query="$reply_mutation" -f thread="$id" -f body="$body" >/dev/null || die "cannot reply to $id"
if [[ $resolved == true ]]; then
  echo "replied $id (already resolved)"
  exit 0
fi
gh api graphql -f query="$resolve_mutation" -f thread="$id" >/dev/null || die "replied to $id but cannot resolve it"
echo "replied+resolved $id"
