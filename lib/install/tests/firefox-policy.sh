#!/usr/bin/env bash
# Tests install_firefox_extension_policy against a scratch HOME and scratch paths, with no sudo and no real Firefox.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

DOTFILES_DIR=$scratch/dotfiles
export HOME=$scratch/home
source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/voice.sh"

mkdir -p "$DOTFILES_DIR/extras" "$HOME/.local/share/voxcmd" "$scratch/bin"
printf '#!/bin/sh\n' >"$scratch/bin/firefox"
chmod +x "$scratch/bin/firefox"
PATH=$scratch/bin:$PATH
touch "$HOME/.local/share/voxcmd/firefox-host"
chmod +x "$HOME/.local/share/voxcmd/firefox-host"
printf 'signed v1' >"$DOTFILES_DIR/extras/voxcmd-firefox.xpi"

export FIREFOX_POLICY_SUDO=''
export FIREFOX_EXTENSION_XPI_DEST=$scratch/share/voxcmd-firefox.xpi
export FIREFOX_POLICIES_FILE=$scratch/etc/policies/policies.json
export FIREFOX_DISTRIBUTION_POLICIES=$scratch/distribution/policies.json

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}
extension_entry() { jq -r '.policies.ExtensionSettings["voxcmd@oasis-dots"] | "\(.installation_mode) \(.install_url)"' "$FIREFOX_POLICIES_FILE"; }
wanted_entry="normal_installed file://$FIREFOX_EXTENSION_XPI_DEST"

case_name='creates the policy and the xpi from nothing'
install_firefox_extension_policy >/dev/null 2>&1
check test "$(extension_entry)" = "$wanted_entry"
check cmp -s "$DOTFILES_DIR/extras/voxcmd-firefox.xpi" "$FIREFOX_EXTENSION_XPI_DEST"
check test -z "$(find "$scratch/etc/policies" -name '.policies.json.*')"

case_name='is idempotent'
before=$(stat -c %Y-%i "$FIREFOX_POLICIES_FILE" "$FIREFOX_EXTENSION_XPI_DEST")
output=$(install_firefox_extension_policy 2>&1)
check test "$(stat -c %Y-%i "$FIREFOX_POLICIES_FILE" "$FIREFOX_EXTENSION_XPI_DEST")" = "$before"
check grep -q 'already current' <<<"$output"

case_name='copies a changed xpi and leaves the policy'
printf 'signed v2' >"$DOTFILES_DIR/extras/voxcmd-firefox.xpi"
install_firefox_extension_policy >/dev/null 2>&1
check cmp -s "$DOTFILES_DIR/extras/voxcmd-firefox.xpi" "$FIREFOX_EXTENSION_XPI_DEST"
check test "$(extension_entry)" = "$wanted_entry"

case_name='merges into existing policies'
cat >"$FIREFOX_POLICIES_FILE" <<'JSON'
{"policies": {"DisableTelemetry": true, "ExtensionSettings": {"other@x": {"installation_mode": "blocked"}}}}
JSON
install_firefox_extension_policy >/dev/null 2>&1
check test "$(extension_entry)" = "$wanted_entry"
check test "$(jq -r '.policies.DisableTelemetry' "$FIREFOX_POLICIES_FILE")" = true
check test "$(jq -r '.policies.ExtensionSettings["other@x"].installation_mode' "$FIREFOX_POLICIES_FILE")" = blocked

case_name='refuses to overwrite invalid JSON'
echo '{broken' >"$FIREFOX_POLICIES_FILE"
check test "$(
  install_firefox_extension_policy 2>&1 >/dev/null
  echo $?
)" != 0
check test "$(cat "$FIREFOX_POLICIES_FILE")" = '{broken'
echo '{}' >"$FIREFOX_POLICIES_FILE"

case_name='refuses to shadow a distribution policies file'
mkdir -p "$scratch/distribution"
echo '{}' >"$FIREFOX_DISTRIBUTION_POLICIES"
check test "$(
  install_firefox_extension_policy >/dev/null 2>&1
  echo $?
)" != 0
check test "$(cat "$FIREFOX_POLICIES_FILE")" = '{}'
rm "$FIREFOX_DISTRIBUTION_POLICIES"

case_name='skips when the xpi is missing'
rm -rf "${scratch:?}/etc" "${scratch:?}/share"
mv "$DOTFILES_DIR/extras/voxcmd-firefox.xpi" "$scratch/held.xpi"
output=$(install_firefox_extension_policy 2>&1)
check test "$?" = 0
check grep -q 'just sign-firefox-extension' <<<"$output"
check test ! -e "$FIREFOX_POLICIES_FILE"
check test ! -e "$FIREFOX_EXTENSION_XPI_DEST"
mv "$scratch/held.xpi" "$DOTFILES_DIR/extras/voxcmd-firefox.xpi"

case_name='skips when voxcmd is not stowed'
chmod -x "$HOME/.local/share/voxcmd/firefox-host"
install_firefox_extension_policy >/dev/null 2>&1
check test ! -e "$FIREFOX_POLICIES_FILE"
chmod +x "$HOME/.local/share/voxcmd/firefox-host"

case_name='skips when Firefox is not installed'
rm "$scratch/bin/firefox"
PATH=$(printf '%s' "$PATH" | sed "s|$scratch/bin:||")
if ! command -v firefox >/dev/null; then
  install_firefox_extension_policy >/dev/null 2>&1
  check test ! -e "$FIREFOX_POLICIES_FILE"
fi

[ "$failures" -eq 0 ] || exit 1
echo 'firefox-policy: ok'
