# shellcheck shell=bash
# Sourced by the check-before-* hooks. `enter_command_cd <command> <target regex>` follows, in order, every `cd <dir>`
# that starts a step (`cd <dir> &&` or `cd <dir>;`, at the start or after `&&`, `||` or `;`) before the first match of
# the target in the command, each relative to the last, with the quotes dropped. A `cd` behind an earlier command still
# moves where the target runs, so only the leading one would check the wrong checkout. It succeeds without moving when
# there is none, and fails when a directory is missing.
enter_command_cd() {
  local rest=$1 cd_re='(^|&&|\|\||;)[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*(&&|;)'
  [[ $rest =~ $2 ]] && rest=${rest%%"${BASH_REMATCH[0]}"*}
  while [[ $rest =~ $cd_re ]]; do
    cd "$(tr -d "\"'" <<<"${BASH_REMATCH[2]}")" 2>/dev/null || return
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
}
