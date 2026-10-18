#!/usr/bin/env bash
# PreToolUse(Bash): refuse tmux commands that could reach the owner's tmux server.
# Agent sessions run inside the owner's tmux, so $TMUX names the owner's socket, and tmux prefers $TMUX over
# TMUX_TMPDIR: `TMUX_TMPDIR=/tmp/x tmux kill-server` killed the real server. Only -L or -S reliably points elsewhere.
# Fails closed: a heredoc with no terminator, or a wrapper option it does not know before a tmux word, is denied.
# Known limit: tmux inside a script file or a `bash -c '...'` string is not inspected, nor is a `$(` inside double
# quotes, nor tmux behind a wrapper command it has no entry for (setsid, stdbuf, ...).
# shellcheck disable=SC1003 # a literal backslash in a case pattern, not an escaped quote
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *tmux* ]] || exit 0

sep=$'\x01'
redir=$'\x02' # prefixes a redirection operator token; the operand follows as its own token
tokens=()
unterminated=0 # a heredoc whose terminator line was not found

# Splits cmd into words with quotes removed; every command separator becomes a lone $sep token, so a quoted
# mention ("tmux kill-server" as one argument) never looks like a command word. Comments are dropped, and each
# redirection operator becomes a $redir token (a leading fd digit absorbed) so the walker can skip it and its operand.
tokenize() {
  local s=$1 i=0 n=${#1} c nc word='' in_word=0 quote='' heredoc='' line op
  local quoted_re=$'^<<-?[[:space:]]*([\'"])([^\'"]*)[\'"]' bare_re=$'^<<-?[[:space:]]*([^[:space:];|&<>)]+)' found
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
          if [[ $c == '<' && ${s:i:2} == '<<' && ${s:i:3} != '<<<' ]]; then
            # The whole delimiter word, quotes dropped; an empty one cannot be found, so it fails closed below.
            if [[ ${s:i} =~ $quoted_re ]]; then
              heredoc=${BASH_REMATCH[2]}
            elif [[ ${s:i} =~ $bare_re ]]; then
              heredoc=${BASH_REMATCH[1]//[\'\"\\]/}
            else
              unterminated=1
            fi
          fi
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
          found=0
          while ((i + 1 < n)); do
            line=${s:i+1}
            line=${line%%$'\n'*}
            i=$((i + ${#line} + 1))
            if [[ ${line#"${line%%[![:space:]]*}"} == "$heredoc" ]]; then
              found=1
              break
            fi
          done
          ((found)) || unterminated=1
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
  [[ -z $heredoc ]] || unterminated=1
}

# Whether a -L/-S value provably names a socket other than the owner's. $1 is L or S, $2 the value. A value the hook
# cannot resolve statically ($var, backticks, ~) or that can be the owner's default socket is refused.
own_socket() {
  local kind=$1 val=$2 norm tmpdir owner=${TMUX%%,*}
  [[ -n $val && $val != *[\$\`~]* ]] || return 1
  tmpdir=$(realpath -m -- "${TMUX_TMPDIR:-/tmp}" 2>/dev/null) || return 1
  if [[ $kind == L ]]; then
    [[ $val != default ]] || return 1
    # -L name is the socket tmux-<uid>/name in the temp dir, which can be the owner's own (a named owner server).
    norm=$(realpath -m -- "$tmpdir/tmux-$(id -u)/$val" 2>/dev/null) || return 1
    [[ -z $owner || $norm != "$(realpath -m -- "$owner" 2>/dev/null)" ]]
    return
  fi
  # A relative path resolves against a cwd that may differ by the time tmux runs.
  [[ $val == /* ]] || return 1
  norm=$(realpath -m -- "$val" 2>/dev/null) || return 1
  [[ $norm == */tmux-[0-9]*/* || $norm == "$tmpdir"/tmux-*/* ]] && return 1
  [[ -z $owner || $norm != "$(realpath -m -- "$owner" 2>/dev/null)" ]]
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
  local i=$1 first=1 sub='' has_p=0 has_fmt=0 arg ended j ch rest val
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
      # -I forwards stdin into a pane, so no flag cluster may carry it.
      [[ $arg =~ ^-[A-Za-z]*I ]] && has_fmt=1
    elif [[ $first == 1 && $arg == -* ]]; then
      rest=${arg:1}
      for ((j = 0; j < ${#rest}; j++)); do
        ch=${rest:j:1}
        case $ch in
        L | S)
          val=${rest:j+1}
          if [[ -z $val ]]; then
            i=$((i + 1))
            val=${tokens[i]:-}
            [[ $val == "$sep" ]] && val=''
          fi
          own_socket "$ch" "$val" && echo allow || echo deny
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

# Sets the option tables of a wrapper: short flags without / with an argument / with an optional joined argument,
# and long options without / with an argument (a long option may also be written --name=value).
wrapper_spec() {
  short_flag='' short_arg='' short_opt='' long_flag='' long_arg=''
  case $1 in
  env)
    short_flag=i0v short_arg=uCS
    long_flag='ignore-environment null debug list-signal-handling block-signal default-signal ignore-signal'
    long_arg='unset chdir split-string'
    ;;
  sudo)
    short_flag=AbEeHiKklnPSsVvB short_arg=ughpCDRTUrt
    long_flag='askpass background preserve-env set-home login remove-timestamp reset-timestamp list non-interactive preserve-groups stdin shell validate version help edit bell'
    long_arg='user group host prompt chdir chroot role type other-user command-timeout close-from login-class'
    ;;
  nice) short_arg=n long_arg=adjustment ;;
  timeout) short_flag=v short_arg=sk long_flag='foreground preserve-status verbose' long_arg='signal kill-after' ;;
  xargs)
    short_flag=0prtxo short_arg=INPLEsda short_opt=ile
    long_flag='null no-run-if-empty verbose interactive open-tty exit show-limits help version replace eof max-lines'
    long_arg='arg-file delimiter max-args max-procs max-chars process-slot-var'
    ;;
  watch)
    short_flag=bcCegptvwxh short_arg=nq short_opt=d
    long_flag='beep color no-color errexit chgexit precise no-title no-wrap exec help version differences'
    long_arg='interval equexit'
    ;;
  command) short_flag=p ;;
  exec) short_flag=cl short_arg=a ;;
  time) short_flag=p ;;
  esac
}

# Skips the options of wrapper tokens[$2] (named $1). Sets wrapper_end to the index of the last token consumed,
# wrapper_unknown when an option is not in the wrapper's tables, and wrapper_deny when env -S carries a tmux command.
skip_wrapper_options() {
  local w=$1 idx=$2 opt name val has_eq rest j ch
  wrapper_unknown=0 wrapper_deny=0
  wrapper_spec "$w"
  while ((idx + 1 < ${#tokens[@]})); do
    opt=${tokens[idx + 1]}
    [[ $opt == -* ]] || break
    idx=$((idx + 1))
    [[ $opt == -- ]] && break
    [[ $opt == - && $w == env ]] && continue
    if [[ $opt == --* ]]; then
      name=${opt#--} has_eq=0 val=''
      if [[ $name == *=* ]]; then
        val=${name#*=} name=${name%%=*} has_eq=1
      fi
      if [[ " $long_arg " == *" $name "* ]]; then
        if ((! has_eq)); then
          idx=$((idx + 1))
          val=${tokens[idx]:-}
        fi
        [[ $w == env && $name == split-string && $val == *tmux* ]] && wrapper_deny=1
      elif [[ " $long_flag " != *" $name "* ]]; then
        wrapper_unknown=1
        break
      fi
    else
      rest=${opt:1}
      [[ $w == nice && $rest =~ ^[0-9]+$ ]] && continue
      for ((j = 0; j < ${#rest}; j++)); do
        ch=${rest:j:1}
        if [[ -n $short_arg && $short_arg == *"$ch"* ]]; then
          val=${rest:j+1}
          if [[ -z $val ]]; then
            idx=$((idx + 1))
            val=${tokens[idx]:-}
          fi
          [[ $w == env && $ch == S && $val == *tmux* ]] && wrapper_deny=1
          break
        elif [[ -n $short_opt && $short_opt == *"$ch"* ]]; then
          break
        elif [[ -z $short_flag || $short_flag != *"$ch"* ]]; then
          wrapper_unknown=1
          break 2
        fi
      done
    fi
  done
  wrapper_end=$idx
}

# Walks the tokens; at each command start, skips prefix words and wrappers (with their options) to the command word.
denied=0 at_start=1 why=''
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
  [A-Za-z_]*=* | '{' | '!' | if | then | else | elif | while | until | do | nohup)
    continue
    ;;
  env | sudo | nice | timeout | xargs | watch | command | exec | time)
    if [[ $t == command && ${tokens[k + 1]:-} == -[vV] ]]; then
      at_start=0 # `command -v tmux` only looks tmux up
      continue
    fi
    skip_wrapper_options "$t" "$k"
    k=$wrapper_end
    if ((wrapper_deny)); then
      denied=1
      break
    fi
    if ((wrapper_unknown)); then
      # The command word is unknown, so any tmux word behind the unrecognised option is refused.
      j=$((k + 1))
      while ((j < ${#tokens[@]})) && [[ ${tokens[j]} != "$sep" ]]; do
        [[ ${tokens[j]##*/} == tmux ]] && denied=1
        j=$((j + 1))
      done
      ((denied)) && break
      at_start=0
      continue
    fi
    [[ $t == timeout && ${tokens[k + 1]:-} != "$sep" ]] && k=$((k + 1)) # the duration
    continue
    ;;
  esac
  at_start=0
  if [[ ${t##*/} == tmux ]] && [[ $(judge_tmux $((k + 1))) == deny ]]; then
    denied=1
    break
  fi
done
if ((unterminated)); then
  denied=1
  why=" The command has a heredoc whose terminator could not be found, so the rest cannot be checked."
fi
((denied)) || exit 0

reason="Blocked: this tmux command can reach the owner's tmux server. This session runs inside the owner's tmux, so \$TMUX points at the owner's socket and tmux prefers it over TMUX_TMPDIR; only -L <name> or -S <path> reliably points tmux elsewhere. Never touch the owner's server. Run your own: \`env -u TMUX tmux -L <unique-name> ...\` for every call, including the final \`env -u TMUX tmux -L <unique-name> kill-server\`. -L must be a literal name other than \`default\`, and -S a literal path outside /tmp/tmux-<uid>/, \${TMUX_TMPDIR:-/tmp}/tmux-*/ and the owner's \$TMUX socket: a value with \$, a backtick or ~ cannot be verified. Without -L or -S only read-only commands are allowed (ls, list-*, has-session, display-message -p without #(, show-options, show-environment).${why:-}"
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
