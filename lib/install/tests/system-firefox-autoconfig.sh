#!/usr/bin/env bash
# Tests that the installer ships the Firefox autoconfig files only when a profile has the script, that mozilla.cfg loads
# the one named script from the root-owned install dir and nothing else, and that uninstall.sh takes all three files off.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

pref=$repo_dir/system/usr/lib/firefox/defaults/pref/autoconfig.js
cfg=$repo_dir/system/usr/lib/firefox/mozilla.cfg
[[ -f $pref ]] || fail 'autoconfig.js is missing from the repo'
[[ -f $cfg ]] || fail 'mozilla.cfg is missing from the repo'

grep -qxF 'pref("general.config.filename", "mozilla.cfg");' "$pref" || fail 'autoconfig.js does not name mozilla.cfg'
grep -qxF 'pref("general.config.obscure_value", 0);' "$pref" || fail 'autoconfig.js obscures the cfg'
grep -qxF 'pref("general.config.sandbox_enabled", false);' "$pref" || fail 'autoconfig.js does not lift the sandbox'

# The loader reads one folder in the install dir, never the profile (user-writable, so any user-level write would run as chrome code).
grep -qF 'const dir_name = "chrome.d";' "$cfg" || fail 'mozilla.cfg does not name chrome.d'
if grep -q 'UChrm\|ProfD\|ProfLD' "$cfg"; then fail 'mozilla.cfg loads from the profile'; fi
grep -qF 'Services.dirsvc.get("GreD"' "$cfg" || fail 'mozilla.cfg does not load from the install dir'
grep -q 'reportError' "$cfg" || fail 'mozilla.cfg does not log load errors to the console'
grep -qF 'isSymlink()' "$cfg" || fail 'mozilla.cfg follows symlinks when it checks a file'
# The real checks run in a private Firefox: see firefox-chrome-d-loader.sh.
# A syntax error is not caught by the cfg's own try, and Firefox then refuses to start.
if command -v node >/dev/null; then
  node -e 'new Function(require("fs").readFileSync(process.argv[1], "utf8"))' "$cfg" || fail 'mozilla.cfg does not parse'
fi
# Firefox skips the first line, so it must be a comment.
head -n1 "$cfg" | grep -q '^//' || fail 'first line of mozilla.cfg is not a comment'

# The hook-free design depends on the package not owning these paths. A hook for them would be dead weight.
if [[ -e $repo_dir/system/etc/pacman.d/hooks/firefox-autoconfig.hook ]]; then fail 'a firefox pacman hook exists although the package does not own the files'; fi

# install_system_files tests /usr/lib/firefox on the real machine, so only the guarded block is checked.
grep -qF 'sudo install -Dm644 system/usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/defaults/pref/autoconfig.js' "$repo_dir/lib/install/system.sh" || fail 'installer does not install autoconfig.js'
grep -qF 'sudo install -Dm644 system/usr/lib/firefox/mozilla.cfg /usr/lib/firefox/mozilla.cfg' "$repo_dir/lib/install/system.sh" || fail 'installer does not install mozilla.cfg'
# shellcheck disable=SC2016 # the literal $bigicons_source is what system.sh contains
grep -qF 'sudo install -Dm644 "$bigicons_source" /usr/lib/firefox/chrome.d/bigicons.uc.js' "$repo_dir/lib/install/system.sh" || fail 'installer does not install the root-owned chrome.d/bigicons.uc.js'
guard=$(grep -n 'firefox_bigicons_source); then' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
cfg_line=$(grep -n 'sudo install .*system/usr/lib/firefox/mozilla.cfg' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
script_line=$(grep -n 'sudo install .*/usr/lib/firefox/chrome.d/bigicons.uc.js' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
pref_line=$(grep -n 'sudo install .*system/usr/lib/firefox/defaults/pref/autoconfig.js' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
grep -qF 'sudo rm -f /usr/lib/firefox/chrome.d/bigicons.uc.js' "$repo_dir/lib/install/system.sh" || fail 'installer keeps a stale root-owned bigicons.uc.js when no profile has the script'
else_line=$(grep -n 'sudo rm -f /usr/lib/firefox/chrome.d/bigicons.uc.js' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
if [[ -z $else_line ]] || ! ((script_line < else_line)); then fail 'the stale-script removal is not in the no-source branch'; fi
if grep -q 'rm .*/usr/lib/firefox/mozilla.cfg' "$repo_dir/lib/install/system.sh"; then fail 'installer removes mozilla.cfg while autoconfig.js stays'; fi
if [[ -z $guard || -z $script_line ]] || ! ((guard < script_line)); then fail 'firefox install is not guarded by the script check'; fi
if [[ -z $cfg_line ]] || ! ((script_line < cfg_line)); then fail 'mozilla.cfg is installed before the script it loads'; fi
# autoconfig.js names mozilla.cfg, and Firefox will not start when it points at a missing file.
if [[ -z $pref_line ]] || ! ((cfg_line < pref_line)); then fail 'autoconfig.js is installed before mozilla.cfg'; fi
grep -qF -- '--exclude=/usr/lib/firefox/' "$repo_dir/justfile" || fail 'system-apply does not exclude /usr/lib/firefox/'

# The profile check follows symlinks, ignores a profile without the script and names the file to copy.
eval "$(awk '/^firefox_bigicons_source\(\) \{/,/^}/' "$repo_dir/lib/install/system.sh")"
home_dir=$(mktemp -d) || exit 1
trap 'rm -rf "$home_dir"' EXIT
HOME=$home_dir
mkdir -p "$home_dir/.mozilla/firefox/a.default/chrome" "$home_dir/private"
firefox_bigicons_source >/dev/null && fail 'profile without the script counts'
: >"$home_dir/private/bigicons.uc.js"
ln -s "$home_dir/private/bigicons.uc.js" "$home_dir/.mozilla/firefox/a.default/chrome/bigicons.uc.js"
[[ $(firefox_bigicons_source) == "$home_dir/.mozilla/firefox/a.default/chrome/bigicons.uc.js" ]] || fail 'symlinked script is not found'
rm "$home_dir/private/bigicons.uc.js"
firefox_bigicons_source >/dev/null && fail 'dangling symlink counts'
# The owner's profile lives under the XDG root.
mkdir -p "$home_dir/.config/mozilla/firefox/b.default/chrome"
: >"$home_dir/.config/mozilla/firefox/b.default/chrome/bigicons.uc.js"
firefox_bigicons_source >/dev/null || fail 'script under ~/.config/mozilla/firefox is not found'

# uninstall.sh runs main when sourced and removes only paths it lists, so the list is what is checked.
grep -q 'firefox' "$repo_dir/uninstall.sh" || fail 'uninstall.sh does not list the firefox files'
for f in /usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/mozilla.cfg /usr/lib/firefox/bigicons.uc.js; do # the last is the pre-chrome.d path
  grep -qxF "    $f" "$repo_dir/uninstall.sh" || fail "uninstall.sh does not remove $f"
done

# Removing mozilla.cfg while autoconfig.js stays leaves Firefox unable to start.
grep -qF 'kept: autoconfig.js is still installed' "$repo_dir/uninstall.sh" || fail 'uninstall.sh removes mozilla.cfg while autoconfig.js stays'

grep -qF 'rm -rf -- /usr/lib/firefox/chrome.d' "$repo_dir/uninstall.sh" || fail 'uninstall.sh does not remove chrome.d'

# Run the installer's Firefox block and uninstall.sh's chrome.d block against a temp tree: sudo becomes a plain call and
# /usr/lib/firefox becomes the temp tree, so nothing near the real install dir is touched.
fx_root=$home_dir/fx
extract_block() { # file start-pattern end-pattern
  awk -v s="$2" -v e="$3" 'index($0, s) { on = 1 } on { print } on && index($0, e) { exit }' "$1" | sed "s# /usr/lib/firefox# $fx_root#g"
}
install_block=$(extract_block "$repo_dir/lib/install/system.sh" 'local bigicons_source' 'Removed the old')
install_block+=$'\n  fi'
uninstall_block=$(extract_block "$repo_dir/uninstall.sh" '# chrome.d holds the bigicons copy' 'chrome.d not found')
uninstall_block+=$'\nfi'
# shellcheck disable=SC2329 # the stubs are called by the eval-ed blocks
{
  # The test user cannot chown to root, so the stub drops "-o root -g root" and the real install keeps its own mode check.
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
  info() { :; }
  success() { :; }
  warn() { :; }
}
run_install() {
  cd "$repo_dir" || return 1
  eval "$install_block"
}

mkdir -p "$fx_root" "$home_dir/.mozilla/firefox/a.default/chrome"
printf 'one\n' >"$home_dir/.mozilla/firefox/a.default/chrome/bigicons.uc.js"
rm -f "$home_dir/.config/mozilla/firefox/b.default/chrome/bigicons.uc.js"
printf 'legacy\n' >"$fx_root/bigicons.uc.js"
run_install
grep -qF 'sudo install -d -o root -g root -m755 /usr/lib/firefox/chrome.d' "$repo_dir/lib/install/system.sh" || fail 'installer does not reset the owner of chrome.d'
[[ -d $fx_root/chrome.d ]] || fail 'installer does not create chrome.d'
[[ $(stat -c %a "$fx_root/chrome.d") == 755 ]] || fail 'chrome.d is not 0755'
[[ $(stat -c %a "$fx_root/chrome.d/bigicons.uc.js") == 644 ]] || fail 'chrome.d/bigicons.uc.js is not 0644'
[[ $(cat "$fx_root/chrome.d/bigicons.uc.js") == one ]] || fail 'chrome.d/bigicons.uc.js is not the profile copy'
[[ -e $fx_root/bigicons.uc.js ]] && fail 'installer keeps the old copy beside mozilla.cfg'
[[ -f $fx_root/mozilla.cfg && -f $fx_root/defaults/pref/autoconfig.js ]] || fail 'installer does not install the cfg and the pref'
: >"$fx_root/chrome.d/other.uc.js"
rm "$home_dir/.mozilla/firefox/a.default/chrome/bigicons.uc.js"
run_install
[[ -e $fx_root/chrome.d/bigicons.uc.js ]] && fail 'installer keeps the stale chrome.d/bigicons.uc.js'
[[ -e $fx_root/chrome.d/other.uc.js ]] || fail 'installer removes a drop-in it did not install'
[[ -f $fx_root/mozilla.cfg ]] || fail 'installer removes mozilla.cfg when no profile has the script'

eval "$uninstall_block"
[[ -e $fx_root/chrome.d ]] && fail 'uninstall.sh leaves chrome.d behind'
eval "$uninstall_block"

exit $((failures > 0))
