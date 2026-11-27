#!/usr/bin/env bash
# Tests the browser module wiring offline: sudo is a stub that records its call, the DesertFox checkout is a temp tree, and
# /usr/lib/firefox is a temp tree, so nothing near the real install dir is touched.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

DOTFILES_DIR=$repo_dir
source "$repo_dir/lib/install/desertfox.sh"
info() { :; }
calls=$scratch/calls
# shellcheck disable=SC2329 # called by the sourced functions
sudo() { printf '%s\n' "$*" >>"$calls"; }

# Without a checkout nothing runs and the lookup defaults to repos/desertfox.
DESERTFOX_DIR='' desertfox_checkout | grep -qxF "$repo_dir/repos/desertfox" || fail 'default checkout is not repos/desertfox'
export DESERTFOX_DIR=$scratch/desertfox
desertfox_module_script >/dev/null && fail 'module counts as wanted without a checkout'
install_desertfox_browser_module || fail 'install fails without a checkout'
uninstall_desertfox_browser_module || fail 'uninstall fails without a checkout'
[[ -e $calls ]] && fail 'sudo ran without a checkout'

mkdir -p "$DESERTFOX_DIR/browser_module"
: >"$DESERTFOX_DIR/browser_module/install.sh"
script=$DESERTFOX_DIR/browser_module/install.sh
desertfox_module_script >/dev/null || fail 'module is not wanted with a checkout'
install_desertfox_browser_module
uninstall_desertfox_browser_module
[[ $(sed -n 1p "$calls") == "bash $script" ]] || fail "install call is: $(sed -n 1p "$calls")"
[[ $(sed -n 2p "$calls") == "bash $script --uninstall" ]] || fail "uninstall call is: $(sed -n 2p "$calls")"

# The module never turns itself on from here.
if grep -rn 'browser_module.enabled' "$repo_dir/lib/install" "$repo_dir/install.sh" "$repo_dir/uninstall.sh" | grep -v '/tests/' | grep -qv '^\S*:[0-9]*:\s*#'; then fail 'the installer touches the enable pref'; fi

# Order: install.sh runs the module after chrome.d exists, uninstall.sh before chrome.d goes.
sys=$(grep -n 'then install_system_files; fi' "$repo_dir/install.sh" | head -n1 | cut -d: -f1)
mod=$(grep -n 'install_desertfox_browser_module' "$repo_dir/install.sh" | head -n1 | cut -d: -f1)
if [[ -z $sys || -z $mod ]] || ! ((sys < mod)); then fail 'install.sh runs the module before chrome.d exists'; fi
un_mod=$(grep -n 'uninstall_desertfox_browser_module' "$repo_dir/uninstall.sh" | head -n1 | cut -d: -f1)
un_rm=$(grep -n 'rm -rf -- /usr/lib/firefox/chrome.d' "$repo_dir/uninstall.sh" | head -n1 | cut -d: -f1)
if [[ -z $un_mod || -z $un_rm ]] || ! ((un_mod < un_rm)); then fail 'uninstall.sh removes chrome.d before the module script runs'; fi

# The gate: with no bigicons source, a checkout with the script still creates chrome.d.
fx_root=$scratch/fx
install_block=$(awk 'index($0, "local bigicons_source") { on = 1 } on { print } on && index($0, "Removed the old") { exit }' "$repo_dir/lib/install/system.sh" | sed "s# /usr/lib/firefox# $fx_root#g")
install_block+=$'\n  fi'
eval "$(awk '/^firefox_bigicons_source\(\) \{/,/^}/' "$repo_dir/lib/install/system.sh")"
install_block="run_block() {
$install_block
}"
eval "$install_block"
# The test user cannot chown to root, so the stub drops "-o root -g root".
# shellcheck disable=SC2329 # called by the eval-ed block
sudo() {
  local args=()
  while (($#)); do
    case $1 in
    -o | -g) shift 2 ;;
    *) args+=("$1") && shift ;;
    esac
  done
  "${args[@]}"
}
HOME=$scratch/home
mkdir -p "$fx_root" "$HOME"
(cd "$repo_dir" && run_block)
[[ -d $fx_root/chrome.d ]] || fail 'chrome.d is not made for the module alone'
[[ -f $fx_root/mozilla.cfg ]] || fail 'mozilla.cfg is not installed for the module alone'
rm -rf "$fx_root"
mkdir -p "$fx_root"
DESERTFOX_DIR=$scratch/none
(cd "$repo_dir" && run_block)
[[ -e $fx_root/chrome.d ]] && fail 'chrome.d is made with neither source nor module'

exit $((failures > 0))
