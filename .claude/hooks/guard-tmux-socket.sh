#!/usr/bin/env bash
# PreToolUse(Bash): refuse tmux commands that could reach the owner's tmux server.
# Agent sessions run inside the owner's tmux, so $TMUX names the owner's socket, and tmux prefers $TMUX over
# TMUX_TMPDIR: `TMUX_TMPDIR=/tmp/x tmux kill-server` killed the real server. Only -L or -S reliably points elsewhere.
# Known limit: tmux inside a script file or a `bash -c '...'` string is not inspected, nor is a `$(` inside double quotes.
# shellcheck disable=SC1003 # a literal backslash in a case pattern, not an escaped quote
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *tmux* ]] || exit 0

sep=$'\x01'
redir=$'\x02' # prefixes a redirection operator token; the operand follows as its own token
tokens=()

# Splits cmd into words with quotes removed; every command separator becomes a lone $sep token, so a quoted
# mention ("tmux kill-server" as one argument) never looks like a command word. Comments are dropped, and each
# redirection operator becomes a $redir token (a leading fd digit absorbed) so the walker can skip it and its operand.
tokenize() {
  local s=$1 i=0 n=${#1} c nc word='' in_word=0 quote='' heredoc='' line op
  local heredoc_re=$'^<<-?[[:space:]]*[\'"]?([A-Za-z_][A-Za-z0-9_]*)'
  flush() {
    ((in_word)) && tokens+=("$word")
    word='' in_word=0
  }
  while ((i < n)); do
    c=${s:i:1}
    if [[ $quote == "'" ]]; then
      [[ $c == "'" ]] && quote='' || word+=$c
    elif [[ $quote == '"' ]]; then
      if [[ $c == '"' ]]; then
        quote=''
      elif [[ $c == '\' ]]; then
        i=$((i + 1))
        word+=${s:i:1}
      else
        word+=$c
      fi
    else
      case $c in
      "'" | '"') quote=$c in_word=1 ;;
      '\')
        i=$((i + 1))
        word+=${s:i:1} in_word=1
        ;;
      '#')
        if ((in_word)); then word+=$c; else
          while ((i < n)) && [[ ${s:i:1} != $'\n' ]]; do i=$((i + 1)); done
          continue
        fi
        ;;
      ' ' | $'\t') flush ;;
      '<' | '>' | '&')
        if [[ $c == '&' && ${s:i+1:1} != '>' ]]; then
          flush
          tokens+=("$sep")
        else
          [[ $c == '<' && ${s:i} =~ $heredoc_re && ${s:i:3} != '<<<' ]] && heredoc=${BASH_REMATCH[1]}
          # A fd number just before the operator belongs to it.
          if ((in_word)) && [[ $word =~ ^[0-9]+$ ]]; then word='' in_word=0; fi
          flush
          op=$c
          for _ in 1 2; do
            nc=${s:i+1:1}
            if [[ $nc == "$c" || $nc == '&' || $nc == '|' || ($c == '<' && $nc == '>') || ($c == '&' && $nc == '>') ||
              ($op == '<<' && $nc == '-') ]]; then
              op+=$nc
              i=$((i + 1))
              [[ $nc == '&' || $nc == '|' || $nc == '-' ]] && break
            else
              break
            fi
          done
          tokens+=("$redir$op")
        fi
        ;;
      $'\n')
        flush
        tokens+=("$sep")
        if [[ -n $heredoc ]]; then
          # Skip the heredoc body: its text is data, not commands.
          while ((i + 1 < n)); do
            line=${s:i+1}
            line=${line%%$'\n'*}
            i=$((i + ${#line} + 1))
            [[ ${line#"${line%%[![:space:]]*}"} == "$heredoc" ]] && break
          done
          heredoc=''
        fi
        ;;
      ';' | '|' | '(' | ')' | '`')
        flush
        tokens+=("$sep")
        ;;
      *) word+=$c in_word=1 ;;
      esac
    fi
    i=$((i + 1))
  done
  flush
}

# Whether one tmux command is read-only: <subcommand> <has -p> <has a #( format expansion, which runs shell on the server>.
read_only() {
  ((${3})) && return 1
  case $1 in
  ls | list-* | has-session | has | show-options | show | show-environment | showenv) return 0 ;;
  display-message | display) return $((! ${2})) ;;
  esac
  return 1
}

# Prints "allow" or "deny" for the tmux invocation whose arguments are tokens[$1..] up to the next separator.
# Without -L/-S, tmux runs every `;`-separated command (an argument that is or ends in `;`), so each must be read-only.
judge_tmux() {
  local i=$1 first=1 sub='' has_p=0 has_fmt=0 arg ended j ch rest
  for (( ; ; i++)); do
    if ((i >= ${#tokens[@]})) || [[ ${tokens[i]} == "$sep" ]]; then
      if [[ -n $sub || $first == 1 ]]; then read_only "$sub" $has_p $has_fmt || {
        echo deny
        return
      }; fi
      break
    fi
    arg=${tokens[i]}
    if [[ $arg == "$redir"* ]]; then
      i=$((i + 1))
      continue
    fi
    ended=0
    if [[ $arg == *';' ]]; then
      arg=${arg%\;}
      ended=1
    fi
    [[ $arg == *'#('* ]] && has_fmt=1
    if [[ -z $arg ]]; then
      :
    elif [[ -n $sub ]]; then
      [[ $arg =~ ^-[A-Za-z]*p ]] && has_p=1
    elif [[ $first == 1 && $arg == -* ]]; then
      rest=${arg:1}
      for ((j = 0; j < ${#rest}; j++)); do
        ch=${rest:j:1}
        case $ch in
        L | S)
          echo allow
          return
          ;;
        f | c | T)
          # Takes the rest of the cluster, or the next word.
          ((j == ${#rest} - 1)) && i=$((i + 1))
          break
          ;;
        esac
      done
    else
      sub=$arg
    fi
    if ((ended)); then
      if [[ -n $sub || $first == 1 ]]; then read_only "$sub" $has_p $has_fmt || {
        echo deny
        return
      }; fi
      first=0 sub='' has_p=0 has_fmt=0
    fi
  done
  echo allow
}

tokenize "$cmd"

# Walks the tokens; at each command start, skips prefix words and wrappers (with their options) to the command word.
denied=0 at_start=1
for ((k = 0; k < ${#tokens[@]}; k++)); do
  t=${tokens[k]}
  if [[ $t == "$sep" ]]; then
    at_start=1
    continue
  fi
  ((at_start)) || continue
  case $t in
  "$redir"*)
    k=$((k + 1)) # its operand
    continue
    ;;
  [A-Za-z_]*=* | '{' | '!' | if | then | else | elif | while | until | do | time | nohup | command | exec)
    if [[ $t == command && ${tokens[k + 1]:-} == -[vV] ]]; then at_start=0; fi
    continue
    ;;
  env | sudo | nice | timeout | xargs | watch)
    # Skip options (and the arguments of those that take one) so the next word is the real command.
    while [[ ${tokens[k + 1]:-} == -* ]]; do
      opt=${tokens[k + 1]}
      k=$((k + 1))
      case "$t $opt" in
      "env -u" | "env -C" | "env -S" | "sudo -u" | "sudo -g" | "sudo -h" | "sudo -p" | "sudo -C" | "sudo -D" | "sudo -R" | \
        "sudo -T" | "sudo -U" | "nice -n" | "timeout -s" | "timeout -k" | "xargs -I" | "xargs -n" | "xargs -P" | "xargs -L" | \
        "xargs -E" | "xargs -s" | "xargs -d" | "xargs -a" | "watch -n" | "watch --interval") k=$((k + 1)) ;;
      esac
    done
    [[ $t == timeout ]] && k=$((k + 1)) # the duration
    continue
    ;;
  esac
  at_start=0
  if [[ ${t##*/} == tmux ]] && [[ $(judge_tmux $((k + 1))) == deny ]]; then
    denied=1
    break
  fi
done
((denied)) || exit 0

reason="Blocked: this tmux command can reach the owner's tmux server. This session runs inside the owner's tmux, so \$TMUX points at the owner's socket and tmux prefers it over TMUX_TMPDIR; only -L <name> or -S <path> reliably points tmux elsewhere. Never touch the owner's server. Run your own: \`env -u TMUX tmux -L <unique-name> ...\` for every call, including the final \`env -u TMUX tmux -L <unique-name> kill-server\`. Without -L or -S only read-only commands are allowed (ls, list-*, has-session, display-message -p, show-options, show-environment)."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
