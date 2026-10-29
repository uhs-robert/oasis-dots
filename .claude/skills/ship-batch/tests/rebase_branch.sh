#!/usr/bin/env bash
# rebase-branch.sh against a temp origin, with a fake gh that knows which branches have an open PR.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=$here/../rebase-branch.sh
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir "$root/bin"
# OPEN_PRS: space-separated branches with an open PR, each #5.
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ $1 == pr && $2 == list ]] || exit 1
[[ " $OPEN_PRS " == *" $4 "* ]] && echo 5
exit 0
EOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH" OPEN_PRS="feat"

# A fresh origin with main and feat (one commit each side of the fork point), cloned to $root/c.
setup() {
  rm -rf "$root/origin" "$root/c" "$root/w"
  git init -q --bare -b main "$root/origin"
  git clone -q "$root/origin" "$root/c" 2>/dev/null
  cd "$root/c" || exit 1
  echo base >base && git add base && git commit -qm base && git push -q origin main
  git switch -qc feat && echo f >f && git add f && git commit -qm "feat: f" && git push -qu origin feat
  git switch -q main && echo m >m && git add m && git commit -qm "feat: m" && git push -q origin main
  git remote set-head origin main
}
# out and code are read by the check strings, which shellcheck cannot follow into eval.
# shellcheck disable=SC2034
run() {
  out=$("$script" "$@" 2>&1)
  code=$?
}
contains_main() { git -C "$root/origin" merge-base --is-ancestor main feat; }

echo "== a branch behind main is rebased and pushed"
setup
run feat
check "exits 0" "[[ $code == 0 ]]"
check "origin's feat contains main" contains_main
check "history stays linear" "[[ \$(git -C '$root/origin' rev-list --merges main..feat | wc -l) == 0 ]]"
check "leaves no worktree behind" "[[ \$(git worktree list | wc -l) == 1 ]]"

echo "== the default branch is refused"
setup
run main
check "fails" "[[ $code != 0 ]] && grep -q 'refusing to rewrite main' <<<\"\$out\""

echo "== a branch with no open PR is refused"
setup
OPEN_PRS="" run feat
check "fails" "[[ $code != 0 ]] && grep -q 'no open PR' <<<\"\$out\""
check "pushes nothing" "! contains_main"

echo "== a remote with commits the local branch lacks is refused"
setup
git clone -q "$root/origin" "$root/w" 2>/dev/null
(cd "$root/w" && git switch -q feat && echo x >x && git add x && git commit -qm "fix: x" && git push -q origin feat)
before=$(git -C "$root/origin" rev-parse feat)
run feat
check "fails" "[[ $code != 0 ]] && grep -q 'commits the local branch lacks' <<<\"\$out\""
check "leaves the remote alone" "[[ \$(git -C '$root/origin' rev-parse feat) == '$before' ]]"

echo "== a conflicting rebase is aborted"
setup
git switch -q feat && echo conflict >m && git add m && git commit -qm "feat: other m" && git push -q origin feat && git switch -q main
before=$(git -C "$root/origin" rev-parse feat)
run feat
check "fails" "[[ $code != 0 ]] && grep -q 'conflicts with origin/main' <<<\"\$out\""
check "pushes nothing" "[[ \$(git -C '$root/origin' rev-parse feat) == '$before' ]]"
check "leaves no worktree behind" "[[ \$(git worktree list | wc -l) == 1 ]]"

echo "== a branch checked out in a worktree is rebased there, only when clean"
setup
git worktree add -q "$root/c-feat" feat
echo dirty >>"$root/c-feat/f"
run feat
check "a dirty worktree is refused" "[[ $code != 0 ]] && grep -q 'has local changes' <<<\"\$out\""
git -C "$root/c-feat" checkout -q f
run feat
check "a clean one is rebased" "[[ $code == 0 ]] && contains_main"
check "the worktree follows" "[[ \$(git -C '$root/c-feat' rev-parse HEAD) == \$(git -C '$root/origin' rev-parse feat) ]]"
git worktree remove -f "$root/c-feat"

echo "== a branch already on main pushes nothing"
setup
run feat
run feat
check "exits 0 and says so" "[[ $code == 0 ]] && grep -q 'nothing pushed' <<<\"\$out\""

echo "$pass passed, $fail failed"
((fail == 0))
