#!/usr/bin/env bash
# Tests for voxcmd's click support: the awk matcher on synthetic tesseract output, the coordinate mapping, click-ocr's
# strips, and click.sh's routing through `voxcmd --dry-run`. Run from anywhere: home/voxcmd/tests/run.sh
#
# Nothing here clicks, moves the pointer or captures the screen: it runs inside sandbox.sh, whose stubs stand in for
# grim, magick, tesseract, hyprctl, wlrctl, wl-kbptr and notify-send and log their calls, and voxcmd only ever runs
# with --dry-run. All fixture text is made up.
# Fixtures are read by name inside the strings check evals.
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
[ -z "${SANDBOX_DIR:-}" ] || [ -z "${SANDBOX_TESSERACT_TSV+set}" ] || unset SANDBOX_TESSERACT_TSV
[ -n "${SANDBOX_DIR:-}" ] || exec "$here/sandbox.sh" "$0" "$@"
share_dir=$package/.local/share/voxcmd
matcher=$share_dir/click-match.awk
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
show() { while IFS= read -r line; do printf '   | %s\n' "$line"; done <<<"$1"; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export XDG_RUNTIME_DIR=$root/run
mkdir -p "$XDG_RUNTIME_DIR"

# ---- fixtures -----------------------------------------------------------------------------------------------------

# word <block> <line> <word_num> <left> <top> <width> <height> <conf> <text>: one tesseract word row (level 5).
word() { printf '5\t1\t%s\t1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"; }
# line_box <block> <line> <left> <top> <width> <height>: the level 4 row of a line, which decides which strip owns its words.
line_box() { printf '4\t1\t%s\t1\t%s\t0\t%s\t%s\t%s\t%s\t-1\t\n' "$1" "$2" "$3" "$4" "$5" "$6"; }
header() { printf 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'; }
# window <gx> <gy> <gw> <gh> <iw> <ih>
window() { printf '#window %s %s %s %s %s %s\n' "$@"; }
# strip <i> <y0> <own_top> <own_bottom>
strip() { printf '#strip %s %s %s %s\n' "$@"; }

# match <fixture> <target>: the matcher's candidates, one per line.
match() { CLICK_TARGET="$2" awk -f "$matcher" <<<"$1"; }
field() { awk -F'\t' -v n="$2" '{print $n}' <<<"$1"; }

# A 1000x600 window at 100,50 captured at scale 1: a button, a heading, a link, a paragraph and misread text.
page=$(
  window 100 50 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 60 24 95 Sign
  word 1 1 2 168 100 24 24 96 in
  word 2 1 1 100 160 200 28 94 Welcome
  word 2 1 2 310 160 40 28 94 to
  word 2 1 3 360 160 100 28 94 Acme
  word 3 1 1 500 300 90 24 91 Settings
  word 4 1 1 100 400 140 24 90 Open
  word 4 1 2 250 400 100 24 90 Settings
  word 5 1 1 100 500 80 24 92 Cancel
  word 6 1 1 800 100 70 24 40 Ghost
  word 7 1 1 800 200 70 24 95 Cancei
  word 8 1 1 700 500 60 24 93 Logln
  word 9 1 1 600 560 80 24 93 Item
  word 9 1 2 690 560 20 24 93 2
)

echo "== matching"
out=$(match "$page" "sign in")
check "'sign in' finds the button once" "[[ \$(wc -l <<<\"\$out\") == 1 ]]"
check "match_text drops the filler word" "[[ \$(field \"\$out\" 3) == sign ]]"
check "label keeps the screen text and says where" "[[ \$(field \"\$out\" 4) == 'Sign in - top left' ]]"
check "click lands in the middle of the matched span, trailing filler included" "[[ \$(field \"\$out\" 1),\$(field \"\$out\" 2) == 246,162 ]]"
out=$(match "$page" "sign")
check "a filler not spoken is not absorbed" "[[ \$(field \"\$out\" 1),\$(field \"\$out\" 7) == 230,60 ]]"
out=$(match "$page" "welcome to acme")
check "an inner filler is inside the span" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 7) == 200,360 ]]"
out=$(match "$page" "welcome acme")
check "an inner filler is inside the span even when not spoken" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 7) == 200,360 ]]"
out=$(match "$page" "to acme")
check "a leading filler that is spoken is included" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 7) == 410,150 ]]"
out=$(match "$page" "acme")
check "a leading filler that is not spoken is left out" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 7) == 460,100 ]]"
out=$(match "$page" "welcome")
check "a trailing filler that is not spoken is left out" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 7) == 200,200 ]]"
out=$(match "$page" "the sign in button")
check "words missing from the screen text match nothing" "[[ -z \$out ]]"
out=$(match "$page" "welcome")
check "'welcome' matches the heading run, whose other words the engine weighs" "[[ \$(field \"\$out\" 3) == 'welcome acme' ]]"
out=$(match "$page" "settings")
check "two runs hold 'settings'" "[[ \$(wc -l <<<\"\$out\") == 2 ]]"
check "candidates are in reading order" "[[ \$(field \"\$out\" 2 | paste -sd' ') == '362 462' ]]"
check "a run with extra words keeps them for weak matching" "[[ \$(field \"\$out\" 3 | tail -1) == 'open settings' ]]"
out=$(match "$page" "nothing like this")
check "text absent from the screen matches nothing" "[[ -z \$out ]]"
out=$(match "$page" "ghost")
check "words below the confidence floor are dropped" "[[ -z \$out ]]"
out=$(match "$page" "the")
check "a target of filler words matches nothing" "[[ -z \$out ]]"
out=$(match "$page" "cancel")
check "an i read for an l is a look-alike: the run still matches, with the spoken word" "[[ \$(field \"\$out\" 3 | paste -sd,) == cancel,cancel ]]"
check "the look-alike run is listed with the screen text" "[[ \$(field \"\$out\" 4 | paste -sd,) == 'Cancei - middle right,Cancel - bottom left' ]]"
out=$(match "$page" "login")
check "an l read for an i matches" "[[ \$(field \"\$out\" 3) == login ]]"
out=$(match "$page" "item two")
check "a number word matches its digit" "[[ \$(field \"\$out\" 3) == 'item two' ]]"
out=$(match "$page" "setting")
check "plural on screen matches singular spoken" "[[ \$(wc -l <<<\"\$out\") == 2 ]]"
out=$(match "$page" "cance")
check "short words and prefixes are not fuzzy-matched" "[[ -z \$out ]]"

echo "== words one edit away"
# Each pair is another word as often as a misread one, so the OCR word stays in match_text for voxcmd's word matching
# to call weak or drop, instead of reading as the spoken word and clicking without asking.
near=$(
  window 0 0 1000 800 1000 800
  strip 0 0 0 800
  header
  word 1 1 1 100 50 70 24 95 Clone
  word 2 1 1 100 100 70 24 95 Clean
  word 3 1 1 100 150 70 24 95 Unable
  word 4 1 1 100 200 70 24 95 Expert
  word 5 1 1 100 250 70 24 95 Summit
  word 6 1 1 100 300 70 24 95 Deleted
  word 7 1 1 100 350 70 24 95 Signing
  word 8 1 1 100 400 70 24 95 Logon
  word 9 1 1 100 450 70 24 95 Pause
  word 10 1 1 100 500 70 24 95 Cancal
)
while IFS=: read -r spoken shown; do
  out=$(match "$near" "$spoken")
  check "'$spoken' finds $shown but keeps its text" "[[ \$(wc -l <<<\"\$out\") == 1 && \$(field \"\$out\" 3) == '$shown' ]]"
done <<'PAIRS'
close:clone
clear:clean
enable:unable
export:expert
submit:summit
delete:deleted
sign in:signing
log in:logon
cause:pause
cancel:cancal
PAIRS
looks=$(
  window 0 0 1000 800 1000 800
  strip 0 0 0 800
  header
  word 1 1 1 100 50 70 24 95 C1ose
  word 2 1 1 100 100 70 24 95 Logln
  word 3 1 1 100 150 70 24 95 Signln
)
check "a 1 read for an l is a look-alike, written as the spoken word" "[[ \$(field \"\$(match \"\$looks\" close)\" 3) == close ]]"
check "a joined span of look-alikes is written as the spoken words" "[[ \$(field \"\$(match \"\$looks\" 'sign in')\" 3) == 'sign in' ]]"
check "a joined span only one edit away keeps the OCR word" "[[ \$(field \"\$(match \"\$near\" 'sign in')\" 3) == signing ]]"
run_both=$(
  window 0 0 1000 800 1000 800
  strip 0 0 0 800
  header
  word 1 1 1 100 50 70 24 95 Newtaxk
  word 1 1 2 175 50 40 24 95 Newt
  word 1 1 3 220 50 30 24 95 ask
)
out=$(match "$run_both" 'new task')
check "a look-alike span beats an earlier span that is only close" "[[ \$(field \"\$out\" 3) == 'newtaxk new task' && \$(field \"\$out\" 5) == 175 ]]"

echo "== joined letters and noise"
joined=$(
  window 0 0 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 80 24 71 Newtask
  word 2 1 1 100 200 60 24 90 Signin
  word 3 1 1 100 300 50 24 90 Read
  word 3 1 2 156 300 30 24 90 me
  word 4 1 1 100 400 20 24 90 '|'
  word 4 1 2 130 400 20 24 90 2
  word 4 1 3 160 400 60 24 90 tasks
)
out=$(match "$joined" "new task")
check "one OCR word holds two spoken words" "[[ \$(field \"\$out\" 3) == 'new task' ]]"
check "the joined match is the spoken words, which voxcmd weighs as strong" "[[ \$(field \"\$out\" 4) == 'Newtask - top left' ]]"
out=$(match "$joined" "sign in")
check "'sign in' matches the single word Signin" "[[ \$(field \"\$out\" 3) == 'sign in' ]]"
out=$(match "$joined" "readme")
check "'readme' matches the two words Read me" "[[ \$(field \"\$out\" 3) == readme && \$(field \"\$out\" 4) == 'Read me - middle left' ]]"
check "the span's point is the middle of both OCR words" "[[ \$(field \"\$out\" 1),\$(field \"\$out\" 2) == 143,312 ]]"
out=$(match "$joined" "read me")
check "spoken 'read me' still matches the two words" "[[ \$(field \"\$out\" 3) == 'read me' ]]"
out=$(match "$joined" "new desk")
check "letters that differ do not join" "[[ -z \$out ]]"
out=$(match "$joined" "2 tasks")
check "a noise token is dropped from the label" "[[ \$(field \"\$out\" 4) == '2 tasks - bottom left' ]]"
check "and from the match text" "[[ \$(field \"\$out\" 3) == '2 tasks' ]]"
out=$(match "$joined" "tasks")
check "a lone noise token does not hide a neighbouring word" "[[ \$(wc -l <<<\"\$out\") == 1 && \$(field \"\$out\" 3) == '2 tasks' ]]"

echo "== candidate box"
out=$(match "$page" "sign in")
check "the box is the matched span's, left top width height" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 6),\$(field \"\$out\" 7),\$(field \"\$out\" 8) == 200,150,92,24 ]]"
scaled=$(
  window 317 1080 1600 800 2560 1280
  strip 0 0 0 1280
  header
  word 1 1 1 1600 640 160 64 95 Target
)
out=$(match "$scaled" "target")
check "the box is mapped like the point, by the image scale" "[[ \$(field \"\$out\" 5),\$(field \"\$out\" 6),\$(field \"\$out\" 7),\$(field \"\$out\" 8) == 1317,1480,100,40 ]]"

echo "== duplicates"
dupes=$(
  window 0 0 900 900 900 900
  strip 0 0 0 900
  header
  word 1 1 1 100 100 80 24 95 Next
  word 2 1 1 100 800 80 24 95 Next
  word 3 1 1 700 100 80 24 95 Next
)
out=$(match "$dupes" "next")
check "same text and place gets a numbered label" "[[ \$(field \"\$out\" 4 | paste -sd,) == 'Next - top left,Next - top right,Next - bottom left' ]]"
dupes=$(
  window 0 0 900 900 900 900
  strip 0 0 0 900
  header
  word 1 1 1 100 100 80 24 95 Next
  word 2 1 1 200 100 80 24 95 Next
)
out=$(match "$dupes" "next")
check "same text in the same third is numbered by position" "[[ \$(field \"\$out\" 4 | paste -sd,) == 'Next - top left #1,Next - top left #2' ]]"

echo "== runs"
runs=$(
  window 0 0 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 50 20 95 Save
  word 1 1 2 400 100 50 20 95 Cancel
  word 1 1 3 460 100 50 20 95 now
)
out=$(match "$runs" "save")
check "a wide gap splits a line into separate runs" "[[ \$(field \"\$out\" 3) == save ]]"
out=$(match "$runs" "cancel now")
check "words close together stay one run" "[[ \$(field \"\$out\" 3) == 'cancel now' ]]"
out=$(match "$runs" "save cancel")
check "words from different runs do not combine" "[[ -z \$out ]]"

echo "== coordinate mapping"
mapped() {
  # mapped <gx> <gy> <gw> <gh> <iw> <ih> <left> <top> <w> <h>
  match "$(
    window "$1" "$2" "$3" "$4" "$5" "$6"
    strip 0 0 0 "$6"
    header
    word 1 1 1 "$7" "$8" "$9" "${10}" 95 Target
  )" target | awk -F'\t' '{print $1 "," $2}'
}
check "scale 1: origin plus pixel" "[[ \$(mapped 1920 0 2560 1440 2560 1440 100 200 40 20) == 2040,210 ]]"
# eDP-1: 2560x1600 at scale 1.6, placed at 317,1080: a 1600x800 logical window is captured at 2560x1280.
check "scale 1.6: pixels shrink by the scale" "[[ \$(mapped 317 1080 1600 800 2560 1280 1600 640 160 64) == 1367,1500 ]]"
check "scale 1.6: window at the monitor origin" "[[ \$(mapped 317 1080 1600 800 2560 1280 0 0 16 16) == 322,1085 ]]"
# DP-13: transform 3 at 4480,0, logical 1080x1920, scale 1.5 here. grim returns the upright image, so the rotation
# changes nothing, and a point off both centre lines fails if the axes swap.
check "rotated monitor: the upright image maps by its own axes" "[[ \$(mapped 4480 0 1080 1920 1620 2880 810 240 30 30) == 5030,170 ]]"
# A window spanning monitors is captured at the largest scale touched, so the scale is the image's, not a monitor's.
check "mixed-scale span: scale comes from the image, not the monitor" "[[ \$(mapped 200 100 1000 500 2000 1000 1000 500 100 100) == 725,375 ]]"
# click-ocr refuses such an image; the matcher still keeps the axes apart rather than reuse the horizontal scale.
check "x and y use their own scales" "[[ \$(mapped 0 0 500 400 1000 600 200 300 100 60) == 125,220 ]]"
check "a point left of the origin rounds to the nearest pixel" "[[ \$(mapped -1000 0 100 100 100 100 0 0 3 4) == -999,2 ]]"
check "a point above the origin rounds to the nearest pixel" "[[ \$(mapped 0 -1000 100 100 100 100 0 0 4 3) == 2,-999 ]]"

echo "== strips"
# Two strips of a 1000x800 image: strip 0 owns rows 0-400 and reads to 430, strip 1 owns 400-800 from row 400-30.
strips=$(
  window 0 0 1000 800 1000 800
  strip 0 0 0 400
  header
  word 1 1 1 100 50 60 20 95 Alpha
  word 2 1 1 100 380 60 20 95 Bravo
  word 3 1 1 100 415 60 20 95 Dupe
  strip 1 370 400 800
  header
  word 1 1 1 100 10 60 20 95 Bravo
  word 2 1 1 100 40 60 20 95 Dupe
  word 3 1 1 100 300 60 20 95 Charlie
)
out=$(match "$strips" "bravo")
check "a word seen by two strips is listed once" "[[ \$(wc -l <<<\"\$out\") == 1 ]]"
check "the strip owning the word's centre keeps it" "[[ \$(field \"\$out\" 2) == 390 ]]"
out=$(match "$strips" "dupe")
check "a word in the overlap belongs to the lower strip, offset by its start" "[[ \$(wc -l <<<\"\$out\") == 1 && \$(field \"\$out\" 2) == 420 ]]"
out=$(match "$strips" "charlie")
check "strip rows are offset into the window" "[[ \$(field \"\$out\" 2) == 680 ]]"
same_block=$(
  window 0 0 1000 800 1000 800
  strip 0 0 0 400
  header
  word 1 1 1 100 50 60 20 95 Open
  strip 1 400 400 800
  header
  word 1 1 1 100 60 60 20 95 File
)
check "the same block numbers in two strips are not one line" "[[ -z \$(match \"\$same_block\" 'open file') ]]"
# One line over the cut at 400: "Open" is centred above it and "Project" on it, but the line box is centred on the cut,
# so the lower strip owns both words and the upper one none. Both strips read the whole line.
crossing=$(
  window 0 0 1000 800 1000 800
  strip 0 0 0 400
  header
  line_box 1 1 100 390 200 20
  word 1 1 1 100 390 60 18 95 Open
  word 1 1 2 170 392 100 18 95 Project
  strip 1 320 400 800
  header
  line_box 1 1 100 70 200 20
  word 1 1 1 100 70 60 18 95 Open
  word 1 1 2 170 72 100 18 95 Project
)
out=$(match "$crossing" "open project")
check "a line across a cut is one run, owned by the strip holding its centre" "[[ \$(wc -l <<<\"\$out\") == 1 && \$(field \"\$out\" 3) == 'open project' ]]"
check "and its words are placed by that strip's rows" "[[ \$(field \"\$out\" 6) == 390 ]]"

# ---- click-ocr and click.sh, inside the sandbox -------------------------------------------------------------------------

log=$SANDBOX_DIR/calls.log
# The window is 160x96 logical at 100,50, captured at 256x154 (scale 1.6).
set_window() { SANDBOX_ACTIVEWINDOW_JSON=$1; }
default_window='{"address": "0x2001", "at": [100, 50], "size": [160, 96], "monitor": 0, "stableId": "18000004", "floating": false, "pinned": false, "workspace": {"id": 1}}'
export SANDBOX_ACTIVEWINDOW_JSON="$default_window"
export SANDBOX_GRIM_SCALE=1.6
export SANDBOX_BINDS_JSON='[
  {"description": "Right Click", "submap": "Cursor", "dispatcher": "__lua", "has_description": true, "mouse": false, "key": "X", "arg": 556},
  {"description": "Left Click", "submap": "Cursor", "dispatcher": "__lua", "has_description": true, "mouse": false, "key": "Y", "arg": 555}]'
export SANDBOX_CLIENTS_JSON='[]'
export SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]'
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Sign
  word 1 1 2 136 40 24 24 95 in
  word 2 1 1 160 120 96 24 95 Settings
})
export SANDBOX_TESSERACT_TSV

echo "== click-ocr"
out=$("$share_dir/click-ocr")
check "emits the window and the image size" "[[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
check "emits one strip for a window of normal height" "[[ \$(grep -c '^#strip' <<<\"\$out\") == 1 ]]"
check "captures the window's own buffer by its stable id" "grep -q 'grim -t ppm -T 18000004' '$log' && ! grep -q ' -g ' '$log'"
check "captures at native scale: no -s" "! grep -q ' -s ' '$log'"
check "leaves no screenshot behind" "[[ -z \$(ls '$XDG_RUNTIME_DIR' | grep voxcmd-click) ]]"
: >"$log"
out=$(SANDBOX_GRIM_NO_TOPLEVEL=1 "$share_dir/click-ocr")
check "a failed toplevel capture falls back to the screen region" "grep -q 'grim -t ppm -g 100,50 160x96' '$log' && [[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
SANDBOX_ACTIVEWINDOW_JSON='{"at": [100, 50], "size": [160, 96], "monitor": 0}'
: >"$log"
"$share_dir/click-ocr" >/dev/null
check "no stable id captures the screen region without trying -T" "grep -q 'grim -t ppm -g 100,50 160x96' '$log' && ! grep -q ' -T ' '$log'"
SANDBOX_ACTIVEWINDOW_JSON=$default_window
: >"$log"
out=$(SANDBOX_GRIM_SIZE='256 100' "$share_dir/click-ocr" 2>&1)
check "a toplevel capture of another shape falls back to the screen region, which stands in here for a right one" "grep -q 'grim -t ppm -T' '$log' && grep -q 'grim -t ppm -g' '$log' && [[ \$out == *'does not match'* ]]"
: >"$log"
out=$(SANDBOX_GRIM_SIZE='256 154' "$share_dir/click-ocr" 2>&1)
check "a capture within 2% of the window's shape is used as it is" "! grep -q ' -g ' '$log' && [[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
out=$(SANDBOX_GRIM_SIZE='256 151' "$share_dir/click-ocr" 2>&1)
check "a vertical scale 2% under the horizontal one is still taken" "[[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 151' ]]"
out=$(SANDBOX_GRIM_SIZE='256 140' "$share_dir/click-ocr" 2>&1)
check "a vertical scale 9% under the horizontal one is an error" "! SANDBOX_GRIM_SIZE='256 140' '$share_dir/click-ocr' >/dev/null 2>&1 && [[ \$out == *'does not match'* ]]"
SANDBOX_ACTIVEWINDOW_JSON='{"at": [0, 0], "size": [1000, 1500], "monitor": 0, "stableId": "18000004"}'
out=$(SANDBOX_GRIM_SCALE=1 "$share_dir/click-ocr")
check "a tall window is cut into 4 to 6 strips" "[[ \$(grep -c '^#strip' <<<\"\$out\") -ge 4 && \$(grep -c '^#strip' <<<\"\$out\") -le 6 ]]"
check "strips own contiguous rows from 0 to the image height" "[[ \$(grep '^#strip' <<<\"\$out\" | awk '{if (\$4 != prev) bad = 1; prev = \$5} END {print (bad ? \"gap\" : prev)}') == 1500 ]]"
check "a lower strip's crop starts 80 px above the rows it owns at scale 1" "[[ \$(grep '^#strip 1 ' <<<\"\$out\" | awk '{print \$4 - \$3}') == 80 ]]"
out=$(SANDBOX_GRIM_SCALE=2 "$share_dir/click-ocr")
check "and 160 px above them at scale 2" "[[ \$(grep '^#strip 1 ' <<<\"\$out\" | awk '{print \$4 - \$3}') == 160 ]]"
mkdir -p "$root/failing"
printf '#!/bin/sh\nexit 1\n' >"$root/failing/tesseract"
chmod +x "$root/failing/tesseract"
check "a failed strip fails the whole OCR" "! SANDBOX_GRIM_SCALE=1 PATH='$root/failing':\$PATH '$share_dir/click-ocr' >/dev/null 2>&1"
# One strip fails at once; the rest would sleep for a minute, and the run must not wait for them.
printf '#!/bin/sh\n[ ! -e "%s/slow_started" ] && : >"%s/slow_started" && exit 1\nexec sleep 60\n' "$root" "$root" >"$root/failing/tesseract"
started=$SECONDS
SANDBOX_GRIM_SCALE=1 PATH="$root/failing:$PATH" "$share_dir/click-ocr" >/dev/null 2>&1
check "a failed strip ends the others instead of waiting for them" "[[ \$((SECONDS - started)) -lt 10 && -z \$(pgrep -f 'sleep 60') ]]"
SANDBOX_ACTIVEWINDOW_JSON='{}'
check "no focused window is an error" "! out=\$('$share_dir/click-ocr' 2>&1) && grep -q 'no focused window' <<<\"\$out\""
SANDBOX_ACTIVEWINDOW_JSON=$default_window

echo "== routing with --dry-run"
config=$root/config
mkdir -p "$config/integrations.d" "$config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/click.sh" "$package/.config/voxcmd/integrations.d/keybinds.sh" "$config/integrations.d/"
export VOXCMD_CONFIG_DIR=$config
voxcmd=$package/.local/bin/voxcmd
route() { "$voxcmd" --dry-run "$1" 2>&1; }

: >"$log"
out=$(route "click sign in")
check "a single strong match runs" "grep -q '^result:      run' <<<\"\$out\""
check "it is the Click integration's click" "grep -q 'Click (click.sh).* action=click ' <<<\"\$out\""
box=',[0-9]*,[0-9]*,[0-9]*,[0-9]*'
check "the id carries the mapped point, button and box" "grep -q \"id='[0-9]*,[0-9]*,left$box'\" <<<\"\$out\""
check "click is silent" "grep -q 'silent: true' <<<\"\$out\""
check "dry-run neither clicks nor moves" "! grep -q 'wlrctl\|hyprctl dispatch' '$log'"
check "nothing captured the real screen: every grim call was the stub's, on the window" "! grep -q '^grim' '$log' || ! grep '^grim' '$log' | grep -qv -e ' -T 18000004' -e ' -g 100,50 160x96'"
out=$(route "right click settings")
check "right click carries the right button" "grep -q \"id='[0-9]*,[0-9]*,right$box'\" <<<\"\$out\""
out=$(route "double click on settings")
check "double click, with the filler 'on'" "grep -q \"id='[0-9]*,[0-9]*,double$box'\" <<<\"\$out\""
out=$(route "left click settings")
check "left click is a click" "grep -q \"action=click .*,left$box'\" <<<\"\$out\""
out=$(route "click nowhere to be found")
check "text not on screen reports it instead of falling through" "grep -q 'action=no_text' <<<\"\$out\" && ! grep -q Keybinds <<<\"\$out\""
out=$(route "right click")
check "bare 'right click' stays with the Cursor submap bind" "grep -q 'Keybinds (keybinds.sh)' <<<\"\$out\" && ! grep -q 'Click (click.sh)' <<<\"\$out\""
out=$(route "click")
check "bare 'click' stays with the keybinds" "! grep -q 'Click (click.sh)' <<<\"\$out\""
# "click left", "click it" and the like are no click target: phrases.tsv records that they route as they did without
# Click. Here, that they do not even capture the screen.
: >"$log"
out=$(route "click left")
check "'click left' stays with the keybinds without capturing the screen" "grep -q 'Keybinds (keybinds.sh)' <<<\"\$out\" && ! grep -q '^grim' '$log'"
out=$(route "show hints")
check "'show hints' launches wl-kbptr" "grep -q 'action=show_hints' <<<\"\$out\" && grep -q 'show_hints' <<<\"\$out\""
check "'show hints' is silent" "grep -q 'silent: true' <<<\"\$out\""
out=$(route "show click hints")
check "'show click hints' is the same" "grep -q 'action=show_hints' <<<\"\$out\""
out=$(route "press enter")
check "'press' still forces the keybinds" "grep -q 'forced to:   keybinds.sh' <<<\"\$out\""

# Two matches and a weak one go to the picker; a lone strong one runs.
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Next
  word 2 1 1 160 120 96 24 95 Next
})
out=$(route "click next")
check "several matches ask with the picker" "grep -q 'ask with the picker (2 options' <<<\"\$out\""
check "picker labels say where each is" "grep -q 'Next - middle' <<<\"\$out\" && grep -q 'Next - bottom right' <<<\"\$out\""
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Open
  word 1 1 2 136 40 96 24 95 Settings
})
out=$(route "click settings")
check "a weak match asks with the picker" "grep -q 'ask with the picker (1 options, weak' <<<\"\$out\""
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 80 24 71 Newtask
})
out=$(route "click new task")
check "'new task' runs the single OCR word Newtask as a strong match" "grep -q '^result:      run' <<<\"\$out\""

# The words one edit away route in phrases.tsv; the joined spans need a screen of their own.
while IFS=: read -r spoken shown; do
  SANDBOX_TESSERACT_TSV=$({
    header
    word 1 1 1 80 40 80 24 95 "$shown"
  })
  out=$(route "click $spoken")
  check "'click $spoken' does not run for '$shown'" "! grep -q '^result:      run' <<<\"\$out\" || grep -q 'action=no_text' <<<\"\$out\""
done <<'PAIRS'
sign in:Signing
log in:Logon
PAIRS

echo "== covered text"
# The bar's and other windows' pixels are not in a window's own buffer, so a candidate under them is dropped. The
# text "Sign in" is centred at 175,82 and "Settings" at 230,132 on the screen.
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Sign
  word 1 1 2 136 40 24 24 95 in
  word 2 1 1 160 120 96 24 95 Settings
})
client() { # client <address> <x> <y> <w> <h> <floating> <pinned> <workspace> [<mapped> <hidden>]
  jq -n -c --arg address "$1" --argjson x "$2" --argjson y "$3" --argjson w "$4" --argjson h "$5" --argjson floating "$6" \
    --argjson pinned "$7" --argjson workspace "$8" --argjson mapped "${9:-true}" --argjson hidden "${10:-false}" \
    '{address: $address, at: [$x, $y], size: [$w, $h], floating: $floating, pinned: $pinned, workspace: {id: $workspace},
      mapped: $mapped, hidden: $hidden}'
}
clients() { SANDBOX_CLIENTS_JSON=$(jq -s -c . <<<"$(cat)"); }
runs_at() { # the point the single run option clicks, or "-" when it is not a plain run
  route "$1" | sed -n "s/^option 1: .* id='\([0-9]*,[0-9]*\),.*/\1/p;s/^option 1: .*id='covered:'.*/covered/p" | head -1
}
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true false 1
)"
check "a floating window over a tiled one covers a candidate beneath it" "[[ \$(runs_at 'click sign in') == covered ]]"
check "and leaves the others" "[[ \$(runs_at 'click settings') == 230,132 ]]"
out=$(route "click sign in")
check "all covered is a candidate that says so, not 'not on screen'" "grep -q 'action=click .*id=.covered:' <<<\"\$out\" && ! grep -q no_text <<<\"\$out\""
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 false false 1
)"
check "a tiled window beside it covers nothing" "[[ \$(runs_at 'click sign in') == 175,82 ]]"
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true false 2
)"
check "a floating window on another workspace covers nothing" "[[ \$(runs_at 'click sign in') == 175,82 ]]"
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true true 2
)"
check "a pinned window covers from any workspace" "[[ \$(runs_at 'click sign in') == covered ]]"
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true false 1 false false
)"
check "an unmapped window covers nothing" "[[ \$(runs_at 'click sign in') == 175,82 ]]"
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true false 1 true true
)"
check "a hidden window covers nothing" "[[ \$(runs_at 'click sign in') == 175,82 ]]"
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 false true 1
)"
check "a pinned tiled window still covers an unpinned one" "[[ \$(runs_at 'click sign in') == covered ]]"
SANDBOX_ACTIVEWINDOW_JSON='{"address": "0x2001", "at": [100, 50], "size": [160, 96], "monitor": 0, "stableId": "18000004", "floating": true, "pinned": false, "workspace": {"id": 1}}'
clients <<<"$(
  client 0x2001 100 50 160 96 true false 1
  client 0x3001 150 50 60 60 true false 1
)"
check "a floating window does not cover a focused floating one" "[[ \$(runs_at 'click sign in') == 175,82 ]]"
SANDBOX_ACTIVEWINDOW_JSON=$default_window
SANDBOX_CLIENTS_JSON='[]'
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 100, 0, 0]}]'
check "the monitor's top reserved edge (the bar) covers a candidate in it" "[[ \$(runs_at 'click sign in') == covered && \$(runs_at 'click settings') == 230,132 ]]"
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [200, 0, 0, 0]}]'
check "a reserved left edge covers x under it" "[[ \$(runs_at 'click sign in') == covered && \$(runs_at 'click settings') == 230,132 ]]"
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1080, "height": 1920, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 950, 0]}]'
check "a reserved right edge covers x from the monitor's width minus it" "[[ \$(runs_at 'click sign in') == covered ]]"
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1080, "height": 1920, "scale": 1, "transform": 1, "x": 0, "y": 0, "reserved": [0, 0, 950, 0]}]'
check "on a rotated monitor the width is the upright one, so the same edge covers nothing here" "[[ \$(runs_at 'click sign in') == 175,82 ]]"
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]'
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Next
  word 2 1 1 160 120 96 24 95 Next
})
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true false 1
)"
out=$(route "click next")
check "one of two matches covered leaves the other, which runs without asking" "grep -q '^result:      run' <<<\"\$out\" && grep -q \"id='230,132,\" <<<\"\$out\""
SANDBOX_CLIENTS_JSON='[]'
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Sign
  word 1 1 2 136 40 24 24 95 in
})

echo "== failures and toasts"
# click_at as voxcmd would eval it, with the stubs logging instead of acting.
run_click_at() { (
  # shellcheck disable=SC2034 # read by click.sh
  voxcmd_share_dir=$share_dir target="sign in"
  # shellcheck source=/dev/null
  source "$package/.config/voxcmd/integrations.d/click.sh"
  click_at "$1"
); }
: >"$log"
run_click_at "error:no focused window"
check "a failed capture is a generic error toast" "grep -q '^notify-send --app-name=voxcmd voxcmd failed Click failed: no focused window\$' '$log'"
: >"$log"
run_click_at "covered:"
check "a covered target is a transient toast naming the spoken target" "grep -q '^notify-send --transient --app-name=voxcmd \"sign in\" is covered by another window\$' '$log'"
: >"$log"
run_click_at "175,82,right,1,2,3,4"
check "a click moves the pointer, then clicks the button" "grep -q 'hyprctl dispatch hl.dsp.cursor.move({x=175,y=82})' '$log' && grep -q '^wlrctl pointer click right\$' '$log'"
: >"$log"
run_click_at "175,82,double,1,2,3,4"
check "a double click is two left clicks" "[[ \$(grep -c '^wlrctl pointer click left\$' '$log') == 2 ]]"
mkdir -p "$root/nowlrctl"
printf '#!/bin/sh\necho "wlrctl: no seat" >&2\nexit 1\n' >"$root/nowlrctl/wlrctl"
chmod +x "$root/nowlrctl/wlrctl"
: >"$log"
PATH="$root/nowlrctl:$PATH" run_click_at "175,82,left,1,2,3,4"
check "a failed click is a generic error toast with the tool's reason" "grep -q '^notify-send --app-name=voxcmd voxcmd failed Click failed: wlrctl: no seat\$' '$log'"
check "no toast ever holds the screen text" "! grep -q -i 'sign' '$log'"
: >"$log"
out=$(PATH="$root/nowlrctl:$PATH" route "click sign in")
check "a click phrase under dry-run only routes" "! grep -q 'notify-send' '$log'"
SANDBOX_ACTIVEWINDOW_JSON='{}'
out=$(route "click sign in")
check "no focused window comes back as an error to show" "grep -q 'no focused window' <<<\"\$out\""
check "and its label is the reason, not screen text" "grep -q \"label='no focused window'\" <<<\"\$out\""
SANDBOX_ACTIVEWINDOW_JSON=$default_window
# A warning on the capture tool's stderr must not become OCR input.
mkdir -p "$root/noisy"
printf '#!/bin/sh\necho "grim: warning" >&2\nexec "%s/bin/grim" "$@"\n' "$SANDBOX_DIR" >"$root/noisy/grim"
chmod +x "$root/noisy/grim"
out=$(SANDBOX_GRIM_NO_TOPLEVEL=1 PATH="$root/noisy:$PATH" route "click sign in")
check "stderr of the capture is not mixed into the OCR data" "grep -q '^result:      run' <<<\"\$out\" && ! grep -q 'warning' <<<\"\$out\""

echo
echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
