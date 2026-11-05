#!/usr/bin/env bash
# PreToolUse(Bash): keep subagents off `git stash`. Every worktree of a repo shares one stash stack, so a subagent that
# pops or drops a stash can destroy another worktree's work. Only subagents are checked (the payload has .agent_id,
# as in context-budget.sh); the main session passes. Read-only `list` and `show` pass; every other stash form is
# denied, which also covers `git stash -u` and a bare `git stash`, both of which push.
#
# The command is tokenised by a small quote-aware scan, not a shell parser. Quoted text and heredoc bodies are data,
# so they never trigger. Anything the scan cannot place errs toward deny. Known gaps, left open: `$(...)` inside double
# quotes is read as text, and a `<<` inside quotes is read as a heredoc start.
set -u
input=$(cat)
[[ -n $(jq -r '.agent_id // empty' <<<"$input") ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd == *stash* ]] || exit 0

denied=false

# Words that run the next command; skipped when looking for the command word.
is_prefix_word() {
  case $1 in
  sudo | env | command | time | nice | timeout | xargs | '!' | exec | then | do | else | if | while | until) return 0 ;;
  esac
  return 1
}

# Judges one command given as words: skips prefixes, then checks for git stash or a shell -c body.
check_words() {
  local i=0 n=${#words[@]} w
  while ((i < n)); do
    w=${words[i]}
    if [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      ((i++))
    elif is_prefix_word "$w"; then
      ((i++))
      # Options of the prefix, and the value that sudo -u/-g, nice -n and timeout take.
      while ((i < n)) && [[ ${words[i]} == -* || ${words[i]} =~ ^[0-9.]+[smhd]?$ ]]; do
        [[ $w == sudo && ${words[i]} =~ ^-[ug]$ ]] && ((i++))
        [[ $w == nice && ${words[i]} == -n ]] && ((i++))
        ((i++))
      done
    else
      break
    fi
  done
  ((i < n)) || return 0
  case ${words[i]##*/} in
  git)
    ((i++))
    # Global options before the subcommand; these five take a separate value.
    while ((i < n)) && [[ ${words[i]} == -* ]]; do
      case ${words[i]} in
      -C | -c | --git-dir | --work-tree | --namespace) ((i += 2)) ;;
      *) ((i++)) ;;
      esac
    done
    [[ ${words[i]:-} == stash ]] || return 0
    case ${words[i + 1]:-} in
    list | show) ;;
    *) denied=true ;;
    esac
    ;;
  bash | sh | zsh | dash)
    while ((i < n)) && [[ ${words[i]} != -*c* ]]; do ((i++)); done
    ((i + 1 < n)) && scan "${words[i + 1]}"
    ;;
  esac
}

# Splits $1 into commands at unquoted ; & | ( ) { } ` and newlines, and into words at blanks, dropping quotes.
scan() {
  local text=$1 quote="" word="" in_word=false c i backslash=\\
  local -a words=()
  text=${text//$'\\\n'/}
  drop_heredoc_bodies "$text"
  text=$heredoc_stripped
  for ((i = 0; i < ${#text}; i++)); do
    c=${text:i:1}
    if [[ $quote == "'" ]]; then
      [[ $c == "'" ]] && quote="" || word+=$c
    elif [[ $quote == '"' ]]; then
      if [[ $c == '"' ]]; then
        quote=""
      elif [[ $c == "$backslash" ]]; then
        word+=${text:++i:1}
      else
        word+=$c
      fi
    else
      case $c in
      "'" | '"') quote=$c in_word=true ;;
      "$backslash") word+=${text:++i:1} in_word=true ;;
      ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '(' | ')' | '{' | '}' | '`')
        $in_word && words+=("$word")
        word="" in_word=false
        if [[ $c != ' ' && $c != $'\t' ]]; then
          ((${#words[@]})) && check_words
          words=()
        fi
        ;;
      *) word+=$c in_word=true ;;
      esac
    fi
  done
  $in_word && words+=("$word")
  ((${#words[@]})) && check_words
}

# Sets heredoc_stripped to $1 with each heredoc body removed, keeping the line that opens it. An unquoted heredoc
# still expands $(...) and backticks, so those parts of its body lines are kept as commands. A `<<` after a `#` or
# in `<<<` does not open a heredoc. The body ends only on a line equal to the whole delimiter.
drop_heredoc_bodies() {
  local line delim="" strip_tabs=false expands=false prefix rest
  heredoc_stripped=""
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -n $delim ]]; then
      $strip_tabs && line=${line#"${line%%[!$'\t']*}"}
      if [[ $line == "$delim" ]]; then
        delim=""
      elif $expands; then
        rest=$line
        while [[ $rest =~ (\$\(([^\)]*)\)|\`([^\`]*)\`) ]]; do
          heredoc_stripped+="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"$'\n'
          rest=${rest#*"${BASH_REMATCH[1]}"}
        done
        # An opener left without a closer cannot be read, so deny.
        [[ $rest == *\$\(* || $rest == *\`* ]] && denied=true
      fi
      continue
    fi
    heredoc_stripped+=$line$'\n'
    prefix=${line%%<<*}
    [[ $prefix =~ (^|[[:space:]])# ]] && continue
    if [[ $line =~ (^|[^<])\<\<(-?)[[:space:]]*([\'\"]?)([A-Za-z_][A-Za-z0-9_]*) ]]; then
      delim=${BASH_REMATCH[4]}
      [[ -n ${BASH_REMATCH[2]} ]] && strip_tabs=true || strip_tabs=false
      [[ -z ${BASH_REMATCH[3]} ]] && expands=true || expands=false
    fi
  done <<<"$1"
}

scan "$cmd"
$denied || exit 0
reason="Blocked: all worktrees of a repo share one stash stack, so a stash from here can clobber another worktree's work. Instead: test old code with \`git show <commit>:<path> > /tmp/old-<name>\` (never over a file with unstaged edits), commit before a merge, and do throwaway work in a temporary worktree (\`git worktree add\`)."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
