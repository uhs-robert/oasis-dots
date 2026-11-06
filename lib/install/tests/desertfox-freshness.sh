#!/usr/bin/env bash
# Tests lib/install/desertfox-freshness against a scratch clone whose upstream is a local bare repo, so nothing touches the network.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
helper="$repo_dir/lib/install/desertfox-freshness"
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

failures=0
expect() { # case_name, output, wanted substring ("" means the output must be empty)
  if [[ -z $3 ]]; then
    [[ -z $2 ]] || {
      printf 'FAIL %s: wanted no output, got: %s\n' "$1" "$2" >&2
      failures=$((failures + 1))
    }
  else
    [[ $2 == *"$3"* ]] || {
      printf 'FAIL %s: wanted "%s", got: %s\n' "$1" "$3" "$2" >&2
      failures=$((failures + 1))
    }
  fi
}

# A fresh upstream and a clone of it with one commit and a current dist/commands.json.
new_case() {
  rm -rf "$scratch/up.git" "$scratch/work" "$scratch/other"
  git init -q --bare -b main "$scratch/up.git"
  git clone -q "$scratch/up.git" "$scratch/work" 2>/dev/null
  git -C "$scratch/work" commit -q --allow-empty -m one
  git -C "$scratch/work" push -q -u origin main 2>/dev/null
  mkdir "$scratch/work/dist"
  : >"$scratch/work/dist/commands.json"
}
run() { bash "$helper" "$scratch/work" 2>&1; }

new_case
expect "up to date" "$(run)" ""

new_case
git clone -q "$scratch/up.git" "$scratch/other" 2>/dev/null
git -C "$scratch/other" commit -q --allow-empty -m two
git -C "$scratch/other" push -q origin main 2>/dev/null
expect "behind upstream" "$(run)" "behind its upstream"

new_case
touch -d '2000-01-01' "$scratch/work/dist/commands.json"
expect "old dist" "$(run)" "older than the last commit"

new_case
rm "$scratch/work/dist/commands.json"
expect "missing dist" "$(run)" "dist/commands.json is missing"

new_case
mv "$scratch/up.git" "$scratch/gone.git"
expect "offline" "$(run)" "fetch failed, skipped the behind-upstream check"

# A git hook running the recipe exports GIT_DIR for its own repo; the warning must still describe the checkout.
new_case
git clone -q "$scratch/up.git" "$scratch/other" 2>/dev/null
git -C "$scratch/other" commit -q --allow-empty -m two
git -C "$scratch/other" push -q origin main 2>/dev/null
expect "inherited GIT_DIR" "$(GIT_DIR="$scratch/other/.git" run)" "behind its upstream"

exit $((failures > 0))
