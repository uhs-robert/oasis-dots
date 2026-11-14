#!/usr/bin/env bash
# Tests that the installer ships the Firefox autoconfig pair only when /usr/lib/firefox exists, that mozilla.cfg loads
# the one named script and nothing else, and that uninstall.sh takes both files off.
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
if grep -q 'directoryEntries\|endsWith' "$cfg"; then fail 'mozilla.cfg globs the chrome folder'; fi
grep -q 'script.exists()' "$cfg" || fail 'mozilla.cfg does not skip a missing script'
grep -q 'reportError' "$cfg" || fail 'mozilla.cfg does not log load errors to the console'
# Firefox skips the first line, so it must be a comment.
head -n1 "$cfg" | grep -q '^//' || fail 'first line of mozilla.cfg is not a comment'

# The hook-free design depends on the package not owning these paths. A hook for them would be dead weight.
if [[ -e $repo_dir/system/etc/pacman.d/hooks/firefox-autoconfig.hook ]]; then fail 'a firefox pacman hook exists although the package does not own the files'; fi

# install_system_files tests /usr/lib/firefox on the real machine, so only the guarded block is checked.
grep -qF 'sudo install -Dm644 system/usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/defaults/pref/autoconfig.js' "$repo_dir/lib/install/system.sh" || fail 'installer does not install autoconfig.js'
grep -qF 'sudo install -Dm644 system/usr/lib/firefox/mozilla.cfg /usr/lib/firefox/mozilla.cfg' "$repo_dir/lib/install/system.sh" || fail 'installer does not install mozilla.cfg'
guard=$(grep -n 'if \[\[ -d /usr/lib/firefox \]\]' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
first=$(grep -n 'system/usr/lib/firefox/mozilla.cfg' "$repo_dir/lib/install/system.sh" | head -n1 | cut -d: -f1)
if [[ -z $guard || -z $first ]] || ! ((guard < first)); then fail 'firefox install is not guarded by /usr/lib/firefox existing'; fi

# uninstall.sh runs main when sourced and removes only paths it lists, so the list is what is checked.
grep -q 'firefox' "$repo_dir/uninstall.sh" || fail 'uninstall.sh does not list the firefox files'
for f in /usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/mozilla.cfg; do
  grep -qxF "    $f" "$repo_dir/uninstall.sh" || fail "uninstall.sh does not remove $f"
done

exit $((failures > 0))
