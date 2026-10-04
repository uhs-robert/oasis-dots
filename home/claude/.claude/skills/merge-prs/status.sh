#!/usr/bin/env bash
# Read-only repo status: open PRs, other worktrees, unmerged branches, untracked top-level entries, main checkout.
set -uo pipefail

worktrees=$(git worktree list --porcelain 2>/dev/null) || {
  echo "status: not inside a git repository" >&2
  exit 1
}
main_dir=$(awk '/^worktree /{print substr($0, 10); exit}' <<<"$worktrees")
cd "$main_dir" || exit 0

default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
default=${default#origin/}
if [[ -z $default ]]; then
  for default in main master; do
    git show-ref --verify -q "refs/remotes/origin/$default" && break
  done
fi
base="origin/$default"

section() {
  echo "$1"
  sed 's/^/  /'
}

prs=$(gh pr list --author @me --json number,title,baseRefName,headRefName,mergeable \
  --jq '.[] | "#\(.number) \(.title) [\(.headRefName) -> \(.baseRefName), \(.mergeable | ascii_downcase)]"' 2>/dev/null) || prs="PRs: gh unavailable"
if [[ $prs == "PRs: gh unavailable" ]]; then
  echo "$prs"
elif [[ -n $prs ]]; then
  section "Open PRs" <<<"$prs"
fi

listed=" $(git branch --show-current) "
lines=""
path=""
branch=""
while IFS= read -r row; do
  case $row in
  "worktree "*)
    path=${row#worktree }
    branch=""
    ;;
  "branch "*) branch=${row#branch refs/heads/} ;;
  "")
    if [[ -n $path && $path != "$main_dir" ]]; then
      dirty=clean
      [[ -z $(git -C "$path" status --porcelain 2>/dev/null) ]] || dirty=dirty
      sync="no upstream"
      if counts=$(git -C "$path" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null); then
        read -r behind ahead <<<"$counts"
        sync="ahead $ahead, behind $behind"
      fi
      lines+="$path (${branch:-detached}): $dirty, $sync"$'\n'
      listed+="$branch "
    fi
    path=""
    ;;
  esac
done <<<"$worktrees"$'\n'
[[ -z $lines ]] || section "Worktrees" <<<"${lines%$'\n'}"

lines=""
while IFS= read -r b; do
  [[ -n $b && $listed != *" $b "* && $b != "$default" ]] || continue
  n=$(git rev-list --count "$base..$b" 2>/dev/null) || continue
  ((n > 0)) && lines+="$b: $n commits not in $base"$'\n'
done < <(git for-each-ref --format='%(refname:short)' refs/heads)
[[ -z $lines ]] || section "Unmerged branches" <<<"${lines%$'\n'}"

untracked=$(git status --porcelain --untracked-files=normal | sed -n 's/^?? //p' | grep -v / || true)
untracked+=$(git status --porcelain --untracked-files=normal | sed -n 's/^?? \([^/]*\)\/.*/\1\//p')
[[ -z $untracked ]] || section "Untracked in main checkout" <<<"$untracked"

cur=$(git branch --show-current)
line="${cur:-detached HEAD}"
if [[ $cur == "$default" ]]; then
  behind=$(git rev-list --count "HEAD..$base" 2>/dev/null || echo 0)
  ((behind > 0)) && line+=", behind $base by $behind"
else
  line+=" (not $default)"
fi
section "Main checkout" <<<"$main_dir: $line"

for script in "$main_dir"/.claude/status.d/*.sh; do
  [[ -x $script ]] || continue
  out=$("$script" 2>&1) || true
  [[ -z $out ]] || section "$(basename "$script" .sh)" <<<"$out"
done
exit 0
