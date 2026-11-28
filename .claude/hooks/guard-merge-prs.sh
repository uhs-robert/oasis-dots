#!/usr/bin/env bash
# PreToolUse(Bash): a merging merge-prs.sh call may not target this repo (main checkout or any worktree); the merge goes
# through ship-batch. merge-prs.sh has no repo option: it acts on the repo of its cwd, so the target is the session cwd
# as moved by the cd commands before the call. A target the hook cannot resolve is blocked (fail closed).
# Why a hook and not permissions.deny globs: a glob cannot tell which repo a command targets, and it misses flags
# before the PR number.
# shellcheck disable=SC2016 # the sed program holds literal $, ( and backtick
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
# Fast exit: nearly every Bash call does not mention the script.
[[ $cmd == *merge-prs* ]] || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
cwd=${cwd:-$PWD}
root=${CLAUDE_PROJECT_DIR:-$cwd}

# repo_state <dir>: prints "this" for a checkout of this repo, "other" for any other dir, "unknown" when it cannot tell.
repo_state() {
  local dir=$1 mine theirs
  [[ -n $dir && -d $dir ]] || {
    echo unknown
    return
  }
  mine=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    echo unknown
    return
  }
  theirs=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    echo other
    return
  }
  if [[ $(realpath -m "$mine") == "$(realpath -m "$theirs")" ]]; then echo this; else echo other; fi
}

# cd_target <word>: the new directory, or empty when it is not a plain path (a variable, "cd -", a substitution).
cd_target() {
  local p=$1
  [[ $p != *[\$\`]* && $p != - ]] || return 1
  [[ $p != "~"* ]] || p="$HOME${p#\~}"
  [[ $p == /* ]] || p="$cur/$p"
  realpath -m "$p"
}

block() {
  echo "guard: merges in this repo go through .claude/skills/ship-batch/ship-batch.sh <n>... ($1). merge-prs.sh is allowed here only with --check, or in another repo." >&2
  exit 2
}

# A cd target built by substitution becomes an unresolvable variable, and quoted cd targets lose their quotes, so the
# splitting below keeps each path in one piece.
cmd=${cmd//$'\\\n'/ }
cmd=$(sed -E "s/(^|[^[:alnum:]_])(cd|pushd)[[:space:]]+(-[-A-Za-z]*[[:space:]]+)*(\"[^\"]*[\$\`][^\"]*\"|[^[:space:];&|\"']*[\$\`][^[:space:];&|]*)/\1\2 \$UNRESOLVED/g; s/(^|[^[:alnum:]_])(cd|pushd)[[:space:]]+(-[-A-Za-z]*[[:space:]]+)*([\"'])([^\"']*)\4/\1\2 \5/g" <<<"$cmd")

# One word per line for grouping marks ( ) quotes and backticks, so a cd inside them does not leak out; commands are
# split on ; & | and newlines.
cur=$cwd
stack=()
dq=0 sq=0 bt=0
while IFS= read -r segment; do
  segment=${segment#"${segment%%[![:space:]]*}"}
  [[ -n $segment ]] || continue
  case $segment in
  "(")
    stack+=("$cur")
    continue
    ;;
  ")")
    if ((${#stack[@]})); then
      cur=${stack[-1]}
      unset 'stack[-1]'
    fi
    continue
    ;;
  '"' | "'" | '`')
    case $segment in
    '"')
      dq=$((1 - dq))
      open=$dq
      ;;
    "'")
      sq=$((1 - sq))
      open=$sq
      ;;
    *)
      bt=$((1 - bt))
      open=$bt
      ;;
    esac
    if ((open)); then stack+=("$cur"); elif ((${#stack[@]})); then
      cur=${stack[-1]}
      unset 'stack[-1]'
    fi
    continue
    ;;
  esac
  read -ra words <<<"$segment"
  # Skip env assignments and wrappers to find the command word.
  i=0
  while ((i < ${#words[@]})); do
    w=${words[i]}
    case $w in
    [A-Za-z_]*=* | env | exec | command | nohup | time | sudo | bash | sh | -*) i=$((i + 1)) ;;
    timeout) i=$((i + 2)) ;;
    *) break ;;
    esac
  done
  w=${words[i]:-}
  w=${w#\{}
  case $w in
  cd | pushd)
    j=$((i + 1))
    while [[ ${words[j]:-} == -[!-]* || ${words[j]:-} == -- ]]; do j=$((j + 1)); done
    if ((j >= ${#words[@]})); then
      cur=$HOME
    elif next=$(cd_target "${words[j]}"); then
      cur=$next
    else
      cur=""
    fi
    continue
    ;;
  esac
  # A command word built from a variable or substitution, in a command that names the script, is treated as the script.
  if [[ ${w##*/} != merge-prs.sh && ! ($w == *[\$\`]* && $cmd == *merge-prs*) ]]; then
    continue
  fi
  [[ " ${words[*]} " != *" --check "* && " ${words[*]} " != *" --help "* && " ${words[*]} " != *" -h "* ]] || continue
  case $(repo_state "$cur") in
  this) block "this call targets $(realpath -m "$cur")" ;;
  unknown) block "the target repo could not be resolved from: ${segment}" ;;
  esac
done < <(sed -E 's/\$\(/\n(\n/g; s/\(/\n(\n/g; s/\)/\n)\n/g; s/`/\n`\n/g; s/"/\n"\n/g; s/'"'"'/\n'"'"'\n/g' <<<"$cmd" | tr -s '&|;' '\n')
exit 0
