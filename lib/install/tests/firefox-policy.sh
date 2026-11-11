#!/usr/bin/env bash
# Tests retire_voxcmd_firefox_extension against a scratch HOME and scratch paths, with no sudo and no real Firefox.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

export HOME=$scratch/home
source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/voice.sh"

export FIREFOX_POLICY_SUDO=''
export FIREFOX_EXTENSION_XPI_DEST=$scratch/share/voxcmd-firefox.xpi
export FIREFOX_POLICIES_FILE=$scratch/etc/policies/policies.json

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}
manifest=$HOME/.mozilla/native-messaging-hosts/voxcmd_firefox.json
host=$HOME/.local/share/voxcmd/firefox-host

install_old_files() {
  mkdir -p "$(dirname "$manifest")" "$(dirname "$host")" "$(dirname "$FIREFOX_EXTENSION_XPI_DEST")" "$(dirname "$FIREFOX_POLICIES_FILE")"
  echo '{"name": "voxcmd_firefox"}' >"$manifest"
  ln -sfn "$scratch/gone/firefox-host" "$host"
  echo 'signed' >"$FIREFOX_EXTENSION_XPI_DEST"
}

case_name='removes the manifest, host link, xpi and policy entry, keeping other policies'
install_old_files
cat >"$FIREFOX_POLICIES_FILE" <<'JSON'
{"policies": {"DisableTelemetry": true, "ExtensionSettings": {"voxcmd@oasis-dots": {"installation_mode": "normal_installed"}, "other@x": {"installation_mode": "blocked"}}}}
JSON
retire_voxcmd_firefox_extension >/dev/null 2>&1
check test ! -e "$manifest"
check test ! -L "$host"
check test ! -e "$FIREFOX_EXTENSION_XPI_DEST"
check test "$(jq -r '.policies.ExtensionSettings["voxcmd@oasis-dots"]' "$FIREFOX_POLICIES_FILE")" = null
check test "$(jq -r '.policies.ExtensionSettings["other@x"].installation_mode' "$FIREFOX_POLICIES_FILE")" = blocked
check test "$(jq -r '.policies.DisableTelemetry' "$FIREFOX_POLICIES_FILE")" = true
check test -z "$(find "$scratch/etc/policies" -name '.policies.json.*')"

case_name='drops an ExtensionSettings left empty'
cat >"$FIREFOX_POLICIES_FILE" <<'JSON'
{"policies": {"DisableTelemetry": true, "ExtensionSettings": {"voxcmd@oasis-dots": {"installation_mode": "normal_installed"}}}}
JSON
retire_voxcmd_firefox_extension >/dev/null 2>&1
check test "$(jq -c '.policies' "$FIREFOX_POLICIES_FILE")" = '{"DisableTelemetry":true}'

case_name='is idempotent and silent when nothing is left'
before=$(stat -c %Y-%i "$FIREFOX_POLICIES_FILE")
output=$(retire_voxcmd_firefox_extension 2>&1)
check test "$?" = 0
check test -z "$output"
check test "$(stat -c %Y-%i "$FIREFOX_POLICIES_FILE")" = "$before"

case_name='works with no policies file and no files at all'
rm -rf "${scratch:?}/etc" "${scratch:?}/share" "${HOME:?}/.mozilla" "${HOME:?}/.local"
retire_voxcmd_firefox_extension >/dev/null 2>&1
check test "$?" = 0
check test ! -e "$FIREFOX_POLICIES_FILE"

case_name='leaves a host link that still points at a file'
mkdir -p "$(dirname "$host")"
echo real >"$scratch/real-host"
ln -sfn "$scratch/real-host" "$host"
retire_voxcmd_firefox_extension >/dev/null 2>&1
check test -L "$host"

case_name='leaves an unrelated invalid policies file alone'
mkdir -p "$(dirname "$FIREFOX_POLICIES_FILE")"
echo '{broken' >"$FIREFOX_POLICIES_FILE"
retire_voxcmd_firefox_extension >/dev/null 2>&1
check test "$?" = 0
check test "$(cat "$FIREFOX_POLICIES_FILE")" = '{broken'

case_name='refuses to rewrite invalid JSON that names the extension'
echo '{"voxcmd@oasis-dots": broken' >"$FIREFOX_POLICIES_FILE"
retire_voxcmd_firefox_extension >/dev/null 2>&1
check test "$?" != 0
check test "$(cat "$FIREFOX_POLICIES_FILE")" = '{"voxcmd@oasis-dots": broken'

case_name='fails when the manifest or the host link cannot be removed'
install_old_files
chmod a-w "$(dirname "$manifest")"
if [ "$(id -u)" != 0 ]; then
  retire_voxcmd_firefox_extension >/dev/null 2>&1
  check test "$?" != 0
  check test -e "$manifest"
  chmod u+w "$(dirname "$manifest")"
  chmod a-w "$(dirname "$host")"
  rm -f "$manifest"
  retire_voxcmd_firefox_extension >/dev/null 2>&1
  check test "$?" != 0
  check test -L "$host"
  chmod u+w "$(dirname "$host")"
fi
chmod -R u+w "$HOME"

[ "$failures" -eq 0 ] || exit 1
echo 'firefox-policy: ok'
