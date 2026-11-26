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

# Only the named script loads: no directory listing, no suffix match.
grep -qF 'const script_name = "bigicons.uc.js";' "$cfg" || fail 'mozilla.cfg does not name bigicons.uc.js'
if grep -q 'directoryEntries\|endsWith' "$cfg"; then fail 'mozilla.cfg globs a folder'; fi
# The profile is user-writable, so the script must come from the install dir (GreD, where mozilla.cfg itself sits).
if grep -q 'UChrm\|ProfD\|ProfLD' "$cfg"; then fail 'mozilla.cfg loads from the profile'; fi
grep -qF 'Services.dirsvc.get("GreD"' "$cfg" || fail 'mozilla.cfg does not load from the install dir'
grep -q 'script.exists()' "$cfg" || fail 'mozilla.cfg does not skip a missing script'
grep -q 'reportError' "$cfg" || fail 'mozilla.cfg does not log load errors to the console'
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
grep -qF 'sudo install -Dm644 "$bigicons_source" /usr/lib/firefox/bigicons.uc.js' "$repo_dir/lib/install/system.sh" || fail 'installer does not install the root-owned bigicons.uc.js'
guard=$(grep -n 'firefox_bigicons_source); then' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
cfg_line=$(grep -n 'sudo install .*system/usr/lib/firefox/mozilla.cfg' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
script_line=$(grep -n 'sudo install .*/usr/lib/firefox/bigicons.uc.js' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
pref_line=$(grep -n 'sudo install .*system/usr/lib/firefox/defaults/pref/autoconfig.js' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
grep -qF 'sudo rm -f /usr/lib/firefox/bigicons.uc.js' "$repo_dir/lib/install/system.sh" || fail 'installer keeps a stale root-owned bigicons.uc.js when no profile has the script'
else_line=$(grep -n 'sudo rm -f /usr/lib/firefox/bigicons.uc.js' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
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
for f in /usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/mozilla.cfg /usr/lib/firefox/bigicons.uc.js; do
  grep -qxF "    $f" "$repo_dir/uninstall.sh" || fail "uninstall.sh does not remove $f"
done

# Removing mozilla.cfg while autoconfig.js stays leaves Firefox unable to start.
grep -qF 'kept: autoconfig.js is still installed' "$repo_dir/uninstall.sh" || fail 'uninstall.sh removes mozilla.cfg while autoconfig.js stays'

exit $((failures > 0))
