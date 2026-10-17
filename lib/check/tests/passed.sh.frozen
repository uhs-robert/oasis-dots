#!/bin/sh
set -u

# Remembers what passed `lib/check.sh`, across every worktree of the repository: whole trees, and single steps by the
# content of the files they read.
#
#   lib/check/passed.sh record           files HEAD's tree as passed (refuses a dirty tree)
#   lib/check/passed.sh record-changed <base>  files HEAD's tree as passing `check.sh --changed <base>` (refuses a dirty tree)
#   lib/check/passed.sh is-passed [rev]  exit 0 when the tree of rev passed; without rev it is HEAD's, and nothing
#                                        tracked may be modified
#   lib/check/passed.sh passed-somewhere [rev]  exit 0 when the tree of rev passed in any checkout, with or without
#                                        repos/; only the symlinks into repos/ are then unverified for this one
#   lib/check/passed.sh passed-since <base> [rev]  exit 0 when the tree of rev passed anywhere, or passed
#                                        `check.sh --changed <base>`: what a PR needs
#   lib/check/passed.sh step-record <step> <key>     files a step as passed for the input key check.sh computed
#   lib/check/passed.sh step-is-passed <step> <key>  exit 0 when it was
#
# The caller vouches for what it records: check.sh records a tree once every step passed for that tree's content, or a
# scoped pass on top of a recorded base; ship-batch records the same inductive case.
cd "$(git rev-parse --show-toplevel)" || exit 1

common_dir=$(git rev-parse --git-common-dir)
passed_file=$common_dir/claude-check-passed-trees
steps_file=$common_dir/claude-check-passed-steps
keep_entries=200
keep_step_entries=2000

# Only a checkout with repos/ clones verified the symlinks into them (lib/check/steps/symlinks.sh skips those links
# otherwise), so a pass from a worktree does not vouch for the main checkout.
if [ -n "$(find repos -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
  coverage=with-repos
else
  coverage=no-repos
fi

clean() { [ -z "$(git status --porcelain --untracked-files=no)" ]; }

# A concurrent writer's entry can be lost to the rename, which only means that pass is checked again.
add_tree_entry() {
  {
    grep -vxF "$1" "$passed_file" 2>/dev/null
    printf '%s\n' "$1"
  } | tail -n "$keep_entries" >"$passed_file.tmp$$" &&
    mv "$passed_file.tmp$$" "$passed_file"
}

tree_passed_anywhere() {
  grep -qxF "$1 with-repos" "$passed_file" 2>/dev/null || grep -qxF "$1 no-repos" "$passed_file" 2>/dev/null
}

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
  tree_passed_anywhere "$tree"
  ;;
passed-since)
  [ $# -ge 2 ] || exit 2
  tree=$(git rev-parse "${3:-HEAD}^{tree}") || exit 1
  base_tree=$(git rev-parse "$2^{tree}") || exit 1
  tree_passed_anywhere "$tree" || grep -qxF "$tree changed-since $base_tree" "$passed_file" 2>/dev/null
  ;;
record)
  clean || {
    echo 'check-passed: uncommitted tracked changes, so the pass is not HEAD'"'"'s tree' >&2
    exit 1
  }
  add_tree_entry "$(git rev-parse 'HEAD^{tree}') $coverage"
  ;;
record-changed)
  [ $# -ge 2 ] || exit 2
  clean || {
    echo 'check-passed: uncommitted tracked changes, so the pass is not HEAD'"'"'s tree' >&2
    exit 1
  }
  add_tree_entry "$(git rev-parse 'HEAD^{tree}') changed-since $(git rev-parse "$2^{tree}")"
  ;;
step-is-passed)
  [ $# -ge 3 ] || exit 2
  grep -qxF "$2 $3" "$steps_file" 2>/dev/null
  ;;
step-record)
  [ $# -ge 3 ] || exit 2
  # A short append is atomic, so concurrent recorders never tear a line; the trim's rename may drop one, which is safe.
  printf '%s %s\n' "$2" "$3" >>"$steps_file"
  if [ "$(wc -l <"$steps_file")" -gt "$keep_step_entries" ]; then
    tail -n $((keep_step_entries / 2)) "$steps_file" >"$steps_file.tmp$$" && mv "$steps_file.tmp$$" "$steps_file"
  fi
  ;;
*)
  echo 'usage: lib/check/passed.sh record | record-changed <base> | is-passed [rev] | passed-somewhere [rev] | passed-since <base> [rev] | step-record <step> <key> | step-is-passed <step> <key>' >&2
  exit 2
  ;;
esac
