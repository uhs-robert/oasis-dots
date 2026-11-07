#!/usr/bin/env bash
# Tests that install_system_files ships the uinput udev rule (ydotool access without the input group) and applies it to the
# running system, and that uninstall.sh's remove_system_files takes it back off, with sudo stubbed.
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
line_of() { grep -nxF "$1" "$scratch/sudo.log" | head -n1 | cut -d: -f1; }
installed=$(line_of "install -Dm644 system/etc/udev/rules.d/70-dotfiles-uinput.rules $dest")
reloaded=$(line_of 'udevadm control --reload')
triggered=$(line_of 'udevadm trigger --name-match=uinput')
# Without these the running system keeps the old /dev/uinput permissions until a reboot.
if [[ -z $reloaded ]]; then fail 'udev rules are not reloaded'; fi
if [[ -z $triggered ]]; then fail 'the /dev/uinput node is not re-triggered'; fi
if [[ -n $installed && -n $reloaded && -n $triggered ]] && ! ((installed < reloaded && reloaded < triggered)); then
  fail 'udev is reloaded or triggered before the rule is in place'
fi
# --no-system-files skips install_system_files, so it skips the reload and trigger too.
# shellcheck disable=SC2016 # the line is matched as written, not expanded
grep -qxF '  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then install_system_files; fi' "$repo_dir/install.sh" || fail 'install.sh does not gate install_system_files on --no-system-files'
if grep -q 'udevadm' "$repo_dir/install.sh"; then fail 'install.sh runs udevadm outside install_system_files'; fi
if grep -q 'usermod' "$scratch/sudo.log"; then fail 'install_system_files touches groups'; fi

# uninstall.sh runs main when sourced, so only its remove_system_files is loaded.
eval "$(awk '/^remove_system_files\(\) \{/,/^}/' "$repo_dir/uninstall.sh")"
# shellcheck disable=SC2329
confirm() { return 0; }
: >"$scratch/sudo.log"
OPT_SYSTEM_FILES=0 remove_system_files >/dev/null 2>&1
if grep -q 'udevadm' "$scratch/sudo.log"; then fail 'uninstall --no-system-files touches udev'; fi
OPT_SYSTEM_FILES=1 remove_system_files >/dev/null 2>&1
removed=$(line_of "rm -f $dest")
reloaded=$(line_of 'udevadm control --reload')
triggered=$(line_of 'udevadm trigger --name-match=uinput')
if [[ -z $reloaded || -z $triggered ]]; then fail 'uninstall does not reload udev and re-trigger /dev/uinput'; fi
if [[ -n $reloaded && -n $triggered ]] && ! ((reloaded < triggered)); then fail 'uninstall triggers before it reloads'; fi
if [[ -n $removed && -n $reloaded ]] && ! ((removed < reloaded)); then fail 'uninstall reloads udev before it removes the rule'; fi
if grep -q 'usermod.*input' "$repo_dir/install.sh"; then fail 'install.sh adds the user to input'; fi

exit $((failures > 0))
