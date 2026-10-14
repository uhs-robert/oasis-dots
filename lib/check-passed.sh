#!/bin/sh
set -u

# Remembers which trees passed a FULL `lib/check.sh`, across every worktree of the repository.
#
#   lib/check-passed.sh record           files HEAD's tree as passed (refuses a dirty tree)
#   lib/check-passed.sh is-passed [rev]  exit 0 when the tree of rev passed; without rev it is HEAD's, and nothing
#                                        tracked may be modified
#   lib/check-passed.sh passed-somewhere [rev]  exit 0 when the tree of rev passed in any checkout, with or without
#                                        repos/; only the symlinks into repos/ are then unverified for this one
#
# The caller vouches for what it records: a full `check.sh`, or a scoped `check.sh --changed <base>` on top of a
# recorded base (ship-batch). A bare scoped pass is never recorded.
cd "$(git rev-parse --show-toplevel)" || exit 1

passed_file=$(git rev-parse --git-common-dir)/claude-check-passed-trees
keep_entries=200

# Only a checkout with repos/ clones verified the symlinks into them (lib/check-symlinks.sh skips those links
# otherwise), so a pass from a worktree does not vouch for the main checkout.
if [ -n "$(find repos -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
  coverage=with-repos
else
  coverage=no-repos
fi

clean() { [ -z "$(git status --porcelain --untracked-files=no)" ]; }

case ${1:-} in
is-passed)
  rev=${2:-HEAD}
  [ "$rev" != HEAD ] || clean || exit 1
  tree=$(git rev-parse "$rev^{tree}") || exit 1
  # A with-repos pass covers any checkout; a no-repos pass covers only another without repos.
  grep -qxF "$tree with-repos" "$passed_file" 2>/dev/null && exit 0
  [ "$coverage" = no-repos ] && grep -qxF "$tree no-repos" "$passed_file" 2>/dev/null
  ;;
passed-somewhere)
  tree=$(git rev-parse "${2:-HEAD}^{tree}") || exit 1
  grep -qxF "$tree with-repos" "$passed_file" 2>/dev/null || grep -qxF "$tree no-repos" "$passed_file" 2>/dev/null
  ;;
record)
  clean || {
    echo 'check-passed: uncommitted tracked changes, so the pass is not HEAD'"'"'s tree' >&2
    exit 1
  }
  entry="$(git rev-parse 'HEAD^{tree}') $coverage"
  {
    grep -vxF "$entry" "$passed_file" 2>/dev/null
    printf '%s\n' "$entry"
  } | tail -n "$keep_entries" >"$passed_file.tmp$$" &&
    mv "$passed_file.tmp$$" "$passed_file"
  ;;
*)
  echo 'usage: lib/check-passed.sh record | is-passed [rev] | passed-somewhere [rev]' >&2
  exit 2
  ;;
esac
