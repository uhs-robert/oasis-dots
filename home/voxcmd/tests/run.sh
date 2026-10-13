#!/usr/bin/env bash
# Tests for voxcmd: the click matcher, mapping and OCR strips, click.sh routing, numbered-pick replies and click mode's
# phrases, with run-sessions.sh (voice sessions and auto-stop) alongside. Run from anywhere: home/voxcmd/tests/run.sh
#
# Nothing here clicks, moves the pointer or captures the screen: it runs inside sandbox.sh, whose stubs stand in for
# grim, magick, tesseract, hyprctl, wlrctl, wl-kbptr and notify-send and log their calls, and voxcmd only ever runs
# with --dry-run, except in the numbered picks, which run it against the sandbox's voxtype and bar. All fixture text is
# made up.
# Fixtures are read by name inside the strings check evals.
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
[ -z "${SANDBOX_DIR:-}" ] || [ -z "${SANDBOX_TESSERACT_TSV+set}" ] || unset SANDBOX_TESSERACT_TSV
if [ -z "${SANDBOX_DIR:-}" ]; then
  # The session tests mostly wait on their watchers, so they run beside these, in a sandbox of their own, and print
  # once these are done. The last lines are the total and every failed check of both.
  outputs=$(mktemp -d)
  trap 'rm -rf "$outputs"' EXIT
  "$here/run-sessions.sh" >"$outputs/sessions" 2>&1 &
  sessions_pid=$!
  "$here/sandbox.sh" "$0" "$@" 2>&1 | tee "$outputs/click"
  click_status=${PIPESTATUS[0]}
  sessions_status=0
  wait "$sessions_pid" || sessions_status=$?
  cat "$outputs/sessions"
  awk '/^[0-9]+ passed, [0-9]+ failed$/ { passed += $1; failed += $3 } END { printf "\nin all: %d passed, %d failed\n", passed, failed }' \
    "$outputs/click" "$outputs/sessions"
  grep -h '^FAILED ' "$outputs/click" "$outputs/sessions"
  [ "$click_status" = 0 ] && [ "$sessions_status" = 0 ]
  exit
fi
share_dir=$package/.local/share/voxcmd
matcher=$share_dir/click-match.awk
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"

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

section "matching"
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

section "words one edit away"
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

section "joined letters and noise"
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

section "doubtful words"
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

section "sub-spans"
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

section "candidate box"
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

section "duplicates"
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

section "runs"
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

section "coordinate mapping"
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

section "strips"
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

section "click-ocr"
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
strips_left_running() {
  local deadline=$((SECONDS + 10)) pid running
  while ((SECONDS < deadline)); do
    running=0
    while read -r pid; do process_running "$pid" && running=1; done <"$root/strip_pids"
    ((running)) || return 1
    sleep 0.1
  done
  return 0
}
check "a failed strip ends the others instead of waiting for them" "[[ \$((SECONDS - started)) -lt 10 ]] && ! strips_left_running"
SANDBOX_ACTIVEWINDOW_JSON='{}'
check "no focused window is an error" "! out=\$('$share_dir/click-ocr' 2>&1) && grep -q 'no focused window' <<<\"\$out\""
SANDBOX_ACTIVEWINDOW_JSON=$default_window

section "routing with --dry-run"
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

section "covered text"
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

section "click-explain"
# `voxcmd click-explain` runs the same candidates() as a click, tracing; these check each reason line, and that it only
# reads. The window is the covered-text section's: "Sign in" centred at 175,82 and "Settings" at 230,132.
explain() { "$voxcmd" click-explain "$@" 2>&1; }
SANDBOX_CLIENTS_JSON='[]'
SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Sign
  word 1 1 2 136 40 24 24 95 in
  word 2 1 1 160 120 96 24 95 Settings
})
rm -f "$XDG_RUNTIME_DIR/voxcmd/click-target"
: >"$log"
out=$(explain "sign in")
check "the header names the window's size, capture mode, image size, scales, inversion, strips and OCR time" \
  "grep -q '^window   .* 160x96' <<<\"\$out\" && grep -q '^capture  toplevel, image 256x154, scale x1.600 y1.604, not inverted, 1 strip(s), OCR [0-9]* ms' <<<\"\$out\""
check "a strong run is kept and the outcome is the click point" "grep -q 'candidate 175,82 \"sign\": kept strong (same words)' <<<\"\$out\" && grep -q '^outcome  click at 175,82\$' <<<\"\$out\""
check "a run with no spoken word is not listed" "! grep -q 'settings(' <<<\"\$out\""
check "explain reads only: no click, no pointer move, no toast" "! grep -q 'wlrctl\|hyprctl dispatch\|hyprctl eval\|notify-send' '$log'"
check "and it leaves no click target for a later click to trust" "[ ! -e '$XDG_RUNTIME_DIR/voxcmd/click-target' ]"
check "the capture and the trace are deleted" "! ls '$XDG_RUNTIME_DIR' | grep -q 'voxcmd-click\|voxcmd-explain'"
check "it agrees with the real route on where it clicks" "[[ \$(runs_at 'click sign in') == 175,82 ]]"

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 55 Sign
  word 1 1 2 136 40 24 24 95 in
  word 2 1 1 160 120 96 24 30 Settings
})
out=$(explain "settings")
check "a word under the low floor is listed with its confidence and the rule" "grep -q 'word \"Settings\" (conf 30) near [0-9]*,[0-9]*: dropped, under 40, below even the low floor' <<<\"\$out\" && grep -q '^outcome  not on screen\$' <<<\"\$out\""
out=$(explain "sign in")
check "a spoken word at conf 55 is kept and shown with its confidence" "grep -q 'run 1: sign(55) in(95)' <<<\"\$out\" && grep -q 'kept strong' <<<\"\$out\""

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 10 40 12 24 95 2
  word 1 1 2 26 40 40 24 95 tasks
  word 1 1 3 70 40 30 24 95 are
  word 1 1 4 104 40 60 24 95 flagged
  word 1 1 5 168 40 50 24 95 today
  word 1 1 6 222 40 28 24 95 now
})
out=$(explain "2 tasks")
check "a link inside a sentence: the whole run fails the coverage rule" "grep -q 'dropped: coverage under half: 2 of 6' <<<\"\$out\""
check "so the sub-span pass runs and keeps just the link" "grep -q '^pass 2: sub-spans' <<<\"\$out\" && grep -q 'candidate [0-9]*,[0-9]* \"2 tasks\": sub-span, kept strong' <<<\"\$out\" && grep -q '^outcome  click at ' <<<\"\$out\""

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 70 24 95 Clone
})
out=$(explain "close")
check "a word one edit away is a near miss, dropped" "grep -q 'candidate [0-9]*,[0-9]* \"clone\": dropped: near miss only' <<<\"\$out\" && grep -q '^outcome  not on screen\$' <<<\"\$out\""

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Open
  word 1 1 2 136 40 96 24 95 Settings
})
out=$(explain "settings")
check "a weak match is kept weak and goes to the overlay" "grep -q 'kept weak' <<<\"\$out\" && grep -q '^outcome  overlay with 1' <<<\"\$out\""

SANDBOX_TESSERACT_TSV=$({
  header
  word 1 1 1 80 40 48 24 95 Sign
  word 1 1 2 136 40 24 24 95 in
})
clients <<<"$(
  client 0x2001 100 50 160 96 false false 1
  client 0x3001 150 50 60 60 true false 1
)"
out=$(explain "sign in")
check "a candidate under a floating window is kept by word matching but dropped as covered" "grep -q 'kept strong (same words), then dropped: covered by another window' <<<\"\$out\" && grep -q '^outcome  covered: ' <<<\"\$out\""
SANDBOX_CLIENTS_JSON='[]'
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 100, 0, 0]}]'
out=$(explain "sign in")
check "the bar's reserved edge is named" "grep -q 'covered by a reserved edge (the bar)' <<<\"\$out\""
SANDBOX_MONITORS_JSON='[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]'

out=$(explain "it")
check "a filler-only target reads nothing and says so" "grep -q '^outcome  filler-only target' <<<\"\$out\""

: >"$log"
SANDBOX_CLIENTS_JSON='[{"address": "0x4001", "mapped": true, "class": "other", "stableId": "18000009", "at": [100, 50], "size": [160, 96], "floating": false, "pinned": false, "monitor": 0, "workspace": {"id": 1}}]'
out=$(explain "sign in" --window 18000009)
check "--window captures that client by stableId and names its class" "grep -q '^grim .*-T 18000009' '$log' && grep -q '^window   other ' <<<\"\$out\""
out=$(explain "sign in" --window 99999)
check "an unknown --window says so" "grep -q 'no such window' <<<\"\$out\""
check "--window never read the focused window's buffer" "! grep -q '^grim .*-T 18000004' '$log'"
SANDBOX_CLIENTS_JSON='[]'
# The trace must cap weak matches at ten the way the real pick does, or explain would call the eleventh kept.
word_match_source=$(sed -n '/^word_match() {/,/^}/p' "$package/.local/bin/voxcmd")
twelve_weak=$(jq -nc '[range(12) | {id: "i\(.)", label: "Open Settings"}]')
traced=$(bash -c "$word_match_source"'
word_match_trace=1 word_match settings "$1"' _ "$twelve_weak")
check "the trace keeps only the ten weak matches the real pick keeps" "[[ \$(jq '[.[] | select(.kept)] | length' <<<\"\$traced\") == 10 && \$(jq '[.[] | select(.verdict == \"dropped: past the ten best weak matches\")] | length' <<<\"\$traced\") == 2 ]]"
check "explain never clicked or moved across all of the above" "! grep -q 'wlrctl\|hyprctl dispatch\|hyprctl eval\|notify-send' '$log'"

section "failures and toasts"
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
capture_status=0
capture_reason=$(run_click_at "error:no focused window") || capture_status=$?
check "a failed capture fails with only the reason" "[[ $capture_status == 1 && '$capture_reason' == 'no focused window' ]]"
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
click_status=0
failed_click=$(PATH="$root/nowlrctl:$PATH" run_click_at "175,82,left,1,2,3,4") || click_status=$?
check "a failed click fails with the tool's reason" "[[ $click_status == 1 && '$failed_click' == 'wlrctl: no seat' ]]"
check "click itself sends no toast for a failure" "! grep -q 'voxcmd failed' '$log'"

# The whole path: a failed click reaches the engine as a failure and its error toast leaves the screen text out.
: >"$log"
real_status=0
PATH="$root/nowlrctl:$PATH" "$voxcmd" "click sign in" >/dev/null 2>&1 || real_status=$?
check "the engine sees a failed click as a failure" "[[ $real_status != 0 ]]"
check "the failed click is one error toast with the reason" "[[ \$(grep -c '^notify-send .*voxcmd failed' '$log') == 1 ]] && grep -q '^notify-send -a voxcmd voxcmd failed Click: click: wlrctl: no seat\$' '$log'"
check "no toast holds the screen text" "! grep -q -i 'sign' '$log'"

# An integration that does not declare private labels keeps its label in the failure toast.
public_config=$root/config-public
mkdir -p "$public_config/integrations.d" "$public_config/replacements.d"
printf 'name="Plain"\nverbs=("break {target}")\ndeclare -A actions=([break]=%s)\n' "'false'" >"$public_config/integrations.d/plain.sh"
: >"$log"
VOXCMD_CONFIG_DIR=$public_config "$voxcmd" "break widget" >/dev/null 2>&1
check "an ordinary integration's failure toast names its label" "grep -q '^notify-send -a voxcmd voxcmd failed Plain: break widget\$' '$log'"

section "the window changed before the click"
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

section "numbered picks"
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
: >"$debug_log"
(
  wait_for_line 'watch: voxtype recording' "$debug_log"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
) &
VOXCMD_DEBUG=1 "$pkg_voxcmd" _watch route >/dev/null 2>&1
wait
rm -f "$debug_log"
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

# A signal or a silent bar ends the pick with the overlay still up, so it is dismissed on the way out. The signal waits
# until voxcmd-hints reads the answer FIFO: before then it may not yet know the overlay is up.
hints_reading_answer() {
  local deadline=$((SECONDS + 20))
  until pgrep -f "head -n 1 $XDG_RUNTIME_DIR/voxcmd-hints\\." >/dev/null; do
    ((SECONDS < deadline)) || return 1
    sleep 0.02
  done
}
wait_for_path() {
  local deadline=$((SECONDS + 20))
  until [ -e "$1" ]; do
    ((SECONDS < deadline)) || return 1
    sleep 0.02
  done
}
: >"$log"
SANDBOX_CLICKHINTS_HOLD=1 "$hints" "Which one?" "$hint_choices" >/dev/null &
waiter_pid=$!
hints_reading_answer
kill -TERM "$waiter_pid"
wait "$waiter_pid" && waiter_status=0 || waiter_status=$?
check "TERM exits 1 and dismisses the overlay" "[[ $waiter_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log'"
: >"$log"
start=$SECONDS
SANDBOX_CLICKHINTS_HOLD=1 VOXCMD_HINTS_TIMEOUT=0.2 run_hints "Which one?" "$hint_choices" >/dev/null && timeout_status=0 || timeout_status=$?
check "a reader timeout exits 1 and dismisses the overlay" "[[ $timeout_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log' && [[ $((SECONDS - start)) -lt 5 ]]"

# A signal during the open call itself: bash runs the trap only once the call returns, so the test sends TERM while the
# stub holds the call, then releases it. The overlay was requested, so it must still be dismissed.
: >"$log"
open_block=$root/open-block
SANDBOX_CLICKHINTS_HOLD=1 SANDBOX_CLICKHINTS_BLOCK=$open_block "$hints" "Which one?" "$hint_choices" >/dev/null &
opening_pid=$!
wait_for_path "$open_block.entered"
kill -TERM "$opening_pid"
: >"$open_block.release"
wait "$opening_pid" && opening_status=0 || opening_status=$?
check "TERM during the open call exits 1 and dismisses the overlay" "[[ $opening_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log'"

# --listen: the reply recording starts through voxcmd listen --start-only before the overlay opens. The recording is
# held, and the sandbox's setsid writes the owner file, so voxcmd-hints sees it live at once instead of waiting 2s for it.
: >"$log"
mkdir -p "$XDG_RUNTIME_DIR/voxtype"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
echo HOLD >"$root/held-turn"
SANDBOX_VOXTYPE_TURNS=$root/held-turn SANDBOX_CLICKHINTS_ANSWER=1 run_hints --listen "Which one?" "$hint_choices" >/dev/null
check "--listen starts the reply recording before the overlay opens" "[[ \$(grep -n 'voxtype record start' '$log' | head -1 | cut -d: -f1) -lt \$(grep -n 'clickhints open' '$log' | head -1 | cut -d: -f1) ]]"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
echo HOLD >"$root/held-turn"
SANDBOX_VOXTYPE_TURNS=$root/held-turn SANDBOX_CLICKHINTS_HOLD=1 "$hints" --listen "Which one?" "$hint_choices" >/dev/null &
waiter_pid=$!
wait_for_line 'clickhints open' "$log"
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

section "direction replies"
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

section "click mode routing"
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
# A dry run is dozens of short processes, so several run at once, as in run-phrases.sh.
strays_dir=$root/click-mode-strays
mkdir -p "$strays_dir"
example_index=0 parallel_routes=$(nproc)
while IFS= read -r phrase; do
  [ "$(jobs -rp | wc -l)" -lt "$parallel_routes" ] || wait -n
  (
    out=$(route_all "$phrase")
    if grep -q 'action=\(click_mode\|stop_clicking\)' <<<"$out"; then printf '%s; ' "$phrase" >"$strays_dir/$example_index"; fi
  ) &
  example_index=$((example_index + 1))
done < <(grep -h -o '^  "[^"<]*"$' "$all_config"/integrations.d/*.sh | tr -d '"' | sed 's/^ *//' | grep -v -e 'click mode' -e 'stop clicking' -e '^click_mode' -e '^stop_clicking' | sort -u)
wait
stray=$(cat "$strays_dir"/* 2>/dev/null)
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

# As voxcmd's session_turn matches them, after its own "done", "I'm done" and "that's all".
click_mode_exits() (
  # shellcheck disable=SC2034 # read by click.sh
  voxcmd_share_dir=$share_dir
  # shellcheck disable=SC1091
  source "$package/.config/voxcmd/integrations.d/click.sh"
  # shellcheck disable=SC2154 # set by click.sh
  [[ "$1" =~ ^($session_exit_phrases)$ ]]
)
for phrase in "stop clicking" "exit click mode" "done clicking" "im done clicking" "done with click mode" "okay exit click mode" \
  "quit click mode" "stop click mode" "exit clicking mode" "leave the click mode" "end clicking" "close click mode" "turn off click mode" \
  "click mode off" "exit click mode please" "alright please finish clicking now"; do
  check "'$phrase' ends click mode" "click_mode_exits '$phrase'"
done
for phrase in stop exit quit close cancel "exit settings" "stop recording" "turn off" "click mode"; do
  check "'$phrase' stays a click mode target" "! click_mode_exits '$phrase'"
done

# ---- Firefox: firefox-tab and firefox.sh, on a made-up profile -----------------------------------------------------

section "firefox"
firefox_tab=$share_dir/firefox-tab
firefox_root=$HOME/.config/mozilla/firefox
# A fresh profile, with Tridactyl loaded as $1 says (store, temporary, stale or none).
make_profile() { rm -rf -- "${firefox_root:?}" && "$here/firefox-profile" "$firefox_root" "$1"; }
# Window 0's selected tab titles 0x3001; window 1 shows a tab the store has not recorded as selected yet; the private
# window is in no store; window 2 of the store is open nowhere.
export SANDBOX_CLIENTS_JSON='[
  {"address": "0x3001", "mapped": true, "class": "firefox", "title": "Example Docs - Getting started — Mozilla Firefox", "focusHistoryID": 1, "workspace": {"id": 1}},
  {"address": "0x3002", "mapped": true, "class": "firefox", "title": "Inbox - Mailbox — Mozilla Firefox", "focusHistoryID": 2, "workspace": {"id": 1}},
  {"address": "0x3003", "mapped": true, "class": "firefox", "title": "Private notes — Mozilla Firefox Private Browsing", "focusHistoryID": 3, "workspace": {"id": 1}},
  {"address": "0x1003", "mapped": true, "class": "kitty", "title": "zsh", "focusHistoryID": 0, "workspace": {"id": 1}}]'
firefox_window() { jq -c --arg address "$1" '.[] | select(.address == $address)' <<<"$SANDBOX_CLIENTS_JSON"; }
SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x1003)
export SANDBOX_ACTIVEWINDOW_JSON
typed() { grep '^wtype ' "$log" | sed 's/^wtype //'; }

make_profile none
out=$("$firefox_tab" tabs)
check "the profile installs.ini names is read, not profiles.ini's Default=1" "[[ \$(jq length <<<\"\$out\") -gt 0 ]]"
check "the store decodes, matches and all, and hidden tabs are left out" "[[ \$(jq '[.[] | select(.window == 0)] | length' <<<\"\$out\") == 4 ]]"
check "a tab's title is its current history entry's" "jq -e 'any(.[]; .title == \"Example Docs - Getting started\" and .selected)' <<<\"\$out\" >/dev/null"
check "a window is found by its selected tab's title" "[[ \$(jq -r '[.[] | select(.window == 0) | .address] | unique | join(\" \")' <<<\"\$out\") == 0x3001 ]]"
check "or by any of its tabs while the store lags" "[[ \$(jq -r '[.[] | select(.window == 1) | .address] | unique | join(\" \")' <<<\"\$out\") == 0x3002 ]]"
check "a store window open nowhere has no address" "[[ \$(jq -r '[.[] | select(.window == 2) | .address] | unique | join(\" \")' <<<\"\$out\") == '' ]]"
check "a window the store lacks is listed by its title" "jq -e 'any(.[]; .window == null and .address == \"0x3003\" and .title == \"Private notes\")' <<<\"\$out\" >/dev/null"

out=$("$firefox_tab" places team)
check "places reads rows still in the write-ahead log" "[[ \$(jq -r '.[0] | \"\(.kind) \(.title)\"' <<<\"\$out\") == 'bookmark Team Wiki' ]]"
out=$("$firefox_tab" places code hub)
check "every word must be in the title or url, and hidden or place: rows are not" "[[ \$(jq -r 'map(.url) | join(\" \")' <<<\"\$out\") == https://code.example.org/ ]]"
out=$("$firefox_tab" places example)
check "sites come before pages" "[[ \$(jq -r '.[0].kind' <<<\"\$out\") == origin ]]"
check "a folder is no bookmark" "! grep -q folder <<<\"\$out\""
out=$("$firefox_tab" candidates sites "example com" --raw "Open example.com in Firefox.")
check "a domain said alone is a site of its own" "[[ \$(jq -r '.[0].id' <<<\"\$out\") == https://example.com ]]"
out=$("$firefox_tab" candidates sites "node js docs" --raw "open node.js docs")
check "a domain inside other words is not" "! grep -q 'https://node.js' <<<\"\$out\""
out=$("$firefox_tab" candidates tabs "tubesite" --raw "go to tubesite")
check "tabs are offered by their site's name, most recent first" "[[ \$(jq -r '[.[] | select(.match_text == \"tubesite\") | .label] | join(\"|\")' <<<\"\$out\") == 'Another cat video - TubeSite (tubesite.example)|Funny cat video - TubeSite (tubesite.example)' ]]"

for mode in store temporary stale none; do
  make_profile "$mode"
  expected=$mode
  [[ $mode != stale ]] || expected=none
  check "Tridactyl loaded as $mode reads as $expected" "[[ \$(\"\$firefox_tab\" tridactyl) == $expected ]]"
done
check "VOXCMD_FIREFOX_TRIDACTYL overrides it" "[[ \$(VOXCMD_FIREFOX_TRIDACTYL=on \"\$firefox_tab\" tridactyl) == store ]]"

make_profile temporary
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3002) "$firefox_tab" focus 0x3002 "Inbox - Mailbox")
check "focus focuses the window" "grep -q \"^hyprctl dispatch hl.dsp.focus({ window = 'address:0x3002' })\" '$log'"
check "then types :tab with the title through Tridactyl's escape hatch" "[[ \"\$(typed | paste -sd'|')\" == '-M alt , -m alt|-k Escape|:|-- tab Inbox - Mailbox|-k Return' ]]"
: >"$log"
status=0
out=$("$firefox_tab" focus 0x3002 "Inbox - Mailbox") || status=$?
check "nothing is typed when the window does not take focus" "[[ \$status != 0 && -z \$(typed) ]]"
check "and it says so" "[[ \$out == 'the Firefox window did not take focus' ]]"
make_profile temporary
: >"$log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3002) SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON=$(firefox_window 0x1003) \
  "$firefox_tab" focus 0x3002 "Inbox - Mailbox") || status=$?
check "typing stops when focus leaves Firefox after the first step" "[[ \$status != 0 && \$(typed | wc -l) == 1 ]]"
check "so the title and Return are never typed" "! typed | grep -q 'Inbox\\|Return' && [[ \$out == 'focus left Firefox, so the rest was not typed' ]]"
: >"$log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3002) SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON=$(firefox_window 0x3001) \
  "$firefox_tab" open --here https://example.com/) || status=$?
check "typing also stops when another Firefox window takes focus" "[[ \$status != 0 && \$(typed | wc -l) == 1 ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3002) "$firefox_tab" focus 0x3002 $'Inbox\nrm -rf ~\x1b[31m - Mailbox')
check "a title's newline and control characters are typed as spaces" "[[ \"\$(typed | paste -sd'|')\" == '-M alt , -m alt|-k Escape|:|-- tab Inbox rm -rf ~ [31m - Mailbox|-k Return' ]]"

make_profile stale
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3002) "$firefox_tab" focus 0x3002 "Inbox - Mailbox")
check "without Tridactyl only the window is focused" "grep -q 'hyprctl dispatch' '$log' && [[ -z \$(typed) ]]"

: >"$log"
status=0
SANDBOX_CLIENTS_JSON='[]' "$firefox_tab" goto --running https://tubesite.example >/dev/null || status=$?
check "goto --running leaves a closed Firefox to the caller" "[[ \$status == 3 ]] && ! grep -q 'dispatch\\|firefox' '$log'"

make_profile store
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" goto https://tubesite.example)
check "goto focuses the most recent tab on the site" "[[ \"\$(typed | grep '^-- ')\" == '-- tab Another cat video - TubeSite' ]]"
: >"$log"
out=$("$firefox_tab" goto https://unopened.example/page)
check "and opens a site no tab shows" "grep -q '^setsid owner= -f firefox --new-tab https://unopened.example/page' '$log'"
: >"$log"
status=0
out=$("$firefox_tab" open "javascript:alert(1)") || status=$?
check "open takes web urls only" "[[ \$status != 0 ]] && ! grep -q firefox '$log'"
: >"$log"
out=$("$firefox_tab" open --here https://example.com/)
check "open --here needs Firefox focused" "[[ \$out == 'Firefox is not focused' && -z \$(typed) ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" open --here https://example.com/)
check "and types into the address bar" "[[ \"\$(typed | paste -sd'|')\" == '-M ctrl l -m ctrl|-- https://example.com/|-k Return' ]]"
: >"$log"
out=$("$firefox_tab" close-tab)
check "close-tab never closes a tab in a window not focused" "[[ \$out == 'Firefox is not focused' && -z \$(typed) ]]"

# Link hints are two commands of Tridactyl's rc, so firefox-tab types their short names; the rc is the repo's own.
repo_rc=$package/../tridactyl/.config/tridactyl/tridactylrc
mkdir -p "$XDG_CONFIG_HOME/tridactyl"
cp "$repo_rc" "$XDG_CONFIG_HOME/tridactyl/tridactylrc"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" hints)
check "show links types only :voxhints" "[[ \"\$(typed | paste -sd'|')\" == '-M alt , -m alt|-k Escape|:|-- voxhints|-k Return' ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" hints 12)
check "a link number types only :voxfollow with it" "[[ \"\$(typed | paste -sd'|')\" == '-M alt , -m alt|-k Escape|:|-- voxfollow 12|-k Return' ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" hints '1");alert(1);("')
check "a link number is digits only" "[[ \$out == not\\ a\\ link\\ number:* && -z \$(typed) ]]"
check "the rc defines both commands" "grep -q '^command voxfollow js -p ' '$repo_rc' && grep -q '^command voxhints voxfollow 0\$' '$repo_rc'"
rc_js=$(sed -n 's/^command voxfollow js -p //p' "$repo_rc")
check "the rc's hints are numbered for one run, in the page's memory" "grep -q 'config.hintnames=\"numeric\";config.hintautoselect=\"false\"' <<<\"\$rc_js\" && ! grep -q 'config.set' <<<\"\$rc_js\""
check "and the settings go back once the hint run ends" "grep -q 'tri.excmds.hint().then(restore,restore)' <<<\"\$rc_js\""
if command -v node >/dev/null; then
  # The rc's code, run against a stand-in for Tridactyl and the page: what each number does with the hints on screen.
  cat >"$root/rc-js.js" <<'NODE'
const body = process.argv[2]
async function follow(JS_ARG, names) {
  const calls = []
  const tri = {
    config: { USERCONFIG: { hintnames: "own" } },
    excmds: { hint: () => new Promise(() => {}) },
    hinting_content: { getHintCommands: () => ({ reset: () => calls.push("reset"), pushKey: (key) => calls.push("key" + key), selectFocusedHint: () => calls.push("select") }) },
  }
  const document = { querySelectorAll: () => names.map((textContent) => ({ textContent })) }
  await eval(body)
  return calls.join(",") + ":" + tri.config.USERCONFIG.hintnames
}
;(async () => {
  const hints = ["1", "2", "12"]
  console.log([await follow("0", hints), await follow("2", hints), await follow("12", hints), await follow("9", hints), await follow('1");x("', hints)].join(" "))
})()
NODE
  out=$(node "$root/rc-js.js" "$rc_js")
  check "voxhints only shows hints, with the numbering set" "[[ \"\${out%% *}\" == ':numeric' ]]"
  check "voxfollow follows the hint with that number, digit by digit" "[[ \"\$out\" == *' key2,select:numeric key1,key2,select:numeric '* ]]"
  check "a number with no hint leaves hint mode and follows nothing" "[[ \"\$out\" == *' reset:numeric reset:numeric' ]]"
fi
: >"$log"
printf 'command voxhints voxfollow 0\n' >"$XDG_CONFIG_HOME/tridactyl/tridactylrc"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" hints 3) || status=$?
check "an rc without :voxfollow says so and types nothing" "[[ \$out == \"link hints need the voxfollow command in Tridactyl's tridactylrc\" && -z \$(typed) ]]"
rm "$XDG_CONFIG_HOME/tridactyl/tridactylrc"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" hints)
check "with no rc file nothing is judged, and :voxhints is typed" "[[ \"\$(typed | grep '^-- ')\" == '-- voxhints' ]]"
cp "$repo_rc" "$XDG_CONFIG_HOME/tridactyl/tridactylrc"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" dismiss-hints)
check "dismissing hints types Escape in the focused Firefox window" "[[ \"\$(typed)\" == '-k Escape' ]]"
: >"$log"
out=$("$firefox_tab" dismiss-hints) || status=$?
check "and never into another window" "[[ \$out == 'Firefox is not focused' && -z \$(typed) ]]"
make_profile none
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" hints)
check "hints need Tridactyl" "[[ \$out == 'link hints need Tridactyl' && -z \$(typed) ]]"

firefox_config=$root/firefox-config
mkdir -p "$firefox_config/integrations.d" "$firefox_config/replacements.d"
cp "$package"/.config/voxcmd/integrations.d/{apps,firefox,firefox-sites,keybinds}.sh "$firefox_config/integrations.d/"
out=$(VOXCMD_CONFIG_DIR=$firefox_config "$voxcmd" --dry-run "go to inbox mailbox" 2>&1)
check "a tab shown in a second window is one tab, not also that window" "[[ \$(grep -c '^option' <<<\"\$out\") == 1 ]] && grep -q 'action=focus_tab' <<<\"\$out\""
out=$(VOXCMD_CONFIG_DIR=$firefox_config "$voxcmd" --dry-run "go to private notes" 2>&1)
check "a private window is found by its title" "grep -q \"action=focus_tab .* id='0x3003 Private notes'\" <<<\"\$out\""
rm -f "$firefox_config/integrations.d/firefox.sh"
out=$(VOXCMD_CONFIG_DIR=$firefox_config "$voxcmd" --dry-run "go to inbox mailbox" 2>&1)
check "without firefox.sh, Apps still focuses the window by its title" "grep -q 'Apps (apps.sh) action=focus' <<<\"\$out\""

finish
