# shellcheck shell=bash
# Sourced by the check-before-* hooks. `enter_leading_cd <command>` moves into the directory a leading `cd <dir> &&` (or
# `cd <dir>;`) of the command names, relative to the current directory, with the quotes dropped. It succeeds without
# moving when the command has none, and fails when the directory is missing.
enter_leading_cd() {
  local cd_re='^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*(&&|;)'
  [[ $1 =~ $cd_re ]] || return 0
  cd "$(tr -d "\"'" <<<"${BASH_REMATCH[1]}")" 2>/dev/null || return
}
