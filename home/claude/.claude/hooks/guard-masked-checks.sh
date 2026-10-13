#!/usr/bin/env bash
# PreToolUse(Bash): refuse commits and --continue steps with conflict markers staged, check runs piped into a filter
# that hides their exit code from && or ||, and synthetic CPU load.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ -n $cmd ]] || exit 0
cwd=${cwd:-$PWD}

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Heredoc bodies are text (commit messages, files being written), not commands.
cmd=$(awk '
  skip { line = $0; if (tabs) sub(/^\t+/, "", line); if (line == word) skip = 0; next }
  { print }
  match($0, /<<[-~]?[ ]*["\x27]?[A-Za-z_][A-Za-z_0-9]*["\x27]?/) {
    w = substr($0, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\x27]?/, "", w); sub(/["\x27]$/, "", w); word = w; skip = 1
  }' <<<"$cmd")
# One line, with fd redirections and |& out of the way, so & and | only appear as list and pipe operators and a
# newline reads as the ; it is.
flat=$(sed -E ':a; /\\$/ { N; s/\\\n/ /; ba }; s/[0-9]*>&[0-9-]*/ /g; s/&>>?/>/g; s/\|&/|/g' <<<"$cmd" | tr '\n' ';')

# Command position: start of a list or pipeline element, or the body of a loop or if, past common wrappers.
at_cmd='(^|[;&|(`{]|\$\(|(do|then|else)[[:space:]])[[:space:]]*((sudo|nohup|exec|nice|timeout[[:space:]]+[0-9.]+[smhd]?)[[:space:]]+)*'
rest='([^;&|]|\|[^|&])*' # the rest of a pipeline, up to the next list operator
yes_to_null="${at_cmd}yes([[:space:]][^;&|]*)?(\|$rest)?>[[:space:]]*/dev/null"
stress="${at_cmd}stress(-ng)?([[:space:]]|;|$)"
busy_loop='(while[[:space:]]+(true|:|\[[[:space:]]*1[[:space:]]*\])|for[[:space:]]*\(\([[:space:]]*;[[:space:]]*;[[:space:]]*\)\))[[:space:]]*;[[:space:];]*do[[:space:];]+(:|true)[[:space:]]*;[[:space:];]*done'
if [[ $flat =~ $yes_to_null || $flat =~ $stress || $flat =~ $busy_loop ]]; then
  deny "the owner works on this machine: find flakes from failure output, not synthetic CPU load"
fi

word='[^[:space:];&|]'
checks="just[[:space:]]+check|make[[:space:]]+(check|test)|(npm([[:space:]]+run)?|pnpm|yarn)[[:space:]]+test|pytest"
checks+="|(cargo|go)[[:space:]]+test|($word*/)?tests/run$word*\.sh"
# A repo adds its own check commands to .claude/check-commands, one command or path (globs allowed) per line.
repo_checks=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)/.claude/check-commands
if [[ -f $repo_checks ]]; then
  while IFS= read -r entry; do
    entry=$(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$entry")
    [[ -n $entry ]] || continue
    pattern=$(sed -E 's/[].^$+?(){}|[]/\\&/g; s/[[:space:]]+/[[:space:]]+/g' <<<"$entry")
    pattern=${pattern//\*/"$word*"}
    # A path also matches when run as ./path or by an absolute path.
    [[ $entry != */* ]] || pattern="$word*$pattern"
    checks+="|$pattern"
  done <"$repo_checks"
fi
masked="(^|[[:space:];&|(])($checks)([[:space:]][^;&|]*)?\|[[:space:]]*(tail|head|grep)([[:space:]]$rest)?(&&|\|\|)"
pipefail='-[a-zA-Z]*o[[:space:]]+pipefail'
if [[ $flat =~ $masked ]]; then
  check=${BASH_REMATCH[2]}
  [[ ${BASH_REMATCH[0]} =~ \|[[:space:]]*(tail|head|grep) ]]
  filter=${BASH_REMATCH[1]}
  [[ $flat =~ $pipefail ]] ||
    deny "$check | $filter hides its exit code from &&: write it to a log and tail the log, or set -o pipefail"
fi

[[ $flat =~ git ]] || exit 0

resolve() {
  local p=${1//[\'\"]/}
  [[ $p != *[\$\`]* ]] || return 1
  [[ $p != "~"* ]] || p="$HOME${p#\~}"
  [[ $p == /* ]] || p="$cur/$p"
  realpath -m "$p"
}

# Files in the repo at $1 that would carry conflict markers into the commit. Scope "index" is what is staged now;
# "tracked" adds unstaged changes to tracked files (commit -a); "worktree" also adds untracked files, for a `git add`
# earlier in the command, whose pathspecs are not worth parsing.
marked_files() {
  local top=$1 scope=$2 files
  files=$({
    git -C "$top" diff --cached --name-only --diff-filter=d
    [[ $scope == index ]] || git -C "$top" diff --name-only --diff-filter=d
    [[ $scope != worktree ]] || git -C "$top" ls-files --others --exclude-standard
  } | sort -u)
  [[ -n $files ]] || return 0
  local file
  while IFS= read -r file; do
    if [[ $scope == index ]]; then
      git -C "$top" show ":$file" 2>/dev/null
    else
      cat -- "$top/$file" 2>/dev/null
    fi | has_markers && echo "$file"
  done <<<"$files"
}

# A <<<<<<<, ||||||| or >>>>>>> at the start of a line. A bare ======= is left out: it also underlines Markdown
# headings, and a real conflict that has one also has a <<<<<<< line. -I skips binary files.
has_markers() {
  grep -qIE '^(<{7}|\|{7}|>{7})( |$)'
}

cur=$cwd
staged_tops=" "
while IFS= read -r segment; do
  read -ra words <<<"$segment"
  ((${#words[@]})) || continue
  words[0]=${words[0]#[({]}
  i=0
  while ((i < ${#words[@]})) && [[ ${words[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ((i++)); done
  case ${words[i]:-} in
  cd | pushd)
    if [[ -z ${words[i + 1]:-} ]]; then
      cur=$HOME
    elif next=$(resolve "${words[i + 1]}"); then
      cur=$next
    fi
    continue
    ;;
  git) ;;
  *) continue ;;
  esac
  dir=$cur
  ((i++))
  # Global options before the subcommand; successive -C paths stack like cd.
  while ((i < ${#words[@]})) && [[ ${words[i]} == -* ]]; do
    case ${words[i]} in
    -C)
      saved=$cur
      cur=$dir
      dir=$(resolve "${words[i + 1]:-}") || dir=""
      cur=$saved
      ((i += 2))
      ;;
    -c | --git-dir | --work-tree | --namespace) ((i += 2)) ;;
    *) ((i++)) ;;
    esac
  done
  [[ -n $dir ]] || continue
  sub=${words[i]:-}
  args=" ${words[*]:i+1} "
  scope=""
  case $sub in
  add) top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && staged_tops+="$top " ;;
  commit) scope=index ;;
  rebase | cherry-pick | merge | am | revert) [[ $args == *" --continue "* ]] && scope=index ;;
  esac
  [[ -n $scope ]] || continue
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
  [[ $staged_tops == *" $top "* ]] && scope=worktree
  # commit -a stages every tracked change.
  [[ $scope == index && $sub == commit && $args =~ [[:space:]](-[b-zA-Z]*a[a-zA-Z]*|--all)[[:space:]] ]] && scope=tracked
  files=$(marked_files "$top" "$scope")
  [[ -z $files ]] || deny "conflict markers staged in $(paste -sd ' ' <<<"$files"): resolve them, git add, then continue"
done < <(tr -s '&|;' '\n' <<<"$flat")
exit 0
