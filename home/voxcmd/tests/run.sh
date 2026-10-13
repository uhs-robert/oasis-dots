#!/usr/bin/env bash
# Tests for voxcmd: the click matcher, mapping and OCR strips, click.sh routing, numbered-pick replies, and voice sessions
# (click mode). Run from anywhere: home/voxcmd/tests/run.sh
#
# Nothing here clicks, moves the pointer or captures the screen: it runs inside sandbox.sh, whose stubs stand in for
# grim, magick, tesseract, hyprctl, wlrctl, wl-kbptr and notify-send and log their calls, and voxcmd only ever runs
# with --dry-run, except in the session tests, which run it against the sandbox's voxtype, auto-stop and bar. All
# fixture text is made up.
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
  word 6 1 1 800 100 70 24 30 Ghost
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
# One run that holds the spoken words twice is two candidates, each with its own point and box.
repeated=$(
  window 0 0 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 90 24 95 Settings
  word 1 1 2 195 100 24 24 95 or
  word 1 1 3 224 100 90 24 95 Settings
  word 2 1 1 100 200 40 24 95 Edit
  word 2 1 2 144 200 40 24 95 Edit
  word 3 1 1 100 300 40 24 95 Sign
  word 3 1 2 144 300 20 24 95 in
  word 3 1 3 168 300 40 24 95 here
  word 3 1 4 212 300 40 24 95 sign
  word 3 1 5 256 300 20 24 95 in
  word 4 1 1 100 500 80 24 90 Newtask
  word 4 1 2 184 500 20 24 90 or
  word 4 1 3 208 500 80 24 90 Newtask
)
out=$(match "$repeated" settings)
check "'Settings or Settings' in one run is two candidates" "[[ \$(wc -l <<<\"\$out\") == 2 ]]"
check "each has its own point and box" "[[ \$(field \"\$out\" 1 | paste -sd' ') == '145 269' && \$(field \"\$out\" 5 | paste -sd' ') == '100 224' ]]"
out=$(match "$repeated" edit)
check "adjacent 'Edit Edit' is two candidates" "[[ \$(wc -l <<<\"\$out\") == 2 ]]"
out=$(match "$repeated" "sign in")
check "a multi-word target twice in one run is two candidates" "[[ \$(wc -l <<<\"\$out\") == 2 && \$(field \"\$out\" 5 | paste -sd' ') == '100 212' ]]"
out=$(match "$repeated" "new task")
check "a joined span twice in one run is two candidates" "[[ \$(wc -l <<<\"\$out\") == 2 && \$(field \"\$out\" 5 | paste -sd' ') == '100 208' ]]"
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

echo "== doubtful words"
# White text on a blue button reads at 45-55. A word that equals a spoken one is safe at that confidence, because a near
# miss no longer stands in for the spoken word; any other use of it keeps the floor of 60.
doubtful=$(
  window 0 0 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 80 24 55 Newtask
  word 2 1 1 100 200 80 24 45 Newtaxk
  word 3 1 1 100 300 80 24 30 Cancel
  word 4 1 1 100 400 60 24 45 Read
  word 4 1 2 166 400 30 24 45 me
  word 5 1 1 100 500 60 24 45 lone
  word 5 1 2 166 500 60 24 90 Clone
)
out=$(match "$doubtful" "new task")
check "conf 55 'Newtask' matches 'new task' as the spoken words" "[[ \$(wc -l <<<\"\$out\") == 1 && \$(field \"\$out\" 3) == 'new task' ]]"
out=$(match "$doubtful" "new taxk")
check "a conf 45 word that equals a spoken word is taken" "[[ \$(field \"\$out\" 2) == 212 ]]"
near_miss=$(
  window 0 0 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 80 24 45 Newtaxk
)
out=$(match "$near_miss" "new task")
check "a conf 45 word that is only a near miss does not match" "[[ -z \$out ]]"
out=$(match "$doubtful" "cancel")
check "conf 30 never matches" "[[ -z \$out ]]"
out=$(match "$doubtful" "readme")
check "doubtful words joined to the spoken letters match" "[[ \$(field \"\$out\" 3) == readme ]]"
out=$(match "$doubtful" "close")
check "a doubtful word does not join a match it is not part of" "[[ \$(field \"\$out\" 3) == clone ]]"
check "a doubtful word beside a match is left out of its text" "[[ \$(field \"\$out\" 3) == clone ]]"

echo "== sub-spans"
# Tesseract reads a sentence as one run, so a link inside it is only part of the run. CLICK_SPANS=1 searches the runs for
# stretches that equal the spoken words.
spans() { CLICK_SPANS=1 CLICK_TARGET="$2" awk -f "$matcher" <<<"$1"; }
sentence=$(
  window 0 0 1000 600 1000 600
  strip 0 0 0 600
  header
  word 1 1 1 100 100 20 20 95 2
  word 1 1 2 125 100 60 20 95 tasks
  word 1 1 3 190 100 40 20 95 are
  word 1 1 4 235 100 80 20 95 flagged
  word 1 1 5 320 100 70 20 95 TODO.
  word 2 1 1 100 300 60 20 95 Kindly
  word 2 1 2 165 300 40 20 95 sign
  word 2 1 3 210 300 20 20 95 in
  word 2 1 4 235 300 60 20 95 here.
  word 3 1 1 100 400 60 20 95 Never
  word 3 1 2 165 400 40 20 95 sign
  word 3 1 3 210 400 20 20 95 in
  word 3 1 4 235 400 60 20 95 again
  word 3 1 5 300 400 20 20 95 or
  word 3 1 6 325 400 50 20 95 sign
  word 3 1 7 380 400 20 20 95 in
)
out=$(spans "$sentence" "2 tasks")
check "'2 tasks' in its sentence is one sub-span of the spoken words" "[[ \$(wc -l <<<\"\$out\") == 1 && \$(field \"\$out\" 3) == '2 tasks' ]]"
check "its point and box are the sub-span's, not the sentence's" "[[ \$(field \"\$out\" 1),\$(field \"\$out\" 2) == 143,110 && \$(field \"\$out\" 5),\$(field \"\$out\" 7) == 100,85 ]]"
check "its label is still the sentence, for the picker" "[[ \$(field \"\$out\" 4) == '2 tasks are flagged TODO. - top left' ]]"
out=$(spans "$sentence" "sign in")
check "each occurrence of the words is a sub-span, in any run" "[[ \$(wc -l <<<\"\$out\") == 3 ]]"
out=$(spans "$sentence" "tasks 2")
check "words in another order are not a sub-span" "[[ -z \$out ]]"
out=$(spans "$sentence" "tasks flagged")
check "words with others between them are not a sub-span" "[[ -z \$out ]]"

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
# One strip fails at once; the rest would sleep for a minute, and the run must not wait for them. Each stub logs its
# pid (kept across exec) so the check looks at this run's stubs only, not at any process that happens to sleep.
printf '#!/bin/sh\necho $$ >>"%s/strip_pids"\n[ ! -e "%s/slow_started" ] && : >"%s/slow_started" && exit 1\nexec sleep 60\n' \
  "$root" "$root" "$root" >"$root/failing/tesseract"
started=$SECONDS
SANDBOX_GRIM_SCALE=1 PATH="$root/failing:$PATH" "$share_dir/click-ocr" >/dev/null 2>&1
# A killed stub is gone once its signal is delivered and it is reaped, which a loaded machine can take a moment to do,
# so it gets a generous while; a stub that was missed sleeps on for the whole minute.
strip_running() { [[ -e /proc/$1 && $(awk '{print $3}' "/proc/$1/stat" 2>/dev/null) != Z ]]; }
strips_left_running() {
  local deadline=$((SECONDS + 10)) pid running
  while ((SECONDS < deadline)); do
    running=0
    while read -r pid; do strip_running "$pid" && running=1; done <"$root/strip_pids"
    ((running)) || return 1
    sleep 0.1
  done
  return 0
}
check "a failed strip ends the others instead of waiting for them" "[[ \$((SECONDS - started)) -lt 10 ]] && ! strips_left_running"
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

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 80 24 55 Newtask
})
out=$(route "click new task")
check "a conf 55 'Newtask' still runs as a strong match" "grep -q '^result:      run' <<<\"\$out\""

# A link inside a sentence: the whole-run candidates are all dropped, so the sub-span is the match.
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 12 24 95 2
  word 1 1 2 96 40 40 24 95 tasks
  word 1 1 3 140 40 30 24 95 are
  word 1 1 4 174 40 60 24 95 flagged
  word 1 1 5 238 40 40 24 95 TODO.
})
out=$(route "click 2 tasks")
check "'2 tasks' in a sentence runs and clicks the sub-span's centre" "grep -q '^result:      run' <<<\"\$out\" && grep -q \"id='168,82,left,\" <<<\"\$out\""
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 90 24 95 Settings
  word 1 1 2 175 40 24 24 95 or
  word 1 1 3 204 40 90 24 95 Settings
})
out=$(route "click settings")
check "one run saying 'Settings or Settings' asks with the picker instead of clicking" "grep -q 'ask with the picker (2 options' <<<\"\$out\""
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 60 24 95 Tasks
  word 2 1 1 80 80 12 24 95 2
  word 2 1 2 96 80 40 24 95 tasks
  word 2 1 3 140 80 30 24 95 are
  word 2 1 4 174 80 60 24 95 flagged
})
out=$(route "click tasks")
check "a heading that matches whole beats a sentence holding the word" "grep -q '^result:      run' <<<\"\$out\" && grep -q \"id='[0-9]*,82,left\" <<<\"\$out\""
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 40 24 95 Kindly
  word 1 1 2 124 40 30 24 95 sign
  word 1 1 3 158 40 20 24 95 in
  word 1 1 4 182 40 40 24 95 today
  word 2 1 1 80 100 40 24 95 Never
  word 2 1 2 124 100 30 24 95 sign
  word 2 1 3 158 100 20 24 95 in
  word 2 1 4 182 100 40 24 95 again
})
out=$(route "click sign in")
check "the same words in two sentences are two candidates, so the picker asks" "grep -q 'ask with the picker (2 options' <<<\"\$out\""

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 160 120 96 24 95 Settings
})
out=$(route "triple click on settings")
check "triple click, with the filler 'on'" "grep -q \"action=triple_click .*,triple$box'\" <<<\"\$out\" && grep -q 'silent: true' <<<\"\$out\""
out=$(route "triple click")
check "bare 'triple click' needs a target and is not the Click integration's" "! grep -q 'Click (click.sh)' <<<\"\$out\""

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
# A route reads the window, which records it for click_at.
route "click sign in" >/dev/null
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
: >"$log"
run_click_at "175,82,triple,1,2,3,4"
check "a triple click is three left clicks" "[[ \$(grep -c '^wlrctl pointer click left\$' '$log') == 3 ]]"
mkdir -p "$root/nowlrctl"
printf '#!/bin/sh\necho "wlrctl: no seat" >&2\nexit 1\n' >"$root/nowlrctl/wlrctl"
chmod +x "$root/nowlrctl/wlrctl"
: >"$log"
PATH="$root/nowlrctl:$PATH" run_click_at "175,82,left,1,2,3,4"
check "a failed click is a generic error toast with the tool's reason" "grep -q '^notify-send --app-name=voxcmd voxcmd failed Click failed: wlrctl: no seat\$' '$log'"
check "no toast ever holds the screen text" "! grep -q -i 'sign' '$log'"

echo "== the window changed before the click"
target_file=$XDG_RUNTIME_DIR/voxcmd/click-target
window_changed_toast='^notify-send --transient --app-name=voxcmd The window changed; say it again$'
# click_at "175,82,left,..." with the focused window $1, logging what it did.
click_in_window() {
  : >"$log"
  SANDBOX_ACTIVEWINDOW_JSON=$1 run_click_at "175,82,left,1,2,3,4"
}
route "click sign in" >/dev/null
check "a route records the captured window" "jq -e '.window.address == \"0x2001\"' '$target_file' >/dev/null"
check "the record is private" "[[ \$(stat -c %a \"\$XDG_RUNTIME_DIR/voxcmd\") == 700 ]]"
click_in_window "$default_window"
check "the same window clicks" "grep -q '^wlrctl pointer click left\$' '$log' && ! grep -q 'window changed' '$log'"
click_in_window "$(jq -c '.address = "0x3001" | .stableId = "18000009"' <<<"$default_window")"
check "another window focused does not click, and says so" "grep -q '$window_changed_toast' '$log' && ! grep -q -e cursor.move -e wlrctl '$log'"
click_in_window "$(jq -c '.at = [300, 50]' <<<"$default_window")"
check "the window moved does not click" "grep -q '$window_changed_toast' '$log' && ! grep -q -e cursor.move -e wlrctl '$log'"
click_in_window "$(jq -c '.size = [400, 96]' <<<"$default_window")"
check "the window resized does not click" "grep -q '$window_changed_toast' '$log' && ! grep -q -e cursor.move -e wlrctl '$log'"
click_in_window '{}'
check "no focused window does not click" "grep -q '$window_changed_toast' '$log' && ! grep -q wlrctl '$log'"
jq -c '.captured_at -= 61' "$target_file" >"$target_file.old" && mv "$target_file.old" "$target_file"
click_in_window "$default_window"
check "a record older than a minute does not click" "grep -q '$window_changed_toast' '$log' && ! grep -q wlrctl '$log'"
rm -f "$target_file"
click_in_window "$default_window"
check "no record does not click" "grep -q '$window_changed_toast' '$log' && ! grep -q wlrctl '$log'"
route "click sign in" >/dev/null
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

# ---- numbered on-screen picks: the integration hook, voxcmd-hints and its replies ---------------------------------------
# A copy of the package whose voxcmd-pick and voxcmd-autostop are the sandbox's stubs, so nothing asks a real picker or
# records audio; voxcmd-hints is the real one and finds the stub voxcmd-pick beside itself.

echo "== numbered picks"
pkg=$root/pkg
mkdir -p "$pkg"
cp -r "$package/.local" "$pkg/.local"
ln -sf "$SANDBOX_DIR/bin/voxcmd-pick" "$pkg/.local/bin/voxcmd-pick"
ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$pkg/.local/bin/voxcmd-autostop"
pkg_voxcmd=$pkg/.local/bin/voxcmd
action_log=$root/actions.log
fake_pick=$root/fake-pick
# shellcheck disable=SC2016 # the stub expands its own arguments
printf '#!/bin/sh\necho "fake-pick $*" >> "%s"\necho 1\n' "$log" >"$fake_pick"
chmod +x "$fake_pick"

# new_config <name> <extra integration lines>: a config dir holding one integration whose two candidates have boxes in
# their ids.
new_config() {
  local dir=$root/config-$1
  mkdir -p "$dir/integrations.d" "$dir/replacements.d"
  cat >"$dir/integrations.d/hinted.sh" <<STUB
name="Hinted"
verbs=("tap tap {target}")
candidates() {
  jq -n -c '[{id: "1,2,left,100,50,60,20", label: "Next - top"}, {id: "3,4,left,300,200,70,22", label: "Next - bottom"}]'
}
declare -A actions=([tap]='echo "\$id" >> "$action_log"')
pick_command=$fake_pick
$2
STUB
  echo "$dir"
}
# shellcheck disable=SC2016 # integration source, expanded when the integration runs
box_function='pick_box() { IFS=, read -r _ _ _ left top width height <<<"$1"; [ -n "${height:-}" ] || return 1; echo "$left $top $width $height"; }'

: >"$log"
: >"$action_log"
export VOXCMD_CONFIG_DIR
VOXCMD_CONFIG_DIR=$(new_config boxed "$box_function")
"$pkg_voxcmd" tap next >/dev/null 2>&1
check "several matches ask the integration's pick command" "grep -q '^fake-pick Which one? ' '$log' && ! grep -q 'voxcmd-pick' '$log'"
check "its choices carry each option's box" "grep -q '\"box\":\[100,50,60,20\]' '$log' && grep -q '\"box\":\[300,200,70,22\]' '$log'"
check "a typed command does not listen" "! grep -q 'fake-pick --listen' '$log'"
check "the pick's answer runs that option" "[[ \$(cat '$action_log') == '3,4,left,300,200,70,22' ]]"

VOXCMD_CONFIG_DIR=$(new_config unboxed 'pick_box() { return 1; }')
: >"$log"
"$pkg_voxcmd" tap next >/dev/null 2>&1
check "an option without a box falls back to the text picker" "grep -q '^voxcmd-pick Which command?' '$log' && ! grep -q fake-pick '$log'"
# shellcheck disable=SC2016 # integration source, expanded when the integration runs
VOXCMD_CONFIG_DIR=$(new_config garbled 'pick_box() { case "$1" in 3,*) echo "not a box" ;; *) echo "1 2 3 4" ;; esac; }')
: >"$log"
"$pkg_voxcmd" tap next >/dev/null 2>&1
check "a pick_box that prints garbage for one option falls back to the text picker" "grep -q '^voxcmd-pick Which command?' '$log' && ! grep -q fake-pick '$log'"
VOXCMD_CONFIG_DIR=$(new_config nofunction "")
: >"$log"
"$pkg_voxcmd" tap next >/dev/null 2>&1
check "pick_command without pick_box falls back too" "grep -q '^voxcmd-pick ' '$log' && ! grep -q fake-pick '$log'"

# A spoken command: _watch routes the transcript voxtype wrote, as `voxcmd listen` leaves it to do.
VOXCMD_CONFIG_DIR=$(new_config boxed2 "$box_function")
: >"$log"
mkdir -p "$XDG_RUNTIME_DIR/voxtype" "$XDG_RUNTIME_DIR/voxcmd"
echo recording >"$XDG_RUNTIME_DIR/voxtype/state"
echo "tap next" >"$XDG_RUNTIME_DIR/voxcmd/transcript.txt"
(
  sleep 0.5
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
) &
"$pkg_voxcmd" _watch route >/dev/null 2>&1
wait
check "a spoken command passes --listen to the pick command" "grep -q '^fake-pick --listen Which one? ' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxtype/state"

# voxcmd-hints: the sandbox's qs-ipc logs the pending state as it is when the overlay opens, then answers through the
# result FIFO as the bar would, with SANDBOX_CLICKHINTS_ANSWER: a number, a label or nothing.
hints=$pkg/.local/bin/voxcmd-hints
hint_choices='[{"id":"a","label":"Next - top","box":[100,50,60,20]},{"id":"b","label":"Next - bottom","box":[300,200,70,22]}]'
run_hints() { "$hints" "$@"; }
export SANDBOX_CLICKHINTS_ANSWER=

: >"$log"
out=$(SANDBOX_CLICKHINTS_ANSWER=2 run_hints "Which one?" "$hint_choices")
check "a number from the overlay prints that choice's id" "[[ $out == b ]]"
check "the overlay's spec has global boxes and numbered labels" "grep -q '\"x\":300,\"y\":200,\"w\":70,\"h\":22' '$log' && grep -q '2. Next - bottom' '$log'"
check "the pending state is written, with kind hints, before the overlay opens" "grep -q '\"pending_kind\":{\"pid\":[0-9]*,\"fifo\":\"[^\"]*\",\"label\":\"Which one?\",\"kind\":\"hints\"' '$log'"
check "the pending state is removed afterwards" "[[ ! -e '$XDG_RUNTIME_DIR/voxcmd/pending-pick.json' ]]"
check "the overlay is dismissed afterwards" "grep -q 'qs-ipc call clickhints dismiss' '$log'"
out=$(SANDBOX_CLICKHINTS_ANSWER="1. Next - top" run_hints "Which one?" "$hint_choices")
check "a voice reply's label prints that choice's id" "[[ $out == a ]]"
check "an empty answer is a cancel" "! run_hints 'Which one?' '$hint_choices' >/dev/null"
check "a number past the choices is a cancel" "! SANDBOX_CLICKHINTS_ANSWER=7 run_hints 'Which one?' '$hint_choices' >/dev/null"
check "an answer of 0 is a cancel, not the last choice" "! SANDBOX_CLICKHINTS_ANSWER=0 run_hints 'Which one?' '$hint_choices' >/dev/null"
: >"$log"
out=$(SANDBOX_CLICKHINTS_OPEN=invalid run_hints "Which one?" "$hint_choices")
check "a bar that refuses the overlay hands the pick to the text picker" "grep -q '^voxcmd-pick Which one? \[{\"id\":\"a\",\"label\":\"Next - top\"}' '$log' && [[ $out == a ]]"
: >"$log"
out=$(run_hints "Which one?" '[{"id":"a","label":"Next - top"}]')
check "a choice without a box skips the overlay" "! grep -q clickhints '$log' && grep -q '^voxcmd-pick ' '$log' && [[ $out == a ]]"
many=$(jq -n -c '[range(0; 12) | {id: tostring, label: "Item \(.)", box: [. * 10, 0, 8, 8]}]')
: >"$log"
out=$(SANDBOX_CLICKHINTS_ANSWER=10 run_hints "Which one?" "$many")
check "more than ten choices fall back to the text picker, which lists them all" "! grep -q clickhints '$log' && grep -q '\"label\":\"Item 11\"' '$log' && [[ \$out == 0 ]]"

# A signal or a silent bar ends the pick with the overlay still up, so it is dismissed on the way out.
: >"$log"
SANDBOX_CLICKHINTS_HOLD=1 "$hints" "Which one?" "$hint_choices" >/dev/null &
waiter_pid=$!
for _ in $(seq 100); do
  grep -q 'clickhints open' "$log" && break
  sleep 0.05
done
kill -TERM "$waiter_pid"
wait "$waiter_pid" && waiter_status=0 || waiter_status=$?
check "TERM exits 1 and dismisses the overlay" "[[ $waiter_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log'"
: >"$log"
start=$SECONDS
SANDBOX_CLICKHINTS_HOLD=1 VOXCMD_HINTS_TIMEOUT=1 run_hints "Which one?" "$hint_choices" >/dev/null && timeout_status=0 || timeout_status=$?
check "a reader timeout exits 1 and dismisses the overlay" "[[ $timeout_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log' && [[ $((SECONDS - start)) -lt 5 ]]"

# --listen: the reply recording starts through voxcmd listen --start-only before the overlay opens.
: >"$log"
mkdir -p "$XDG_RUNTIME_DIR/voxtype"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
SANDBOX_CLICKHINTS_ANSWER=1 run_hints --listen "Which one?" "$hint_choices" >/dev/null
check "--listen starts the reply recording before the overlay opens" "[[ \$(grep -n 'voxtype record start' '$log' | head -1 | cut -d: -f1) -lt \$(grep -n 'clickhints open' '$log' | head -1 | cut -d: -f1) ]]"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
SANDBOX_CLICKHINTS_HOLD=1 "$hints" --listen "Which one?" "$hint_choices" >/dev/null &
waiter_pid=$!
for _ in $(seq 100); do
  grep -q 'clickhints open' "$log" && break
  sleep 0.05
done
check "--listen hands the watcher the pick's recording owner file" "grep -Eq '^setsid owner=.*/voxcmd-hints\\.[^/]+/recording-owner ' '$log'"
kill -TERM "$waiter_pid"
wait "$waiter_pid" || true
rm -f "$XDG_RUNTIME_DIR/voxtype/state"

# Replies: the pending state of a waiting hints picker, owned by a process whose command line names voxcmd-hints.
waiter=$root/voxcmd-hints
cp /bin/sleep "$waiter"
"$waiter" 60 &
waiter_pid=$!
reply_fifo=$root/reply-fifo
mkfifo "$reply_fifo"
listen_again=$root/listen-again
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$reply_fifo" --arg listen_again "$listen_again" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, listen_again: $listen_again,
    choices: [{id: "a", label: "1. Next - top"}, {id: "b", label: "2. Next - bottom"}, {id: "c", label: "3. Settings - middle"}]}' \
  >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
reply_dry() { "$voxcmd" --dry-run --reply "$1" 2>&1; }
check "a waiting voxcmd-hints is a pending pick that a reply finds" "grep -q 'picker:      Which one?' <<<\"\$(reply_dry two)\""
check "an ordinal picks by number" "grep -q 'result:      pick: 2. Next - bottom' <<<\"\$(reply_dry 'the second one')\""
check "a spoken number picks by number" "grep -q 'result:      pick: 3. ' <<<\"\$(reply_dry 3)\""
check "label words pick" "grep -q 'result:      pick: 3. Settings - middle' <<<\"\$(reply_dry settings)\""
check "a number past the choices is unclear" "grep -q 'unclear: there are only 3 choices' <<<\"\$(reply_dry 'number 8')\""
check "cancel cancels" "grep -q 'result:      cancel' <<<\"\$(reply_dry 'never mind')\""

: >"$log"
touch "$listen_again"
"$pkg_voxcmd" --reply "banana" >/dev/null 2>&1
check "an unclear reply listens once more" "[[ ! -e '$listen_again' ]] && grep -q 'voxtype record start' '$log'"
: >"$log"
"$pkg_voxcmd" --reply "banana" >/dev/null 2>&1
check "and only once" "! grep -q 'voxtype record start' '$log'"
# The answer goes into the FIFO as the displayed label.
(timeout 5 head -n 1 "$reply_fifo" >"$root/reply-answer") &
reader=$!
"$pkg_voxcmd" --reply "two" >/dev/null 2>&1
wait "$reader"
check "a reply writes the displayed label to the FIFO" "[[ \$(cat '$root/reply-answer') == '2. Next - bottom' ]]"
kill "$waiter_pid" 2>/dev/null
wait "$waiter_pid" 2>/dev/null
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"

# click.sh's own pick_box, on the id format of its candidates.
click_box() (
  # shellcheck disable=SC2034 # read by click.sh
  voxcmd_share_dir=$share_dir
  # shellcheck disable=SC1091
  source "$package/.config/voxcmd/integrations.d/click.sh"
  pick_box "$1"
)
check "click.sh places an option from its id" "[[ \$(click_box '150,75,left,100,50,60,20') == '100 50 60 20' ]]"
check "click.sh has no box for an id without one" "! click_box '150,75,left' >/dev/null"
check "click.sh asks voxcmd-hints" "grep -q '^pick_command=voxcmd-hints' '$package/.config/voxcmd/integrations.d/click.sh'"

# ---- narrowing replies by box position ------------------------------------------------------------------------------

echo "== direction replies"
waiter=$root/voxcmd-hints
"$waiter" 60 &
waiter_pid=$!
# Four boxes: two on the top row (the right one a few pixels lower), one lower left, one far lower right.
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$reply_fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {},
    choices: [{id: "a", label: "1. Next - top left", box: [100, 50, 60, 20]}, {id: "b", label: "2. Next - top right", box: [300, 53, 70, 20]},
      {id: "c", label: "3. Next - bottom left", box: [100, 300, 80, 20]}, {id: "d", label: "4. Next - bottom right", box: [500, 400, 80, 20]}]}' \
  >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
check "'the top one' takes the topmost, and the left of a tie" "grep -q 'result:      pick: 1. ' <<<\"\$(reply_dry 'the top one')\""
check "'top' alone is the same, though every label says 'top'" "grep -q 'result:      pick: 1. ' <<<\"\$(reply_dry top)\""
check "'the bottom one' takes the lowest edge" "grep -q 'result:      pick: 4. ' <<<\"\$(reply_dry 'the bottom one')\""
check "'the left one' takes the leftmost edge, the topmost of a tie" "grep -q 'result:      pick: 1. ' <<<\"\$(reply_dry 'the left one')\""
check "'the right one' takes the rightmost edge" "grep -q 'result:      pick: 4. ' <<<\"\$(reply_dry 'the right one')\""
check "'rightmost' and 'lower' are directions too" "grep -q 'pick: 4. ' <<<\"\$(reply_dry rightmost)\" && grep -q 'pick: 4. ' <<<\"\$(reply_dry lower)\""
check "'the first one' and 'the last one' are still the numbers" "grep -q 'pick: 1. ' <<<\"\$(reply_dry 'the first one')\" && grep -q 'pick: 4. ' <<<\"\$(reply_dry 'the last one')\""
jq -c '.choices |= map(del(.box))' "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json" >"$root/nobox.json"
mv "$root/nobox.json" "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
check "boxless choices cannot be told apart by direction" "grep -q 'result:      unclear' <<<\"\$(reply_dry 'the right one')\""
kill "$waiter_pid" 2>/dev/null
wait "$waiter_pid" 2>/dev/null
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"

# ---- click mode phrases ---------------------------------------------------------------------------------------------

echo "== click mode routing"
all_config=$root/config-all
mkdir -p "$all_config/integrations.d" "$all_config/replacements.d"
find "$package/.config/voxcmd/integrations.d" -maxdepth 1 -type f -name '*.sh' -exec cp -t "$all_config/integrations.d/" {} +
route_all() { VOXCMD_CONFIG_DIR=$all_config "$voxcmd" --dry-run "$1" 2>&1; }
for phrase in "click mode" "start clicking" "clicking mode" "enter click mode"; do
  out=$(route_all "$phrase")
  check "'$phrase' opens click mode, alone" "grep -q 'result:      run' <<<\"\$out\" && grep -q 'Click (click.sh) action=click_mode' <<<\"\$out\" && [[ \$(grep -c '^option' <<<\"\$out\") == 1 ]]"
done
out=$(route_all "stop clicking")
check "'stop clicking' ends click mode instead of pausing media" "grep -q 'Click (click.sh) action=stop_clicking' <<<\"\$out\" && [[ \$(grep -c '^option' <<<\"\$out\") == 1 ]]"
out=$(route_all "click mode on")
check "'click' followed by other text is still a click on that text" "! grep -q 'action=click_mode' <<<\"\$out\""
# Every example that needs no screen text still goes where it did: nothing but Click's own examples reaches its mode verbs.
stray=""
while IFS= read -r phrase; do
  out=$(route_all "$phrase")
  if grep -q 'action=\(click_mode\|stop_clicking\)' <<<"$out"; then stray+="$phrase; "; fi
done < <(grep -h -o '^  "[^"<]*"$' "$all_config"/integrations.d/*.sh | tr -d '"' | sed 's/^ *//' | grep -v -e 'click mode' -e 'stop clicking' -e '^click_mode' -e '^stop_clicking' | sort -u)
check "no other example routes to click mode ($stray)" "[[ -z '$stray' ]]"

session_rewrite_of() (
  # shellcheck disable=SC2034 # read by click.sh
  voxcmd_share_dir=$share_dir
  # shellcheck disable=SC1091
  source "$package/.config/voxcmd/integrations.d/click.sh"
  session_rewrite "$1"
)
check "a bare target becomes a click" "[[ \$(session_rewrite_of 'sign in') == 'click sign in' ]]"
check "a click phrase is routed as spoken" "[[ \$(session_rewrite_of 'right click settings') == 'right click settings' && \$(session_rewrite_of 'double click on readme') == 'double click on readme' ]]"
check "a bare click names no target" "[[ -z \$(session_rewrite_of 'right click') && -z \$(session_rewrite_of click) ]]"
check "the entry phrases are not read as targets" "[[ \$(session_rewrite_of 'clicking mode') == 'clicking mode' && \$(session_rewrite_of 'click mode') == 'click mode' ]]"
# ---- voice sessions ---------------------------------------------------------------------------------------------------
# A copy of the package whose voxcmd-autostop is the sandbox's stub, with the sandbox's setsid really starting the
# watcher and its voxtype "hearing" the next line of $SANDBOX_VOXTYPE_TURNS ("SILENCE" and an empty queue are no
# speech, "EMPTY" is speech that transcribes to nothing, "HOLD" keeps recording until stopped or cancelled, "FAIL" is a
# record start that fails). Every run ends when no watcher is left, which is what proves the microphone stops
# re-opening.

echo "== voice sessions"
sess_stubs=$root/sess-stubs
sess_pkg=$root/sess-pkg
mkdir -p "$sess_stubs" "$sess_pkg"
cp -r "$package/.local" "$sess_pkg/.local"
ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$sess_pkg/.local/bin/voxcmd-autostop"
sess_voxcmd=$sess_pkg/.local/bin/voxcmd
# The stub detector's long sleep, under its own name so the tests can end the ones a killed watcher leaves behind.
stub_sleep=$root/stub-sleep
cp "$(command -v sleep)" "$stub_sleep"
trap 'pkill -f "$stub_sleep" 2>/dev/null; rm -rf "$root"' EXIT
sess_turns=$root/turns
# The numbered overlay: answers with the next line of $STUB_PICKS, a choice's index or CANCEL.
export STUB_PICKS=$root/picks
cat >"$sess_stubs/sess-hints" <<STUB
#!/bin/sh
echo "pick no_speech_secs=\${VOXCMD_AUTOSTOP_NO_SPEECH_SECS:-default}" >> "$log"
echo "pick min_speech_secs=\${VOXCMD_AUTOSTOP_MIN_SPEECH_SECS:-default} silence_secs=\${VOXCMD_AUTOSTOP_SILENCE_SECS:-default}" >> "$log"
answer=\$(head -n 1 "\$STUB_PICKS"); sed -i 1d "\$STUB_PICKS"
[ "\$answer" != CANCEL ] || exit 1
echo "\$answer"
STUB
chmod +x "$sess_stubs/sess-hints"
hints_state=$SANDBOX_DIR/clickhints-state popup_state_file=$SANDBOX_DIR/popup-state

# "both" is two targets, which the overlay asks about.
sess_config=$root/config-sess
mkdir -p "$sess_config/integrations.d" "$sess_config/replacements.d"
cat >"$sess_config/integrations.d/sess.sh" <<STUB
name="Sess"
verbs=("begin_it start testing" "stop_it stop testing" "tap tap {target}")
session_miss_actions=(none)
pick_command=$sess_stubs/sess-hints
candidates() {
  case "\$2" in
  missing) echo '[{"id": "zz", "label": "zz"}]' ;;
  both) echo '[{"id": "both left", "label": "both left"}, {"id": "both right", "label": "both right"}]' ;;
  *) jq -n -c --arg t "\$2" '[{id: \$t, label: \$t}]' ;;
  esac
}
pick_box() { echo "0 0 10 10"; }
declare -A no_match_actions=([tap]=none)
declare -A actions=(
  [begin_it]='session_begin test "\$file" "Test mode"'
  [stop_it]='session_end done'
  [tap]='echo "tap \$id" >> "$log"'
  [none]='echo "tap nothing" >> "$log"'
)
session_rewrite() {
  [ "\$1" != noise ] || return 0
  printf 'tap %s' "\$1"
}
STUB

sess_voxcmd_env() {
  env SANDBOX_SETSID_RUN=1 SANDBOX_VOXTYPE_TURNS="$sess_turns" SANDBOX_AUTOSTOP_SLEEP="$stub_sleep" \
    VOXCMD_CONFIG_DIR="$sess_config" VOXCMD_APP_SETTLE_SECS=0.05 \
    "${sess_env[@]}" "$sess_voxcmd" "$@" >/dev/null 2>&1
}
# sess_start <turn>...: types "start testing" with these turns queued. $sess_env adds environment, $sess_overlay is
# what the overlay reports from the start.
sess_env=()
sess_overlay=""
sess_start() {
  printf '%s\n' "$@" >"$sess_turns"
  : >"$log"
  rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json" "$hints_state" "$popup_state_file"
  [ -z "$sess_overlay" ] || echo "$sess_overlay" >"$hints_state"
  mkdir -p "$XDG_RUNTIME_DIR/voxtype" "$XDG_RUNTIME_DIR/voxcmd"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  sess_voxcmd_env start testing
}
# Waits for every watcher to finish; fails when one is alive after 20s, which would be a microphone that never closes.
# A watcher handing over to its successor shows no command line for an instant while the successor execs, so absence has
# to hold for a few polls in a row.
sess_wait() {
  local waited absent=0
  for ((waited = 0; waited < 200; waited++)); do
    if pgrep -f "$sess_voxcmd _watch" >/dev/null; then absent=0; else absent=$((absent + 1)); fi
    [ "$absent" -lt 4 ] || return 0
    sleep 0.1
  done
  return 1
}
sess_run() {
  sess_start "$@"
  sess_wait
}
# log_has_soon <pattern> [tenths]: the watcher starts in the background, so its log lines can land after listen has
# returned.
log_has_soon() {
  local waited
  for ((waited = 0; waited < ${2:-20}; waited++)); do
    grep -q "$1" "$log" && return 0
    sleep 0.1
  done
  return 1
}
taps() { grep -c '^tap ' "$log"; }
record_starts() { grep -c '^voxtype record start' "$log"; }
session_gone() { [[ ! -e $XDG_RUNTIME_DIR/voxcmd/session.json ]]; }
ended_because() { grep -q "^notify-send .*Test mode ended $1" "$log"; }
start_time_of() { sed 's/.*) //' "/proc/$1/stat" | awk '{print $20}'; }
# Waits until the session's owner is a watcher that is recording.
owner_is_recording() {
  local waited owner
  for ((waited = 0; waited < 50; waited++)); do
    owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json" 2>/dev/null)
    if [ -n "$owner" ] && grep -qs _watch "/proc/$owner/cmdline" && [[ $(cat "$XDG_RUNTIME_DIR/voxtype/state") == recording ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

sess_run alpha beta "done"
check "targets are tapped in turn" "[[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
check "it listens once more after each turn, and not after 'done'" "[[ \$(record_starts) == 3 ]]"
check "an exit word clears the session and leaves the microphone idle" "session_gone && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle ]]"
check "session listens allow 10s of silence" "[[ \$(grep -c 'autostop no_speech_secs=10\$' '$log') == 3 ]]"
check "no session listen asks for the default" "! grep -q 'no_speech_secs=default' '$log'"

sess_env=(VOXCMD_AUTOSTOP_NO_SPEECH_SECS=4)
sess_run alpha "done"
check "the session's allowance wins over a user's auto-stop setting" "[[ \$(grep -c 'autostop no_speech_secs=10\$' '$log') == 2 ]]"
sess_env=(VOXCMD_SESSION_NO_SPEECH_SECS=7)
sess_run alpha "done"
check "VOXCMD_SESSION_NO_SPEECH_SECS sets it" "[[ \$(grep -c 'autostop no_speech_secs=7\$' '$log') == 2 ]]"
sess_env=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1 VOXCMD_AUTOSTOP_SILENCE_SECS=0.5)
sess_run alpha "done"
check "session listens want 0.4s of speech and a 1.5s pause, whatever auto-stop's settings" "[[ \$(grep -c 'autostop min_speech_secs=0.4 silence_secs=1.5\$' '$log') == 2 ]]"
sess_env=(VOXCMD_SESSION_MIN_SPEECH_SECS=0.8 VOXCMD_SESSION_SILENCE_SECS=2)
sess_run alpha "done"
check "VOXCMD_SESSION_MIN_SPEECH_SECS and VOXCMD_SESSION_SILENCE_SECS set them" "[[ \$(grep -c 'autostop min_speech_secs=0.8 silence_secs=2\$' '$log') == 2 ]]"
sess_env=()

# While it is open, the session file names its kind and a live owner.
sess_start alpha "done"
check "an open session records its kind, label and a live owner" "[[ \$(jq -r '[.kind, .label, (.owner | tostring | test(\"^[0-9]+\$\"))] | join(\",\")' '$XDG_RUNTIME_DIR/voxcmd/session.json') == 'test,Test mode,true' ]]"
sess_wait

for word in "done" "Done." "stop clicking" "exit click mode" "that's all" "I'm done" "done clicking"; do
  sess_run alpha "$word" gamma
  check "'$word' ends the session and the microphone with it" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
# Button labels: these are what the user wants clicked.
for word in "cancel" "exit" "stop" "never mind"; do
  sess_run "$word" "done"
  check "'$word' is a target, not an exit" "[[ \$(grep '^tap ' '$log') == 'tap $word' && \$(record_starts) == 2 ]]"
done

sess_run alpha
check "no speech ends the session instead of stopping silently" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]] && ended_because 'nothing was said'"
sess_run
check "no speech in the first listen ends it too" "session_gone && [[ \$(taps) == 0 && \$(record_starts) == 1 ]]"

sess_run noise noise noise alpha
check "three unusable turns in a row end it" "session_gone && [[ \$(taps) == 0 && \$(record_starts) == 3 ]] && ended_because 'nothing understood'"
sess_run missing missing missing alpha
check "three targets found nowhere end it" "session_gone && [[ \$(grep -c '^tap nothing' '$log') == 3 && \$(taps) == 3 ]]"
sess_run EMPTY EMPTY EMPTY alpha "done"
check "recordings that transcribe to nothing listen again without counting as unusable" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 5 ]] && ended_because done"
# Whisper's stock guesses at noise, as voxtype writes them.
sess_run "Thank you." "The End" "you" "..." "Thanks for watching!" "[BLANK_AUDIO]" alpha "done"
check "the transcriber's guesses at noise are not turns that missed" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap alpha' && \$(record_starts) == 8 ]] && ended_because done"
check "and are not reported as not understood" "! grep -q 'Not understood' '$log'"
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run "Thank you." "The End" "Thank you." "Thank you." alpha
check "the turn cap still ends a session that only hears noise" "session_gone && [[ \$(taps) == 0 && \$(record_starts) == 3 ]] && ended_because 'it reached 3 turns'"
sess_env=()
sess_run noise noise alpha noise noise "done"
check "a usable turn resets the count" "session_gone && [[ \$(grep -c '^tap alpha' '$log') == 1 && \$(record_starts) == 6 ]]"

# The overlay inside a session: a pick is a turn that did something, a cancel (or timeout) one that did nothing.
printf '%s\n' 0 CANCEL CANCEL CANCEL >"$STUB_PICKS"
sess_run both both both both alpha
check "an overlay pick clicks and the session carries on" "[[ \$(grep '^tap ' '$log') == 'tap both left' ]]"
check "three cancelled overlays in a row end it" "session_gone && [[ \$(record_starts) == 4 ]] && ended_because 'nothing understood'"
check "the overlay's own listen keeps auto-stop's usual allowance" "[[ \$(grep -c '^pick no_speech_secs=default\$' '$log') == 4 && \$(grep -c '^pick min_speech_secs=default silence_secs=default\$' '$log') == 4 ]]"
printf '%s\n' CANCEL CANCEL 1 >"$STUB_PICKS"
sess_run both both both noise noise "done"
check "a pick resets the count of cancelled overlays" "[[ \$(grep '^tap ' '$log') == 'tap both right' && \$(record_starts) == 6 ]] && ended_because done"

# Caps that hold even while every turn does something.
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run alpha alpha alpha alpha alpha
check "a session ends after VOXCMD_SESSION_MAX_TURNS turns" "session_gone && [[ \$(taps) == 3 && \$(record_starts) == 3 ]] && ended_because 'it reached 3 turns'"
sess_env=(VOXCMD_SESSION_MAX_SECS=0)
sess_run alpha alpha
check "and after VOXCMD_SESSION_MAX_SECS" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 1 ]] && ended_because 'it reached its time limit'"
sess_env=()
check "by default it is 40 turns or 5 minutes" "grep -q 'VOXCMD_SESSION_MAX_SECS:-300}' '$package/.local/bin/voxcmd' && grep -q 'VOXCMD_SESSION_MAX_TURNS:-40}' '$package/.local/bin/voxcmd'"

# Without auto-stop nothing would end an idle session.
export SANDBOX_AUTOSTOP_OFF="auto-stop is turned off (enabled = false)"
sess_run alpha
check "no session opens while auto-stop is off" "session_gone && [[ \$(record_starts) == 0 ]] && grep -q '^notify-send .*--transient voxcmd: Test mode needs auto-stop auto-stop is turned off' '$log'"
unset SANDBOX_AUTOSTOP_OFF
# The interpreter itself, not `command -v python3`: a pyenv shim is a bash script, which the bare PATH below cannot run.
python3_binary=$(python3 -c 'import sys; print(sys.executable)')
autostop_check() { env -i PATH="$1" VOXCMD_CONFIG_DIR="$root/autostop-config" "${@:2}" "$python3_binary" "$package/.local/bin/voxcmd-autostop" --check; }
mkdir -p "$root/autostop-config" "$root/pw-bin" "$root/no-pw-bin"
printf '#!/bin/sh\n' >"$root/pw-bin/pw-record"
chmod +x "$root/pw-bin/pw-record"
check "autostop --check passes when it can listen" "autostop_check '$root/pw-bin' >/dev/null"
check "and fails when turned off" "[[ \$(autostop_check '$root/pw-bin' VOXCMD_AUTOSTOP=false) == *'turned off'* ]] && ! autostop_check '$root/pw-bin' VOXCMD_AUTOSTOP=false >/dev/null"
check "or when pw-record is missing" "[[ \$(autostop_check '$root/no-pw-bin') == *'pw-record is not installed'* ]]"
echo "bogus = 1" >"$root/autostop-config/autostop.conf"
check "or when its config is wrong" "[[ \$(autostop_check '$root/pw-bin') == *'unknown setting: bogus'* ]]"

# The detector itself, on synthetic audio: pcm <file> <kind>:<secs>:<dBFS>..., where noise is a steady hiss (a fan)
# and voice is a syllable-paced tone over the last noise. Nothing here is recorded.
pcm() {
  python3 - "$@" <<'PY'
import math, random, struct, sys
rate, rng, samples, room_db = 16000, random.Random(7), [], -90.0
for segment in sys.argv[2:]:
    kind, secs, db = segment.split(":")
    count, amplitude = int(float(secs) * rate), 32768 * 10 ** (float(db) / 20)
    if kind == "noise":
        room_db = float(db)
        samples += [rng.gauss(0, amplitude) for _ in range(count)]
    else:
        room_amplitude = 32768 * 10 ** (room_db / 20)
        samples += [rng.gauss(0, room_amplitude) + amplitude * math.sqrt(2) * abs(math.sin(math.pi * 4 * i / rate))
                    * math.sin(2 * math.pi * 180 * i / rate) for i in range(count)]
with open(sys.argv[1], "wb") as out:
    out.write(b"".join(struct.pack("<h", max(-32768, min(32767, int(sample)))) for sample in samples))
PY
}
# detect <file> [VAR=value...]: runs the detector on it with voxcmd's debug log on, printing its exit code; the trace
# is left in $detector_trace.
detector_trace=$root/detector-run/voxcmd/debug.log
mkdir -p "$root/detector-config" "$(dirname "$detector_trace")"
detect() {
  local status=0
  : >"$detector_trace"
  env XDG_RUNTIME_DIR="$root/detector-run" VOXCMD_CONFIG_DIR="$root/detector-config" "${@:2}" \
    python3 "$package/.local/bin/voxcmd-autostop" --pcm "$1" 2>/dev/null || status=$?
  echo "$status"
}
session_detector=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.4 VOXCMD_AUTOSTOP_SILENCE_SECS=1.5 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=5)
echo "== auto-stop detector"
# A microphone's first fraction of a second, quieter than the fan the rest of the recording hears.
pcm "$root/fan-after-quiet-start.pcm" noise:0.3:-75 noise:7.7:-42
check "a steady fan after a quiet start is not speech then a pause" "[[ \$(detect '$root/fan-after-quiet-start.pcm') == 3 ]]"
check "the trace says why the fan was set aside" "grep -q '1.80s of speech is 0.00s against the room now' '$detector_trace' && grep -q 'verdict no speech' '$detector_trace'"
check "and in a session" "[[ \$(detect '$root/fan-after-quiet-start.pcm' \"\${session_detector[@]}\") == 3 ]]"
pcm "$root/word-over-fan.pcm" noise:0.3:-75 noise:2.7:-42 voice:0.9:-18 noise:4:-42
check "a word over the same fan still stops it" "[[ \$(detect '$root/word-over-fan.pcm') == 0 ]]"
check "the trace has the room, the threshold, each speech run and the verdict" "grep -q 'calibrated: room -7[0-9.]* dBFS, threshold -45.0 dBFS' '$detector_trace' && grep -q 'speech run [0-9.]*s +[0-9.]*s: mean -[0-9.]* peak -[0-9.]* threshold -[0-9.]* dBFS' '$detector_trace' && grep -q 'verdict speech then quiet at [0-9.]*s: room -4[0-9.]*, threshold -3[0-9.]* dBFS, speech [0-9.]*s' '$detector_trace'"
check "a session stops on it too" "[[ \$(detect '$root/word-over-fan.pcm' \"\${session_detector[@]}\") == 0 ]]"
# Two knocks on the desk: enough for a command, not for a session turn.
pcm "$root/knocks.pcm" noise:1:-55 voice:0.15:-25 noise:0.35:-55 voice:0.15:-25 noise:5:-55
check "two knocks then quiet stop a command" "[[ \$(detect '$root/knocks.pcm') == 0 ]] && grep -q 'verdict speech then quiet at [12]\.' '$detector_trace'"
check "a session does not stop on them, only takes them as a short word at its no-speech deadline" "[[ \$(detect '$root/knocks.pcm' \"\${session_detector[@]}\") == 0 ]] && grep -q 'a short word, stopping' '$detector_trace' && grep -q 'verdict speech then quiet at 5\.' '$detector_trace'"
# A spoken "cancel" heard as 0.15s of speech: short of a command's min_speech_secs, but still an answer.
reply_detector=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1)
pcm "$root/short-word.pcm" noise:2:-48 voice:0.15:-28 noise:6:-48
check "a short word is transcribed at the no-speech deadline, not cancelled" "[[ \$(detect '$root/short-word.pcm') == 0 ]] && grep -q 'a short word, stopping' '$detector_trace' && grep -q 'verdict speech then quiet at 6\.' '$detector_trace'"
check "a reply's lower minimum stops on the pause after it" "[[ \$(detect '$root/short-word.pcm' \"\${reply_detector[@]}\") == 0 ]] && grep -q 'verdict speech then quiet at 3\.' '$detector_trace'"
pcm "$root/word-at-deadline.pcm" noise:5.8:-48 voice:0.5:-28 noise:3:-48
check "speech under way at the deadline still waits for its pause" "[[ \$(detect '$root/word-at-deadline.pcm') == 0 ]] && grep -q 'verdict speech then quiet at 7\.' '$detector_trace'"
pcm "$root/quiet-room.pcm" noise:6:-60
check "a quiet room is no speech" "[[ \$(detect '$root/quiet-room.pcm') == 3 ]]"
check "for a reply too" "[[ \$(detect '$root/quiet-room.pcm' \"\${reply_detector[@]}\") == 3 && \$(detect '$root/fan-after-quiet-start.pcm' \"\${reply_detector[@]}\") == 3 ]]"
check "without the debug log there is no trace" "env -u VOXCMD_DEBUG XDG_RUNTIME_DIR='$root/no-trace' python3 '$package/.local/bin/voxcmd-autostop' --pcm '$root/quiet-room.pcm'; [[ ! -e '$root/no-trace/voxcmd/debug.log' ]]"

# A start that fails ends the session rather than leaving it open with no microphone.
sess_run alpha FAIL
check "a failed record start ends the session" "session_gone && [[ \$(taps) == 1 ]] && ended_because 'the microphone could not be opened'"
sess_run FAIL
check "so does one for the first turn" "session_gone && [[ \$(taps) == 0 ]] && ended_because 'the microphone could not be opened'"

# The voice key pressed while a turn is still settling: that listen takes the session over, and the turn's own watcher
# leaves it alone instead of ending it and discarding the user's recording. The overlay stays "open" so the first
# watcher is held in its settle wait until the takeover is done.
sess_overlay=open
sess_env=(VOXCMD_UI_SETTLE_MAX_SECS=30)
sess_start alpha beta
log_has_soon '^qs-ipc call clickhints state' 50
sess_voxcmd_env listen
log_has_soon '^tap beta' 50
echo closed >"$hints_state"
sess_wait
check "a voice key pressed during a turn takes the session over" "[[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
check "the turn's watcher does not listen again or cancel the new recording" "[[ \$(record_starts) == 3 ]] && ! grep -q 'microphone could not be opened' '$log' && ended_because 'nothing was said'"
sess_overlay=""
sess_env=()

# Ending the session while its recording is open cancels that recording.
sess_start HOLD
owner_is_recording
sess_voxcmd_env end-session
sess_wait
check "end-session while recording cancels it and closes the microphone" "session_gone && grep -q '^voxtype record cancel' '$log' && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle && \$(record_starts) == 1 ]] && ended_because 'ended by request'"

# Settling: the next listen waits for the overlay and popups. The stub bar reports what the files hold. Bounds are
# loose, since a loaded machine stretches every sleep; they only tell a short wait from the long one.
settle_ms() {
  local started
  started=$(date +%s%N)
  env "$@" "$sess_voxcmd" _settle >/dev/null 2>&1
  echo $((($(date +%s%N) - started) / 1000000))
}
rm -f "$hints_state" "$popup_state_file"
check "a settled screen waits only the app's moment" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0.3 VOXCMD_UI_SETTLE_MAX_SECS=20) -ge 300 && \$(settle_ms VOXCMD_APP_SETTLE_SECS=0.3 VOXCMD_UI_SETTLE_MAX_SECS=20) -lt 10000 ]]"
echo open >"$hints_state"
(sleep 0.6 && echo closed >"$hints_state") &
check "an open overlay is waited out" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0) -ge 450 ]]"
wait
for popup_state in "opening weather" "open weather" "closing weather"; do
  echo "$popup_state" >"$popup_state_file"
  (sleep 0.6 && echo closed >"$popup_state_file") &
  check "a popup that is '$popup_state' is waited out" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0) -ge 450 ]]"
  wait
done
echo open >"$hints_state"
check "a screen that never settles is waited on for a bounded time" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=1) -ge 1000 && \$(settle_ms VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=1) -lt 10000 ]] && ! env VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=0.5 '$sess_voxcmd' _settle"
rm -f "$hints_state"
check "no bar to ask counts as settled" "env XDG_CONFIG_HOME='$root/no-bar' VOXCMD_APP_SETTLE_SECS=0 '$sess_voxcmd' _settle"

# In a session the bar is asked after the turn's action and before the microphone opens again.
sess_run alpha "done"
check "the screen is checked between a turn's action and the next listen" "[[ \$(awk '/^tap alpha/{a=NR} /qs-ipc call clickhints state/{if (a && !q) q=NR} /voxtype record start/{n++; if (n==2) r=NR} END{print (a && a < q && q < r) ? \"ok\" : \"no\"}' '$log') == ok ]]"

# A stale session: its owner is gone, so the next listen routes normally and clears it.
stale_listen() {
  printf '%s\n' "tap hello" >"$sess_turns"
  : >"$log"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  jq -n -c --argjson owner "$1" --arg owner_start "$2" \
    '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
    >"$XDG_RUNTIME_DIR/voxcmd/session.json"
  sess_voxcmd_env listen
  sess_wait
}
stale_listen 999999 1
check "a stale session is dropped and the command routes normally" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap hello' && \$(record_starts) == 1 ]]"
check "a normal listen keeps the default silence allowance" "grep -q 'no_speech_secs=default' '$log' && grep -q 'min_speech_secs=default silence_secs=default' '$log'"
# A live process under the owner's PID is not the owner unless it started when the owner did.
"$stub_sleep" 60 &
reused_pid=$!
stale_listen "$reused_pid" 1
check "a reused owner PID does not keep the session" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap hello' ]]"
kill "$reused_pid" 2>/dev/null
wait "$reused_pid" 2>/dev/null
# Outside a session the same words are a command like any other.
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json"
printf '%s\n' "thank you" >"$sess_turns"
: >"$XDG_RUNTIME_DIR/voxcmd/debug.log"
sess_voxcmd_env listen
sess_wait
check "outside a session a stock noise transcript is routed" "grep -q 'transcript \"thank you\" goes to route' '$XDG_RUNTIME_DIR/voxcmd/debug.log' && ! grep -q 'guess at noise' '$XDG_RUNTIME_DIR/voxcmd/debug.log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/debug.log"

# The watcher dying mid-session takes the session with it.
sess_start alpha alpha alpha
pkill -TERM -f "$sess_voxcmd _watch"
sess_wait
check "a killed listener ends the session" "session_gone"
# SIGKILL runs no trap, so the file stays, but the owner check reads it as no session.
sess_start HOLD
owner_is_recording
pkill -KILL -f "$sess_voxcmd _watch"
sess_wait
check "a SIGKILLed listener leaves its file behind" "! session_gone"
printf '%s\n' "tap hello" >"$sess_turns"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
sess_voxcmd_env listen
sess_wait
check "and the next listen finds no session and routes normally" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap hello' ]]"
pkill -f "$stub_sleep"

# A recording that belongs to a reply keeps its priority over the session.
mkdir -p "$root/owner"
cp /bin/sleep "$root/owner/voxcmd"
"$root/owner/voxcmd" 60 &
owner_pid=$!
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
waiter_pid=$!
mkfifo "$root/pending-fifo"
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/pending-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
jq -n -c --argjson owner "$owner_pid" --arg owner_start "$(start_time_of "$owner_pid")" \
  '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
  >"$XDG_RUNTIME_DIR/voxcmd/session.json"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
: >"$log"
"$pkg_voxcmd" listen >/dev/null 2>&1
log_has_soon 'setsid '
check "a pending picker's reply wins over the open session" "grep -q 'setsid .*_watch reply' '$log' && ! grep -q 'setsid .*_watch session_turn' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
"$pkg_voxcmd" listen >/dev/null 2>&1
log_has_soon 'setsid '
check "with nothing pending, a live session's listen goes to the session" "grep -q 'setsid .*_watch session_turn' '$log'"
# The detector each listen starts: a reply's lower speech minimum, the session's settings, nothing for a command.
sess_env=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.5)
detector_settings_of() {
  printf '%s\n' SILENCE >"$sess_turns"
  : >"$log"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  sess_voxcmd_env listen
  sess_wait
  grep '^voxcmd-autostop ' "$log" | sed 's/^voxcmd-autostop //' | paste -sd' '
}
jq -n -c --argjson owner "$owner_pid" --arg owner_start "$(start_time_of "$owner_pid")" \
  '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
  >"$XDG_RUNTIME_DIR/voxcmd/session.json"
check "a session turn's listen keeps the session's settings" "[[ \$(detector_settings_of) == 'no_speech_secs=10 min_speech_secs=0.4 silence_secs=1.5' ]]"
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json"
check "a command's listen keeps auto-stop's own" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=0.5 silence_secs=default' ]]"
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/pending-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
check "a reply's listen wants only 0.1s of speech, with auto-stop's own pause and deadline" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=0.1 silence_secs=default' ]]"
sess_env=(VOXCMD_REPLY_MIN_SPEECH_SECS=0.2)
check "VOXCMD_REPLY_MIN_SPEECH_SECS sets it" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=0.2 silence_secs=default' ]]"
sess_env=()
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
kill "$owner_pid" "$waiter_pid" 2>/dev/null
wait "$owner_pid" "$waiter_pid" 2>/dev/null
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json" "$XDG_RUNTIME_DIR/voxtype/state"

echo
echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
