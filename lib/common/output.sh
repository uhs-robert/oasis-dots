#!/usr/bin/env bash
# Colored output helpers used throughout the install scripts.

info() { printf '\e[34m==> \e[0m%s\n' "$*"; }
success() { printf '\e[32m ✓  \e[0m%s\n' "$*"; }
warn() { printf '\e[33m !  \e[0m%s\n' "$*"; }
die() {
  printf '\e[31m ✗  \e[0m%s\n' "$*" >&2
  exit 1
}
confirm() {
  if [[ "${OPT_YES:-0}" -eq 1 ]]; then
    printf '\e[35m[?] \e[0m%s [y/N] y (auto)\n' "$*"
    return 0
  fi
  local resp
  printf '\e[35m[?] \e[0m%s [y/N] ' "$*"
  read -r resp
  [[ "$resp" =~ ^[Yy]$ ]]
}

# Aborts with a list of any commands from "$@" that are not on PATH.
require_cmd() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing required commands: ${missing[*]}"
}
