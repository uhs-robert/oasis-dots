#!/usr/bin/env bash
# Runs reconcile.sh against fixture docs with `gh` and `git worktree list` stubbed through PATH.
# check takes its condition as a single-quoted string for eval, which reads status and out.
# shellcheck disable=SC2016,SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../reconcile.sh}
pass=0 fail=0

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir "$root/bin"

# Every PR is OPEN except those the fixtures name: 11 is MERGED, 12 is CLOSED. Each call is logged to count them.
cat >"$root/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case $3 in
  14) echo "gh: HTTP 401 bad credentials" >&2; echo "second line" >&2; exit 1 ;;
  11) echo MERGED ;;
  12) echo CLOSED ;;
  *) echo OPEN ;;
esac
STUB
cat >"$root/bin/git" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2 $3" = "worktree list --porcelain" ] || exit 99
cat "$WORKTREES"
STUB
chmod +x "$root/bin/gh" "$root/bin/git"
export GH_LOG=$root/gh.log WORKTREES=$root/worktrees

cat >"$WORKTREES" <<'EOF2'
worktree /srv/repo
HEAD aaaa
branch refs/heads/main

worktree /srv/repo-alpha
HEAD bbbb
branch refs/heads/feat/alpha

worktree /srv/repo-stray
HEAD cccc
branch refs/heads/feat/stray

worktree /elsewhere/odd-place
HEAD dddd
branch refs/heads/feat/odd
EOF2

fixture() { cat >"$root/$1.md"; }

fixture clean <<'EOF2'
# Track

## Resume here (2026-10-20)

- Open PRs: #10, #13 (#11 merged; #12 closed)
- Worktree /srv/repo-alpha, branch feat/alpha; /srv/repo-stray (feat/stray); /elsewhere/odd-place.
- Doc lives at /srv/repo/track.md.

## Done

- #11 and PR #99 open (outside the section, ignored).
EOF2

fixture merged <<'EOF2'
## Resume here
Open PRs: #10, #11
- /srv/repo-alpha /srv/repo-stray /elsewhere/odd-place
### Sub
## Later
EOF2

fixture finished <<'EOF2'
## Resume here
- PR #11 DONE. PR #12 closed. Open PRs: none (#11 MERGED).
- /srv/repo-alpha /srv/repo-stray /elsewhere/odd-place
EOF2

fixture missing <<'EOF2'
## Resume here
- PR #13 open.
- /srv/repo-alpha /srv/repo-stray /elsewhere/odd-place /srv/repo-gone
EOF2

fixture unlisted <<'EOF2'
## Resume here
- /srv/repo-alpha /elsewhere/odd-place
EOF2

fixture failing <<'EOF2'
## Resume here
- Open PRs: #14
- /srv/repo-alpha /srv/repo-stray /elsewhere/odd-place
EOF2

fixture none <<'EOF2'
# No section
EOF2

run() {
  : >"$GH_LOG"
  out=$(PATH=$root/bin:$PATH bash "$script" "${@/#/$root/}" 2>&1)
  status=$?
}
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  printf '   | %s\n' "$out"
  fail=$((fail + 1))
fi; }

run clean.md
check "clean doc: no output, exit 0" '[ "$status" = 0 ] && [ -z "$out" ]'
check "clean doc: one gh call per open PR" '[ "$(wc -l <"$GH_LOG")" = 2 ] && grep -qx "pr view 10 --json state --jq .state" "$GH_LOG"'

run merged.md
check "merged PR listed open is flagged" '[ "$status" = 1 ] && [ "$out" = "PR #11 listed open but MERGED" ]'

run finished.md
check "DONE, closed and merged PRs are not checked" '[ "$status" = 0 ] && [ -z "$out" ] && [ ! -s "$GH_LOG" ]'

run missing.md
check "listed worktree that does not exist is flagged" '[ "$status" = 1 ] && [ "$out" = "worktree /srv/repo-gone listed but missing" ]'

run unlisted.md
check "live worktree no doc lists is flagged with its branch" '[ "$status" = 1 ] && [ "$out" = "worktree /srv/repo-stray (feat/stray) exists but no doc lists it" ]'

run unlisted.md merged.md
check "a worktree listed by any doc counts as listed" '[ "$out" = "PR #11 listed open but MERGED" ]'

run failing.md
check "a gh failure is a mismatch carrying gh's first stderr line" '[ "$status" = 1 ] && [ "$out" = "PR #14: could not query state (gh: HTTP 401 bad credentials)" ]'

run none.md
check "doc without a section is flagged" '[ "$status" = 1 ] && grep -q "has no Resume here section" <<<"$out"'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
