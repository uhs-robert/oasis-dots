#!/usr/bin/env bash
# Runs the mozilla.cfg chrome.d loader in a private headless Firefox copy and checks which drop-ins load, in what order,
# and that an unsafe chrome.d loads nothing. Skips when Firefox is not installed.
# The loader has no owner check, so the copy owned by the test user behaves like an install.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
cfg=$repo_dir/system/usr/lib/firefox/mozilla.cfg
fx_src=${KEY_TEST_FIREFOX_DIR:-/usr/lib/firefox}

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

if grep -q 'ctypes\|root_uid' "$cfg"; then fail 'the shipped cfg has an owner check'; fi
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

# The test cfg is the shipped one, and its error log goes to out.txt as "ERR <message>".
install_cfg() {
  local err_fn
  err_fn='var test_err=(m)=>{const f=Components.classes["@mozilla.org/file/local;1"].createInstance(Components.interfaces.nsIFile);f.initWithPath("'$out'");const o=Components.classes["@mozilla.org/network/file-output-stream;1"].createInstance(Components.interfaces.nsIFileOutputStream);o.init(f,0x02|0x08|0x10,0o600,0);const s="ERR "+m+"\n";o.write(s,s.length);o.close();};'
  {
    head -n1 "$cfg"
    printf '%s\n' "$err_fn"
    tail -n +2 "$cfg" | sed 's/Components.utils.reportError(/test_err(/'
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
ERR chrome.d/group.js skipped: not a regular file that only its owner can write
ERR chrome.d/linked.js skipped: not a regular file that only its owner can write
ERR chrome.d/subdir.js skipped: not a regular file that only its owner can write
ERR chrome.d/writable.js skipped: not a regular file that only its owner can write
done'

refused='ERR chrome.d refused: not a real directory that only its owner can write'

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

rm -rf "$work/fx/chrome.d"
install_cfg
run_firefox never 15
expect_out 'missing folder' ''

exit $((failures > 0))
