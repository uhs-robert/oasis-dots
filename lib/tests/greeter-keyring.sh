#!/usr/bin/env bash
# Tests enable_greetd_keyring_unlock against scratch PAM files, with no sudo and no real greetd.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/output.sh"
source "$repo_dir/lib/greeter-keyring.sh"

export GREETD_KEYRING_SUDO=''
export GREETD_PAM_FILE=$scratch/pam.d/greetd
export PAM_GNOME_KEYRING_MODULE=$scratch/security/pam_gnome_keyring.so
mkdir -p "$scratch/pam.d" "$scratch/security"
touch "$PAM_GNOME_KEYRING_MODULE"

stock_greetd='#%PAM-1.0

auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
account    include      system-local-login
session    include      system-local-login'

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

case_name='adds both lines after the last line of their type'
printf '%s\n' "$stock_greetd" >"$GREETD_PAM_FILE"
enable_greetd_keyring_unlock >/dev/null 2>&1
check test "$(sed -n 6p "$GREETD_PAM_FILE")" = "$GREETD_KEYRING_AUTH_LINE"
check test "$(sed -n 7p "$GREETD_PAM_FILE")" = 'account    include      system-local-login'
check test "$(tail -n 1 "$GREETD_PAM_FILE")" = "$GREETD_KEYRING_SESSION_LINE"
check test "$(grep -vxF -e "$GREETD_KEYRING_AUTH_LINE" -e "$GREETD_KEYRING_SESSION_LINE" "$GREETD_PAM_FILE")" = "$stock_greetd"

case_name='is idempotent'
before=$(stat -c %Y-%i "$GREETD_PAM_FILE")
output=$(enable_greetd_keyring_unlock 2>&1)
check test "$(stat -c %Y-%i "$GREETD_PAM_FILE")" = "$before"
check grep -q 'already unlocks' <<<"$output"

case_name='adds only the missing line'
printf '%s\n%s\n' "$stock_greetd" 'session    optional     pam_gnome_keyring.so' >"$GREETD_PAM_FILE"
enable_greetd_keyring_unlock >/dev/null 2>&1
check test "$(grep -c pam_gnome_keyring "$GREETD_PAM_FILE")" = 2
check test "$(sed -n 6p "$GREETD_PAM_FILE")" = "$GREETD_KEYRING_AUTH_LINE"

case_name='leaves the file alone without the PAM module'
printf '%s\n' "$stock_greetd" >"$GREETD_PAM_FILE"
rm "$PAM_GNOME_KEYRING_MODULE"
enable_greetd_keyring_unlock >/dev/null 2>&1
check test "$(cat "$GREETD_PAM_FILE")" = "$stock_greetd"

[ "$failures" -eq 0 ] || exit 1
echo 'greeter-keyring: ok'
