#!/usr/bin/env bash
# PreToolUse(Bash): route PR merges through ship-batch, which also cleans up and leaves a running test bar alone.
#
# merge-prs.sh is the merge engine ship-batch calls itself (a subprocess this hook never sees), so a direct run that
# merges skips ship-batch's per-PR check, restows and post-merge check. `--check` and `--help` merge nothing.
#
# Only a command word counts, not a mention in quoted text (`git commit -m "...; merge-prs.sh 1"`). A bounded tokenizer
# splits the command into simple commands, strips wrappers (sudo, timeout, xargs, if/then, ...) and re-scans the
# strings that run as code: `bash -c`/`eval` payloads, command substitutions, and quoted arguments of any command not
# known to treat them as data (ssh, watch, trap, alias). When it cannot tell (unbalanced quotes, a shell reading
# stdin, a payload built at run time) it falls back to the raw-text match this hook used before the tokenizer, which
# denies more; nesting deeper than max_depth is denied outright.
#
# Not caught, all deliberate evasion rather than honest mistakes: variable indirection (`x=merge-prs.sh; $x 1`), a
# command name printed by a substitution (`$(echo merge-prs.sh) 1`), a script file or another language's code that
# contains the call, quote-split or globbed names (`m""erge-prs.sh`), `find -exec`, unquoted `ssh` or `watch`
# arguments, aliases set in an earlier call, `gh alias`, and `gh api` on the merge endpoint.
set -u
cmd=$(jq -r '.tool_input.command // empty')
# Byte-wise substrings: every character the tokenizer acts on is ASCII, and a multibyte locale makes ${s:i:1} slow.
LC_ALL=C

# Cheap first pass, so the common Bash call never reaches the tokenizer.
might_merge() {
  [[ $1 == *merge-prs* ]] || [[ $1 == *merge* && $1 =~ (^|[^[:alnum:]_.-])gh([^[:alnum:]_.-]|$) ]]
}
might_merge "$cmd" || exit 0

# The pre-tokenizer match. The merge-prs.sh form needs command position after `; & | (` backtick or newline, behind
# a fixed list of wrappers; the gh form matches anywhere. The arguments are the last capture group.
nl=$'\n'
raw_prefix='((timeout[[:space:]]+[^[:space:]]+|env|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|bash|sh|exec|nohup|command|time|!)[[:space:]]+)*'
raw_invocation="(^|[;&|(\`$nl])[[:space:]]*${raw_prefix}([^[:space:]]*/)?merge-prs\.sh([^;&|)\`$nl]*)"
raw_gh_merge='gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'
raw_match() {
  local rest=$cmd args
  [[ $cmd =~ $raw_gh_merge ]] && return 0
  while [[ $rest =~ $raw_invocation ]]; do
    args=${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}
    rest=${rest#*"${BASH_REMATCH[0]}"}
    [[ $args =~ ^[[:space:]]*$ || $args =~ [[:space:]](--check|--help|-h)([[:space:]=]|$) ]] || return 0
  done
  return 1
}

# Tokenizer state: the text being parsed (s, length n, position i), and the verdict flags every level checks.
# A command substitution leaves `sub_marker` in the word, so a word built at run time is recognisable as such.
sub_marker=$'\x01'
max_depth=3
found=0 doubt=0

# Characters that end a run the parsers copy whole, as patterns (so unquoted where used): ${s:i:1} copies all of s,
# so one step per character is slow.
word_stop=$'[[:space:];&|(){}#"`$<>\'\\\\]'
dquote_stop='["`$\\]'

# Parses s from i until the end, or for term ")" until the matching paren, evaluating each simple command.
parse() {
  local term=$1 depth=$2 c word="" have_word=0 skip_word=0 parens=0 part rest segment_runs_code=0 line_runs_code=0
  local -a words=() here_strings=() heredoc_delims=() heredoc_quoted=() heredoc_tabs=()
  while ((i < n && ! found && ! doubt)); do
    c=${s:i:1}
    case $c in
    $'\n')
      end_word
      end_segment
      ((i++))
      ((${#heredoc_delims[@]} == 0)) || read_heredocs
      line_runs_code=0
      ;;
    ' ' | $'\t')
      end_word
      ((i++))
      ;;
    ';' | '&' | '|')
      end_word
      end_segment
      ((i++))
      ;;
    '(')
      end_word
      end_segment
      ((parens++, i++))
      ;;
    ')')
      end_word
      end_segment
      ((i++))
      if ((parens)); then
        ((parens--))
      elif [[ $term == ')' ]]; then
        return
      fi
      ;;
    '{' | '}')
      # Reserved words only at a word start (`{ cmd; }`); elsewhere brace expansion or ${var}.
      if ((! have_word)) && [[ $c == '}' || ${s:i+1:1} == [[:space:]] ]]; then
        end_segment
      else
        word+=$c have_word=1
      fi
      ((i++))
      ;;
    '#')
      if ((have_word)); then
        word+=$c
        ((i++))
      else
        rest=${s:i}
        part=${rest%%$'\n'*}
        ((i += ${#part}))
      fi
      ;;
    "'")
      ((i++))
      rest=${s:i}
      [[ $rest == *"'"* ]] || {
        doubt=1
        return
      }
      part=${rest%%"'"*}
      word+=$part have_word=1
      ((i += ${#part} + 1))
      ;;
    '"')
      ((i++))
      have_word=1
      parse_dquote '"' "$depth"
      ;;
    \\)
      [[ ${s:i+1:1} == $'\n' ]] || word+=${s:i+1:1} have_word=1
      ((i += 2))
      ;;
    '`')
      ((i++))
      word+=$sub_marker have_word=1
      parse_backtick "$depth"
      ;;
    '$')
      case ${s:i+1:1} in
      '(')
        ((i += 2))
        word+=$sub_marker have_word=1
        parse_sub "$depth"
        ;;
      "'")
        ((i += 2))
        have_word=1
        parse_ansi
        ;;
      *)
        word+='$' have_word=1
        ((i++))
        ;;
      esac
      ;;
    '<' | '>') parse_redirect "$depth" ;;
    *)
      rest=${s:i}
      # shellcheck disable=SC2295
      part=${rest%%$word_stop*}
      # A stop character no branch above takes (\r, \f) is a plain character.
      part=${part:-$c}
      word+=$part have_word=1
      ((i += ${#part}))
      ;;
    esac
  done
  ((found || doubt)) && return
  end_word
  end_segment
  # An unclosed $( or a heredoc with no body: bash would read on to the end, so take no chances.
  [[ $term == ')' || ${#heredoc_delims[@]} -gt 0 ]] && doubt=1
}

parse_sub() {
  if (($1 >= max_depth)); then
    found=1
  else
    parse ')' $(($1 + 1))
  fi
}

end_word() {
  ((have_word)) || return 0
  if ((skip_word == 2)); then
    here_strings+=("$word")
  elif ((skip_word == 0)); then
    words+=("$word")
  fi
  word="" have_word=0 skip_word=0
}

# A here-string or heredoc is data for a data command, but code for anything else (ssh, python, eval in a loop).
end_segment() {
  local text
  skip_word=0
  if ((${#words[@]})); then
    segment_runs_code=0
    check_command "${words[@]}"
    if ((segment_runs_code)); then
      line_runs_code=1
      for text in "${here_strings[@]}"; do rescan "$text" $((depth + 1)); done
    fi
  fi
  words=() here_strings=()
}

# Inside double quotes only $( and backticks run code; with end "" it scans an unquoted heredoc body.
parse_dquote() {
  local end=$1 depth=$2 c part rest
  while ((i < n && ! found && ! doubt)); do
    c=${s:i:1}
    case $c in
    '"')
      ((i++))
      [[ $end == '"' ]] && return
      word+=$c
      ;;
    \\)
      case ${s:i+1:1} in
      '"' | \\ | '$' | '`')
        word+=${s:i+1:1}
        ((i += 2))
        ;;
      $'\n') ((i += 2)) ;;
      *)
        word+=$c
        ((i++))
        ;;
      esac
      ;;
    '`')
      ((i++))
      word+=$sub_marker
      parse_backtick "$depth"
      ;;
    '$')
      if [[ ${s:i+1:1} == '(' ]]; then
        ((i += 2))
        word+=$sub_marker
        parse_sub "$depth"
      else
        word+=$c
        ((i++))
      fi
      ;;
    *)
      rest=${s:i}
      # shellcheck disable=SC2295
      part=${rest%%$dquote_stop*}
      word+=$part
      ((i += ${#part}))
      ;;
    esac
  done
  [[ $end == '"' ]] && doubt=1
}

parse_backtick() {
  local code="" c
  while ((i < n)); do
    c=${s:i:1}
    if [[ $c == '`' ]]; then
      ((i++))
      rescan "$code" $(($1 + 1))
      return
    elif [[ $c == \\ ]]; then
      case ${s:i+1:1} in
      '`' | \\ | '$') code+=${s:i+1:1} ;;
      *) code+=$c${s:i+1:1} ;;
      esac
      ((i += 2))
    else
      code+=$c
      ((i++))
    fi
  done
  doubt=1
}

# $'...' is data; only its end matters.
parse_ansi() {
  local c
  while ((i < n)); do
    c=${s:i:1}
    if [[ $c == "'" ]]; then
      ((i++))
      return
    elif [[ $c == \\ ]]; then
      word+=${s:i:2}
      ((i += 2))
    else
      word+=$c
      ((i++))
    fi
  done
  doubt=1
}

# A redirection's target is not an argument (`>/dev/null merge-prs.sh 1` runs merge-prs.sh), and an fd number before
# the operator is part of it.
parse_redirect() {
  [[ $word =~ ^[0-9]+$ ]] && word="" have_word=0
  end_word
  case ${s:i:3} in
  '<<<')
    ((i += 3))
    skip_word=2
    ;;
  '<<'*) parse_heredoc_op ;;
  '<(' | '>(')
    ((i += 2))
    word+=$sub_marker have_word=1
    parse_sub "$1"
    ;;
  '>>'* | '>&'* | '>|'* | '<&'* | '<>'*)
    ((i += 2))
    skip_word=1
    ;;
  *)
    ((i++))
    skip_word=1
    ;;
  esac
}

parse_heredoc_op() {
  local tabs=0 quoted=0 delim="" c part rest
  ((i += 2))
  [[ ${s:i:1} == '-' ]] && ((tabs = 1, i++))
  while [[ ${s:i:1} == [' '$'\t'] ]]; do ((i++)); done
  while ((i < n)); do
    c=${s:i:1}
    case $c in
    [[:space:]] | ';' | '&' | '|' | '(' | ')' | '<' | '>') break ;;
    "'" | '"')
      rest=${s:i+1}
      [[ $rest == *"$c"* ]] || {
        doubt=1
        return
      }
      part=${rest%%"$c"*}
      delim+=$part quoted=1
      ((i += ${#part} + 2))
      ;;
    \\)
      delim+=${s:i+1:1} quoted=1
      ((i += 2))
      ;;
    *)
      delim+=$c
      ((i++))
      ;;
    esac
  done
  [[ -n $delim ]] || {
    doubt=1
    return
  }
  heredoc_delims+=("$delim") heredoc_quoted+=("$quoted") heredoc_tabs+=("$tabs")
}

# Called at the start of the line after the heredoc operators; consumes every pending body.
read_heredocs() {
  local h line rest body
  for h in "${!heredoc_delims[@]}"; do
    body=""
    while :; do
      ((i < n)) || {
        doubt=1
        return
      }
      rest=${s:i}
      line=${rest%%$'\n'*}
      ((i += ${#line} + 1))
      if ((heredoc_tabs[h])); then
        while [[ $line == $'\t'* ]]; do line=${line#$'\t'}; done
      fi
      [[ $line == "${heredoc_delims[h]}" ]] && break
      body+=$line$'\n'
    done
    if ((line_runs_code)); then
      rescan "$body" $((depth + 1))
    elif ((! heredoc_quoted[h])); then
      scan_expanding "$body" "$depth"
    fi
  done
  heredoc_delims=() heredoc_quoted=() heredoc_tabs=()
}

with_text() {
  local saved_s=$s saved_i=$i saved_n=$n
  s=$1 i=0 n=${#1}
  "${@:2}"
  s=$saved_s i=$saved_i n=$saved_n
}

scan_expanding() {
  might_merge "$1" || return 0
  local word=""
  with_text "$1" parse_dquote "" "$2"
}

# Parses a string that runs as shell code.
rescan() {
  might_merge "$1" || return 0
  if (($2 > max_depth)); then
    found=1
    return
  fi
  with_text "$1" parse "" "$2"
}

# Advances k past the option words of a wrapper; $1 holds the short options and $2 the long ones that take a value.
skip_opts() {
  local opt j
  while ((k < nw)); do
    opt=${w[k]}
    case $opt in
    --)
      ((k++))
      return
      ;;
    --*=*) ((k++)) ;;
    --?*)
      ((k++))
      [[ " $2 " == *" ${opt#--} "* ]] && ((k++))
      ;;
    -?*)
      ((k++))
      for ((j = 1; j < ${#opt}; j++)); do
        if [[ -n $1 && $1 == *"${opt:j:1}"* ]]; then
          ((j == ${#opt} - 1)) && ((k++))
          break
        fi
      done
      ;;
    *) return ;;
    esac
  done
}

# Like skip_opts for sh-like shells; sets runs_payload for -c and reads_stdin for -s.
skip_shell_opts() {
  local opt j
  while ((k < nw)); do
    opt=${w[k]}
    case $opt in
    --)
      ((k++))
      return
      ;;
    --rcfile | --init-file) ((k += 2)) ;;
    --*) ((k++)) ;;
    [-+]?*)
      ((k++))
      for ((j = 1; j < ${#opt}; j++)); do
        case ${opt:j:1} in
        c) runs_payload=1 ;;
        s) reads_stdin=1 ;;
        o | O)
          ((j == ${#opt} - 1)) && ((k++))
          break
          ;;
        esac
      done
      ;;
    *) return ;;
    esac
  done
}

# Commands whose arguments are data, so quoted text in them is never re-scanned as code.
data_commands=' echo printf cat grep egrep fgrep rg jq sed tee head tail wc sort uniq cut tr less test [ [[ cd ls mkdir touch rm cp mv diff export local declare typeset readonly read true false : notify-send '

# Evaluates one simple command, given as words with quotes removed.
check_command() {
  local -a w=("$@")
  local k=0 nw=$# base arg runs_payload reads_stdin args_from_stdin=0
  while ((k < nw)); do
    if [[ ${w[k]} =~ ^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?= ]]; then
      ((k++))
      continue
    fi
    base=${w[k]##*/}
    base=${base#=}
    case $base in
    if | then | else | elif | do | while | until | '!' | '{' | '}' | coproc | builtin | noglob | nocorrect | - | nohup | source | .) ((k++)) ;;
    repeat) ((k += 2)) ;;
    time | command | setsid)
      ((k++))
      skip_opts "" ""
      ;;
    exec)
      ((k++))
      skip_opts a ""
      ;;
    sudo)
      ((k++))
      skip_opts ugCDhprtTU "user group close-from chdir host prompt role type command-timeout other-user"
      ;;
    doas)
      ((k++))
      skip_opts uC ""
      ;;
    nice)
      ((k++))
      skip_opts n adjustment
      ;;
    ionice)
      ((k++))
      skip_opts cnpPu "class classdata pid pgid uid"
      ;;
    stdbuf)
      ((k++))
      skip_opts ioe "input output error"
      ;;
    xargs)
      ((k++, args_from_stdin = 1))
      skip_opts adEILnPs "arg-file delimiter max-lines max-args max-procs max-chars process-slot-var"
      ;;
    timeout)
      ((k++))
      skip_opts sk "signal kill-after"
      ((k++))
      ;;
    env)
      ((k++))
      check_env_split && return
      skip_opts uC "unset chdir"
      ;;
    eval)
      segment_runs_code=1
      arg="${w[*]:k+1}"
      if [[ $arg == *"$sub_marker"* ]]; then doubt=1; else rescan "$arg" $((depth + 1)); fi
      return
      ;;
    bash | sh | zsh | dash | ksh | mksh | ash | rbash)
      ((k++))
      runs_payload=0 reads_stdin=0
      skip_shell_opts
      if ((runs_payload)); then
        arg=${w[k]-}
        if [[ $arg == *"$sub_marker"* ]]; then doubt=1; else rescan "$arg" $((depth + 1)); fi
        return
      fi
      # A shell reading stdin runs whatever the pipe or heredoc feeds it, which may be quoted text here.
      ((reads_stdin || k >= nw)) && doubt=1
      ;;
    merge-prs.sh)
      ((k + 1 < nw || args_from_stdin)) || return 0
      for arg in "${w[@]:k+1}"; do
        [[ $arg == --check || $arg == --check=* || $arg == --help || $arg == -h ]] && return 0
      done
      found=1
      return
      ;;
    gh)
      ((k++))
      skip_gh_flags
      [[ ${w[k]-} == pr ]] || return 0
      ((k++))
      skip_gh_flags
      [[ ${w[k]-} == merge ]] && found=1
      return
      ;;
    git)
      check_git_args
      return
      ;;
    alias)
      for arg in "${w[@]:k+1}"; do
        rescan "${arg#*=}" $((depth + 1))
      done
      return
      ;;
    case)
      # A case pattern's lone `)` would end a $( early and expose the rest as plain text.
      [[ $term == ')' ]] && doubt=1
      return
      ;;
    *"$sub_marker"*)
      doubt=1
      return
      ;;
    *)
      [[ $data_commands == *" $base "* ]] && return
      segment_runs_code=1
      for arg in "${w[@]:k+1}"; do
        [[ $arg == *[[:space:]\;\&\|\`]* || $arg == *"\$("* ]] && rescan "$arg" $((depth + 1))
      done
      return
      ;;
    esac
  done
}

# env -S splits its value into a command line, which then gets the remaining words as arguments.
check_env_split() {
  local j opt line=""
  for ((j = k; j < nw; j++)); do
    opt=${w[j]}
    case $opt in
    --split-string=*) line="${opt#*=} ${w[*]:j+1}" ;;
    --split-string) line="${w[*]:j+1}" ;;
    --*) continue ;;
    -*S*)
      opt=${opt#*S}
      if [[ -n $opt ]]; then line="$opt ${w[*]:j+1}"; else line="${w[*]:j+1}"; fi
      ;;
    -*) continue ;;
    *) return 1 ;;
    esac
    rescan "$line" $((depth + 1))
    return 0
  done
  return 1
}

skip_gh_flags() {
  while [[ ${w[k]-} == -* ]]; do
    case ${w[k]} in
    -R | --repo) ((k += 2)) ;;
    *) ((k++)) ;;
    esac
  done
}

# git's text arguments are data, except the few that git runs as shell code.
check_git_args() {
  local j next
  for ((j = k + 1; j < nw; j++)); do
    next=${w[j + 1]-}
    case ${w[j]} in
    -x | --exec) rescan "$next" $((depth + 1)) ;;
    --exec=*) rescan "${w[j]#--exec=}" $((depth + 1)) ;;
    -c) [[ $next == alias.*=!* ]] && rescan "${next#*=!}" $((depth + 1)) ;;
    esac
  done
}

s=$cmd i=0 n=${#cmd}
parse "" 0
# A found call stops every level early, which an enclosing quote or $( may then report as unterminated.
if ((! found)); then
  ((doubt)) || exit 0
  raw_match || exit 0
fi

reason="Blocked: merge PRs with \`.claude/skills/ship-batch/ship-batch.sh <pr>...\` (in merge order), not \`gh pr merge\` or a direct \`merge-prs.sh <pr>\`; \`merge-prs.sh --check\` is still fine. ship-batch checks each PR, rebase-merges, rebases stacked PRs, removes merged worktrees and branches, pulls main, restows packages that gained files, syncs the greeter, restarts the bar (skipped while a test bar is running) and checks main. After a PR was merged on GitHub by hand, run \`ship-batch.sh\` with no arguments for the post-merge steps. Load the ship-batch skill for details."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
