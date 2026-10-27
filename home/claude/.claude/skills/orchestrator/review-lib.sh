#!/usr/bin/env bash
# Shared by the *-review.sh scripts and run-local-reviews.sh; source it, do not run it.
#
# Reviewer contract: `<cmd> <base> <outdir>` writes `<outdir>/<name>-review.md` and exits
#   0 review written (path printed), 2 unavailable (one-line reason printed),
#   3 uncommitted changes, 4 skipped by scope (one-line reason printed, also kept in
#   `<outdir>/<name>-skipped.txt`).

review_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
visibility_ttl_s=${REVIEW_VISIBILITY_TTL_S:-86400}

# Repo visibility (lowercase) on stdout. A failed lookup returns 1 so `public` scope fails closed.
review_repo_visibility() {
  local cache_dir key file now mtime vis
  cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/code-reviewers
  key=$(git remote get-url origin 2>/dev/null | cksum | cut -d' ' -f1)
  file=$cache_dir/visibility-${key:-none}
  now=$(date +%s)
  if [ -n "$key" ] && [ -s "$file" ]; then
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt "$visibility_ttl_s" ]; then
      cat "$file"
      return 0
    fi
  fi
  vis=$(gh repo view --json visibility --jq .visibility 2>/dev/null | tr '[:upper:]' '[:lower:]')
  case $vis in
  public | private | internal) ;;
  *) return 1 ;;
  esac
  if [ -n "$key" ] && mkdir -p "$cache_dir" 2>/dev/null; then
    printf '%s\n' "$vis" >"$file" 2>/dev/null
  fi
  printf '%s\n' "$vis"
}

# The reviewer's scope: $REVIEW_SCOPE (set by the runner), else the resolved registry, else $2.
review_scope() {
  local name=$1 fallback=$2 scope=""
  if [ -n "${REVIEW_SCOPE:-}" ]; then
    printf '%s\n' "$REVIEW_SCOPE"
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    scope=$("$review_lib_dir/reviewers.sh" list 2>/dev/null |
      jq -r --arg n "$name" '.[] | select(.name == $n) | .local.scope // empty' 2>/dev/null)
  fi
  printf '%s\n' "${scope:-$fallback}"
}

# review_scope_gate NAME OUTDIR FALLBACK_SCOPE: returns 0 to proceed, 4 after printing the skip reason.
# Anything but off/public/all is treated as off, and an unknown visibility as private.
review_scope_gate() {
  local name=$1 outdir=$2 scope vis reason=""
  scope=$(review_scope "$name" "$3")
  case $scope in
  all) return 0 ;;
  public)
    vis=$(review_repo_visibility) || vis=""
    [ "$vis" = public ] && return 0
    reason="scope public and the repo is ${vis:-of unknown visibility (lookup failed)}"
    ;;
  *) reason="scope is ${scope:-off}" ;;
  esac
  mkdir -p "$outdir" 2>/dev/null && printf '%s\n' "$reason" >"$outdir/$name-skipped.txt"
  echo "$name skipped: $reason"
  return 4
}

# Review commands that read only commits miss a dirty tree.
review_tree_is_clean() {
  [ -z "$(git status --porcelain)" ]
}
