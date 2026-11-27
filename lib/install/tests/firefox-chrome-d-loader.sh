#!/usr/bin/env bash
# Runs the mozilla.cfg chrome.d loader in a private headless Firefox copy and checks which drop-ins load, in what order,
# and that an unsafe chrome.d loads nothing. Skips when Firefox is not installed.
# The copy is owned by the test user, not root, so the cfg's root uid is swapped for the test user's uid in the copy.
# That swap is a text edit of the copy and not a runtime switch, so the shipped cfg has no way to change the expected owner.
# Untested here: a real root-owned install (the swap proves the owner comparison, not that uid 0 is the value in the shipped cfg).
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
cfg=$repo_dir/system/usr/lib/firefox/mozilla.cfg
fx_src=${KEY_TEST_FIREFOX_DIR:-/usr/lib/firefox}

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

grep -qxF '  const root_uid = 0;' "$cfg" || fail 'the shipped cfg does not expect uid 0'
if [[ ! -x $fx_src/firefox ]]; then
  printf 'SKIP no Firefox at %s\n' "$fx_src"
  exit $((failures > 0))
fi

work=$(mktemp -d) || exit 1
fx_pid=''
# shellcheck disable=SC2329 # runs through the EXIT trap
cleanup() {
  [[ -n $fx_pid ]] && kill "$fx_pid" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

cp -r --reflink=auto "$fx_src" "$work/fx" || exit 1
out=$work/out.txt

# A drop-in appends its tag to out.txt. The block scope keeps tags from clashing in the shared window scope.
write_dropin() { # tag path
  printf '{const f=Components.classes["@mozilla.org/file/local;1"].createInstance(Components.interfaces.nsIFile);f.initWithPath("%s");const o=Components.classes["@mozilla.org/network/file-output-stream;1"].createInstance(Components.interfaces.nsIFileOutputStream);o.init(f,0x02|0x08|0x10,0o600,0);const s="%s\\n";o.write(s,s.length);o.close();}' "$out" "$1" >"$2"
}

# The test cfg is the shipped one with the owner swapped, and its error log goes to out.txt as "ERR <message>".
install_cfg() {
  local err_fn
  err_fn='var test_err=(m)=>{const f=Components.classes["@mozilla.org/file/local;1"].createInstance(Components.interfaces.nsIFile);f.initWithPath("'$out'");const o=Components.classes["@mozilla.org/network/file-output-stream;1"].createInstance(Components.interfaces.nsIFileOutputStream);o.init(f,0x02|0x08|0x10,0o600,0);const s="ERR "+m+"\n";o.write(s,s.length);o.close();};'
  {
    head -n1 "$cfg"
    printf '%s\n' "$err_fn"
    tail -n +2 "$cfg" | sed "s/const root_uid = 0;/const root_uid = $(id -u);/; s/Components.utils.reportError(/test_err(/"
  } >"$work/fx/mozilla.cfg"
}

# Starts Firefox on a fresh profile and waits until out.txt has a line matching the pattern, or 40 s (the second argument) pass.
run_firefox() { # wait-pattern [seconds]
  rm -rf "$work/prof" "$out"
  mkdir "$work/prof"
  "$work/fx/firefox" --headless --no-remote --profile "$work/prof" about:blank >"$work/firefox.log" 2>&1 &
  fx_pid=$!
  local i
  for ((i = 0; i < ${2:-40}; i++)); do
    grep -q "$1" "$out" 2>/dev/null && break
    sleep 1
  done
  sleep 1
  kill "$fx_pid" 2>/dev/null
  wait "$fx_pid" 2>/dev/null
  fx_pid=''
}

expect_out() { # label expected-text
  [[ $(cat "$out" 2>/dev/null) == "$2" ]] || fail "$1: got $(tr '\n' '|' <"$out" 2>/dev/null)"
}

install_cfg
mkdir "$work/fx/chrome.d"
chmod 755 "$work/fx/chrome.d"
write_dropin b "$work/fx/chrome.d/b.js"
write_dropin a "$work/fx/chrome.d/a.js"
write_dropin "done" "$work/fx/chrome.d/z.js"
printf 'throw new Error("boom")\n' >"$work/fx/chrome.d/aa_throws.js"
write_dropin writable "$work/fx/chrome.d/writable.js"
chmod 666 "$work/fx/chrome.d/writable.js"
write_dropin group "$work/fx/chrome.d/group.js"
chmod 664 "$work/fx/chrome.d/group.js"
write_dropin linked "$work/fx/linked_target.js"
ln -s ../linked_target.js "$work/fx/chrome.d/linked.js"
write_dropin text "$work/fx/chrome.d/note.txt"
mkdir "$work/fx/chrome.d/subdir.js"

run_firefox '^done$'
expect_out 'safe folder' 'a
ERR chrome.d/aa_throws.js failed to load: Error: boom
b
ERR chrome.d/group.js skipped: not a root-owned regular file that only root can write
ERR chrome.d/linked.js skipped: not a root-owned regular file that only root can write
ERR chrome.d/subdir.js skipped: not a root-owned regular file that only root can write
ERR chrome.d/writable.js skipped: not a root-owned regular file that only root can write
done'

refused='ERR chrome.d refused: not a root-owned directory that only root can write'

chmod 775 "$work/fx/chrome.d"
run_firefox 'refused'
expect_out 'group-writable folder' "$refused"
chmod 755 "$work/fx/chrome.d"

mv "$work/fx/chrome.d" "$work/fx/real_d"
ln -s real_d "$work/fx/chrome.d"
run_firefox 'refused'
expect_out 'symlinked folder' "$refused"
rm "$work/fx/chrome.d"
mv "$work/fx/real_d" "$work/fx/chrome.d"

# Another owner: swap in a uid that is not the test user's.
sed -i "s/const root_uid = $(id -u);/const root_uid = $(($(id -u) + 1));/" "$work/fx/mozilla.cfg"
run_firefox 'refused'
expect_out 'folder owned by another user' "$refused"

rm -rf "$work/fx/chrome.d"
install_cfg
run_firefox never 15
expect_out 'missing folder' ''

exit $((failures > 0))
