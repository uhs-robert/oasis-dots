#!/usr/bin/env bash
# Tests that install_system_files ships the uinput udev rule (ydotool access without the input group), with sudo stubbed.
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

rule=$repo_dir/system/etc/udev/rules.d/70-dotfiles-uinput.rules
dest=/etc/udev/rules.d/70-dotfiles-uinput.rules

install_system_files >/dev/null 2>&1
grep -qxF "install -Dm644 system/etc/udev/rules.d/70-dotfiles-uinput.rules $dest" "$scratch/sudo.log" || fail 'rule is not installed to /etc/udev/rules.d'
[[ -f $rule ]] || fail 'rule file is missing from the repo'
grep -qxF 'KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"' "$rule" || fail 'rule is not the uaccess rule for /dev/uinput'
if grep -q 'GROUP=\|MODE=' "$rule"; then fail 'rule grants a group or mode instead of uaccess'; fi
if grep -q 'usermod' "$scratch/sudo.log"; then fail 'install_system_files touches groups'; fi
if grep -q 'usermod.*input' "$repo_dir/install.sh"; then fail 'install.sh adds the user to input'; fi

exit $((failures > 0))
