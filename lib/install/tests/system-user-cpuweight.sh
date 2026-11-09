#!/usr/bin/env bash
# Tests that install_system_files ships the user@.service CPUWeight drop-in and has systemd reload it, and that
# uninstall.sh's remove_system_files takes it back off and reloads, with sudo stubbed.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/system.sh"
export DOTFILES_DIR="$repo_dir"
sudo() { printf '%s\n' "$*" >>"$scratch/sudo.log"; }

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

dropin=$repo_dir/system/etc/systemd/system/user@.service.d/50-cpuweight.conf
dest=/etc/systemd/system/user@.service.d/50-cpuweight.conf
line_of() { grep -nxF "$1" "$scratch/sudo.log" | head -n1 | cut -d: -f1; }

install_system_files >/dev/null 2>&1
install_line="install -Dm644 system/etc/systemd/system/user@.service.d/50-cpuweight.conf $dest"
grep -qxF "$install_line" "$scratch/sudo.log" || fail 'drop-in is not installed under /etc/systemd/system/user@.service.d'
[[ -f $dropin ]] || fail 'drop-in is missing from the repo'
# The weight is a [Service] setting, and 50 is below the login session's default of 100.
awk '/^\[Service\]$/ { in_service = 1; next } /^\[/ { in_service = 0 } in_service && /^CPUWeight=50$/ { found = 1 } END { exit !found }' "$dropin" || fail 'drop-in does not set CPUWeight=50 in [Service]'
installed=$(line_of "$install_line")
reloaded=$(line_of 'systemctl daemon-reload')
if [[ -z $reloaded ]]; then fail 'systemd is not reloaded, so the running user manager keeps its weight'; fi
if [[ -n $installed && -n $reloaded ]] && ! ((installed < reloaded)); then fail 'systemd reloads before the drop-in is in place'; fi

# uninstall.sh runs main when sourced, so only its remove_system_files is loaded.
eval "$(awk '/^remove_system_files\(\) \{/,/^}/' "$repo_dir/uninstall.sh")"
# shellcheck disable=SC2329
confirm() { return 0; }
: >"$scratch/sudo.log"
OPT_SYSTEM_FILES=0 remove_system_files >/dev/null 2>&1
if [[ -s $scratch/sudo.log ]]; then fail 'uninstall --no-system-files runs sudo'; fi
OPT_SYSTEM_FILES=1 remove_system_files >/dev/null 2>&1
# The removal loop skips files this machine does not have, so check the list rather than the sudo log.
grep -qxF "    $dest" "$repo_dir/uninstall.sh" || fail 'uninstall does not list the drop-in for removal'
reloaded=$(line_of 'systemctl daemon-reload')
if [[ -z $reloaded ]]; then fail 'uninstall does not reload systemd'; fi
grep -qxF 'rmdir /etc/systemd/system/user@.service.d' "$scratch/sudo.log" || fail 'uninstall leaves the empty drop-in directory'

exit $((failures > 0))
