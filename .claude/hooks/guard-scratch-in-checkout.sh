#!/usr/bin/env bash
# PreToolUse(Bash): refuse test setups (git init/clone/worktree add, mkdir) created directly in the live checkout.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
root=${CLAUDE_PROJECT_DIR:-}
[[ -n $cmd && -n $root ]] || exit 0
root=$(realpath -m "$root")
cwd=${cwd:-$PWD}

resolve() {
  local p=${1//[\'\"]/}
  [[ $p != *[\$\`]* ]] || return 1
  [[ $p != "~"* ]] || p="$HOME${p#\~}"
  [[ $p == /* ]] || p="$cur/$p"
  realpath -m "$p"
}

blocked() {
  local rel first
  [[ $1 == "$root"/* ]] || return 1
  rel=${1#"$root"/}
  first=${rel%%/*}
  [[ $first != .claude ]] || return 1
  [[ $rel == "$first" || ! -e $root/$first ]]
}

targets_of() {
  local -a pos=()
  local skip=0 arg
  for arg in "${@:2}"; do
    if ((skip)); then
      skip=0
      continue
    fi
    case $arg in
    -b | -B | --branch | --depth | -o | -c | --template | --separate-git-dir | --reference | -m | --mode) skip=1 ;;
    -*) ;;
    *) pos+=("$arg") ;;
    esac
  done
  case $1 in
  mkdir) printf '%s\n' "${pos[@]}" ;;
  init) ((${#pos[@]})) && printf '%s\n' "${pos[-1]}" ;;
  clone)
    if ((${#pos[@]} > 1)); then
      printf '%s\n' "${pos[-1]}"
    elif ((${#pos[@]} == 1)); then
      local name=${pos[0]%/}
      name=${name##*/}
      name=${name##*:}
      printf '%s\n' "${name%.git}"
    fi
    ;;
  worktree) ((${#pos[@]})) && printf '%s\n' "${pos[0]}" ;;
  esac
}

cur=$cwd
while IFS= read -r segment; do
  read -ra words <<<"$segment"
  ((${#words[@]})) || continue
  kind=""
  case ${words[0]} in
  cd)
    if ((${#words[@]} > 1)) && next=$(resolve "${words[1]}"); then cur=$next; fi
    continue
    ;;
  mkdir) kind="mkdir" ;;
  git)
    case ${words[1]:-} in
    init | clone) kind=${words[1]} ;;
    worktree) [[ ${words[2]:-} == add ]] && kind=worktree ;;
    esac
    ;;
  esac
  [[ -n $kind ]] || continue
  if [[ $kind == worktree ]]; then
    args=("${words[@]:3}")
  elif [[ $kind == mkdir ]]; then
    args=("${words[@]:1}")
  else
    args=("${words[@]:2}")
  fi
  while IFS= read -r target; do
    [[ -n $target ]] || continue
    path=$(resolve "$target") || continue
    if blocked "$path"; then
      echo "guard: test setups go in the scratchpad or \$TMPDIR, not the live checkout ($root). cd there by absolute path first." >&2
      exit 2
    fi
  done < <(targets_of "$kind" "${args[@]}")
done < <(tr -s "&|;" "\n" <<<"$cmd")
exit 0
