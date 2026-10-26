#!/usr/bin/env bash
# Tests for voxcmd: the click matcher, mapping and OCR strips, click.sh routing, numbered-pick replies and click mode's
# phrases, with run-sessions.sh (voice sessions and auto-stop), run-modes.sh (rapid and type modes), run-sequences.sh (several steps in one phrase) run-overview.sh (the overview integration) and run-monitors.sh (monitor phrases) alongside. Run from anywhere: home/voxcmd/tests/run.sh
#
# Nothing here clicks, moves the pointer or captures the screen: it runs inside sandbox.sh, whose stubs stand in for
# grim, magick, tesseract, hyprctl, wlrctl, wl-kbptr and notify-send and log their calls, and voxcmd only ever runs
# with `explain`, except in the numbered picks, which run it against the sandbox's voxtype and bar. All fixture text is
# made up.
# Fixtures are read by name inside the strings check evals.
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$here/../../../lib/check/lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"
[ -z "${SANDBOX_DIR:-}" ] || [ -z "${SANDBOX_TESSERACT_TSV+set}" ] || unset SANDBOX_TESSERACT_TSV
if [ -z "${SANDBOX_DIR:-}" ]; then
  # The session, mode and sequence tests mostly wait on their watchers and waits, so they run beside these, each in a sandbox of
  # its own, and print once these are done. The last lines are the total and every failed check of all.
  outputs=$(mktemp -d)
  trap 'rm -rf "$outputs"' EXIT
  "$here/run-sessions.sh" >"$outputs/sessions" 2>&1 &
  sessions_pid=$!
  "$here/run-modes.sh" >"$outputs/modes" 2>&1 &
  modes_pid=$!
  "$here/run-sequences.sh" >"$outputs/sequences" 2>&1 &
  sequences_pid=$!
  "$here/run-overview.sh" >"$outputs/overview" 2>&1 &
  overview_pid=$!
  "$here/run-monitors.sh" >"$outputs/monitors" 2>&1 &
  monitors_pid=$!
  "$here/sandbox.sh" "$0" "$@" 2>&1 | tee "$outputs/click"
  click_status=${PIPESTATUS[0]}
  sessions_status=0 modes_status=0 sequences_status=0 overview_status=0 monitors_status=0
  wait "$sessions_pid" || sessions_status=$?
  wait "$modes_pid" || modes_status=$?
  wait "$sequences_pid" || sequences_status=$?
  wait "$overview_pid" || overview_status=$?
  wait "$monitors_pid" || monitors_status=$?
  cat "$outputs/sessions" "$outputs/modes" "$outputs/sequences" "$outputs/overview" "$outputs/monitors"
  awk '/^[0-9]+ passed, [0-9]+ failed$/ { passed += $1; failed += $3 } END { printf "\nin all: %d passed, %d failed\n", passed, failed }' \
    "$outputs/click" "$outputs/sessions" "$outputs/modes" "$outputs/sequences" "$outputs/overview" "$outputs/monitors"
  grep -h '^FAILED ' "$outputs/click" "$outputs/sessions" "$outputs/modes" "$outputs/sequences" "$outputs/overview" "$outputs/monitors"
  [ "$click_status" = 0 ] && [ "$sessions_status" = 0 ] && [ "$modes_status" = 0 ] && [ "$sequences_status" = 0 ] && [ "$overview_status" = 0 ] && [ "$monitors_status" = 0 ]
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

# click_matcher <fixture> <target> <spans>: the matcher's candidates, one per line: the awk, or under VOXCMD_BIN=rs the
# Rust build, which must be what the sandbox put first on PATH. CLICK_CASES_DUMP=<dir> also keeps each call's page,
# target and mode there, for gen-click-goldens.sh (a call with the same inputs overwrites its files).
rust_matcher=
if [ "${VOXCMD_BIN:-bash}" = rs ]; then
  rust_matcher=$(command -v voxcmd)
  [[ $rust_matcher == "$package/target/release/voxcmd" ]] || {
    echo "run.sh: voxcmd is not this checkout's Rust build: $rust_matcher" >&2
    exit 2
  }
  # Tripwire: a call that fell through to the awk under rs would find no matcher and fail its check.
  matcher=/nonexistent/under-rs/click-match.awk
fi
click_matcher() {
  if [ -n "${CLICK_CASES_DUMP:-}" ]; then
    local id
    id=$(printf '%s\0%s\0%s' "$1" "$2" "$3" | md5sum | cut -c1-12)
    printf '%s\n' "$1" >"$CLICK_CASES_DUMP/$id.page"
    printf '%s' "$2" >"$CLICK_CASES_DUMP/$id.target"
    printf '%s' "$3" >"$CLICK_CASES_DUMP/$id.spans"
  fi
  if [ -n "$rust_matcher" ]; then
    CLICK_TARGET="$2" "$rust_matcher" internal click-match ${3:+--spans} <<<"$1"
  else
    CLICK_TARGET="$2" CLICK_SPANS="$3" awk -f "$matcher" <<<"$1"
  fi
}
# click_ocr: what the click-ocr checks run, the bash script or under rs the Rust build's hidden entry point (the same
# tripwire as the matcher's: bash's script is not reached under rs). click_ocr_cmd is the same, quoted for a check's eval.
click_ocr=("$share_dir/click-ocr")
[ -z "$rust_matcher" ] || click_ocr=("$rust_matcher" internal click-ocr)
click_ocr_cmd=$(printf '%q ' "${click_ocr[@]}")
# match <fixture> <target>: the matcher's candidates, one per line.
match() { click_matcher "$1" "$2" ""; }
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
spans() { click_matcher "$1" "$2" 1; }
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
: >"$SANDBOX_DIR/callers.log"
: >"$SANDBOX_DIR/ocr-calls.log"
out=$("${click_ocr[@]}")
check "emits the window and the image size" "[[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
check "emits one strip for a window of normal height" "[[ \$(grep -c '^#strip' <<<\"\$out\") == 1 ]]"
check "captures the window's own buffer by its stable id" "grep -q 'grim -t ppm -T 18000004' '$log' && ! grep -q ' -g ' '$log'"
check "captures at native scale: no -s" "! grep -q ' -s ' '$log'"
check "leaves no screenshot behind" "[[ -z \$(ls '$XDG_RUNTIME_DIR' | grep voxcmd-click) ]]"
: >"$log"
out=$(SANDBOX_GRIM_NO_TOPLEVEL=1 "${click_ocr[@]}")
check "a failed toplevel capture falls back to the screen region" "grep -q 'grim -t ppm -g 100,50 160x96' '$log' && [[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
SANDBOX_ACTIVEWINDOW_JSON='{"at": [100, 50], "size": [160, 96], "monitor": 0}'
: >"$log"
"${click_ocr[@]}" >/dev/null
check "no stable id captures the screen region without trying -T" "grep -q 'grim -t ppm -g 100,50 160x96' '$log' && ! grep -q ' -T ' '$log'"
SANDBOX_ACTIVEWINDOW_JSON=$default_window
: >"$log"
out=$(SANDBOX_GRIM_SIZE='256 100' "${click_ocr[@]}" 2>&1)
check "a toplevel capture of another shape falls back to the screen region, which stands in here for a right one" "grep -q 'grim -t ppm -T' '$log' && grep -q 'grim -t ppm -g' '$log' && [[ \$out == *'does not match'* ]]"
: >"$log"
out=$(SANDBOX_GRIM_SIZE='256 154' "${click_ocr[@]}" 2>&1)
check "a capture within 2% of the window's shape is used as it is" "! grep -q ' -g ' '$log' && [[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
out=$(SANDBOX_GRIM_SIZE='256 151' "${click_ocr[@]}" 2>&1)
check "a vertical scale 2% under the horizontal one is still taken" "[[ \$(head -1 <<<\"\$out\") == '#window 100 50 160 96 256 151' ]]"
out=$(SANDBOX_GRIM_SIZE='256 140' "${click_ocr[@]}" 2>&1)
check "a vertical scale 9% under the horizontal one is an error" "! SANDBOX_GRIM_SIZE='256 140' $click_ocr_cmd >/dev/null 2>&1 && [[ \$out == *'does not match'* ]]"
SANDBOX_ACTIVEWINDOW_JSON='{"at": [0, 0], "size": [1000, 1500], "monitor": 0, "stableId": "18000004"}'
out=$(SANDBOX_GRIM_SCALE=1 "${click_ocr[@]}")
check "a tall window is cut into 4 to 6 strips" "[[ \$(grep -c '^#strip' <<<\"\$out\") -ge 4 && \$(grep -c '^#strip' <<<\"\$out\") -le 6 ]]"
check "strips own contiguous rows from 0 to the image height" "[[ \$(grep '^#strip' <<<\"\$out\" | awk '{if (\$4 != prev) bad = 1; prev = \$5} END {print (bad ? \"gap\" : prev)}') == 1500 ]]"
check "a lower strip's crop starts 80 px above the rows it owns at scale 1" "[[ \$(grep '^#strip 1 ' <<<\"\$out\" | awk '{print \$4 - \$3}') == 80 ]]"
out=$(SANDBOX_GRIM_SCALE=2 "${click_ocr[@]}")
check "and 160 px above them at scale 2" "[[ \$(grep '^#strip 1 ' <<<\"\$out\" | awk '{print \$4 - \$3}') == 160 ]]"
mkdir -p "$root/failing"
printf '#!/bin/sh\nexit 1\n' >"$root/failing/tesseract"
chmod +x "$root/failing/tesseract"
check "a failed strip fails the whole OCR" "! SANDBOX_GRIM_SCALE=1 PATH='$root/failing':\$PATH $click_ocr_cmd >/dev/null 2>&1"
# One strip fails at once; the rest would sleep for a minute, and the run must not wait for them. Each stub logs its
# pid (kept across exec) so the check looks at this run's stubs only, not at any process that happens to sleep.
printf '#!/bin/sh\necho $$ >>"%s/strip_pids"\n[ ! -e "%s/slow_started" ] && : >"%s/slow_started" && exit 1\nexec sleep 60\n' \
  "$root" "$root" "$root" >"$root/failing/tesseract"
started=$SECONDS
SANDBOX_GRIM_SCALE=1 PATH="$root/failing:$PATH" "${click_ocr[@]}" >/dev/null 2>&1
# A killed stub is gone once its signal is delivered and it is reaped, which a loaded machine can take a moment to do;
# a stub that was missed sleeps on for the whole minute.
strip_stubs_gone() {
  local pid
  while read -r pid; do process_gone "$pid" || return 1; done <"$root/strip_pids"
}
check "a failed strip ends the others instead of waiting for them" "[[ \$((SECONDS - started)) -lt 60 ]] && wait_until strip_stubs_gone"
SANDBOX_ACTIVEWINDOW_JSON='{}'
check "no focused window is an error" "! out=\$($click_ocr_cmd 2>&1) && grep -q 'no focused window' <<<\"\$out\""
SANDBOX_ACTIVEWINDOW_JSON=$default_window

# The strips' tesseract is a stub a check makes fail, linger or sleep. It logs its pids so a check looks at this run's
# processes only, and takes its turns from markers in $strips_dir (mkdir is atomic, so exactly one strip wins each).
strips_dir=$root/strips
reset_strips() { rm -rf "$strips_dir" && mkdir -p "$strips_dir"; }
strip_stub() { cat >"$root/failing/tesseract"; }
strip_pids() { tr ' ' '\n' <"$strips_dir/pids"; }
all_strip_pids_gone() {
  local pid
  while read -r pid; do process_gone "$pid" || return 1; done < <(strip_pids)
}
failing_run() { SANDBOX_GRIM_SCALE=1 STRIPS_DIR=$strips_dir PATH="$root/failing:$PATH" "${click_ocr[@]}"; }
SANDBOX_ACTIVEWINDOW_JSON='{"at": [0, 0], "size": [1000, 1500], "monitor": 0, "stableId": "18000004"}'

# A strip that forks a child just before it fails. Ending the strips' children by parent pid missed that
# one, which slept on after the run; the whole group must be signalled.
reset_strips
strip_stub <<'EOF'
#!/bin/sh
sleep 60 &
echo "$$ $!" >>"$STRIPS_DIR/pids"
if mkdir "$STRIPS_DIR/failed" 2>/dev/null; then exit 1; fi
wait
EOF
chmod +x "$root/failing/tesseract"
# Only the failing strip is sure to have logged (a loaded machine can kill the others before they start), so two pids are the floor.
failing_run >/dev/null 2>&1
check "a failed strip also ends the child it forked, not only its siblings" "[[ \$(strip_pids | wc -l) -ge 2 ]] && wait_until all_strip_pids_gone"

# The failure path must find every strip, not only those a job listing shows under load. One fails at once
# and the rest sleep; repeated, since the miss was a race.
strip_stub <<'EOF'
#!/bin/sh
echo $$ >>"$STRIPS_DIR/pids"
if mkdir "$STRIPS_DIR/failed" 2>/dev/null; then exit 1; fi
exec sleep 60
EOF
leaked=0 statuses=""
for attempt in 1 2 3 4 5 6; do
  reset_strips
  failing_run >/dev/null 2>"$root/failed_stderr"
  statuses+="$? $(<"$root/failed_stderr") "
  wait_until all_strip_pids_gone || leaked=$((leaked + 1))
done
check "no strip outlives a failed run, in 6 runs" "[[ $leaked == 0 ]]"
check "each failed run exits 1 saying ocr failed" "[[ '$statuses' == '1 ocr failed 1 ocr failed 1 ocr failed 1 ocr failed 1 ocr failed 1 ocr failed ' ]]"
check "and leaves no work directory behind" "[[ -z \$(ls '$XDG_RUNTIME_DIR' | grep voxcmd-click) ]]"

# A strip that finished well is out of the set before anything is killed. One leaves a child behind in its
# group and exits 0; once it has, another fails. Signalling the finished strip's group would take its child too.
reset_strips
strip_stub <<'EOF'
#!/bin/sh
if mkdir "$STRIPS_DIR/finished" 2>/dev/null; then
  sleep 30 &
  echo $! >"$STRIPS_DIR/lingering"
  exit 0
fi
if mkdir "$STRIPS_DIR/failing" 2>/dev/null; then
  while [ ! -s "$STRIPS_DIR/lingering" ]; do sleep 0.02; done
  sleep 0.3
  exit 1
fi
echo $$ >>"$STRIPS_DIR/pids"
exec sleep 60
EOF
failing_run >/dev/null 2>&1
lingering=$(<"$strips_dir/lingering")
check "the strips still running are ended" "wait_until all_strip_pids_gone"
check "a strip that finished well is not signalled: the child it left behind lives" "process_running $lingering"
kill "$lingering" 2>/dev/null

# The strips come out in order, each one's text after its own line, though the last one finishes first.
strip_stub <<'EOF'
#!/bin/sh
number=${1##*strip}
number=${number%.pgm}
sleep "0.$((9 - number))"
echo "text-$number"
EOF
out=$(failing_run)
order=$(sed -n 's/^#strip \([0-9]*\) .*/\1/p;s/^text-/t/p' <<<"$out" | tr '\n' ' ')
check "strips come out in order, each followed by its own text" "[[ '$order' == '0 t0 1 t1 2 t2 3 t3 4 t4 ' ]]"
rm -f "$root/failing/tesseract"
SANDBOX_ACTIVEWINDOW_JSON=$default_window

# Which program drove the tools, and with what.
if [ -n "$rust_matcher" ]; then
  rust_real=$(realpath "$rust_matcher")
  check "every grim, magick and tesseract call came from the Rust binary, none from bash" "[[ -s '$SANDBOX_DIR/callers.log' ]] && ! grep -qv ' $rust_real\$' '$SANDBOX_DIR/callers.log'"
else
  check "every grim, magick and tesseract call came from bash" "[[ -s '$SANDBOX_DIR/callers.log' ]] && ! grep -qv 'bash\$' '$SANDBOX_DIR/callers.log'"
fi
ocr_calls() { sed "s#$XDG_RUNTIME_DIR/voxcmd-click\.[A-Za-z0-9]*#<work>#g" "$SANDBOX_DIR/ocr-calls.log"; }
: >"$SANDBOX_DIR/ocr-calls.log"
"${click_ocr[@]}" >/dev/null
tool_calls=$(ocr_calls)
check "magick cuts the strips and measures the mean in one call" "[[ \$(grep '^magick' <<<\"\$tool_calls\") == 'magick <work>/shot.ppm -colorspace Gray -depth 8 ( +clone -crop 256x154+0+0 +repage -write <work>/strip0.pgm +delete ) ( +clone -filter box -resize 1x1! -format %[fx:mean] -write info:- +delete ) null:' ]]"
check "tesseract reads the strip's file with the flags that keep it fast" "[[ \$(grep '^tesseract' <<<\"\$tool_calls\") == 'tesseract <work>/strip0.pgm - --psm 11 --oem 1 -c tessedit_do_invert=0 tsv' ]]"
: >"$SANDBOX_DIR/ocr-calls.log"
out=$(SANDBOX_IMAGE_MEAN=0.2 "${click_ocr[@]}" --explain)
tool_calls=$(ocr_calls)
check "a dark image is negated into a tesseract that reads the pipe" "grep -qx 'magick <work>/strip0.pgm -negate pgm:-' <<<\"\$tool_calls\" && grep -qx 'tesseract - - --psm 11 --oem 1 -c tessedit_do_invert=0 tsv' <<<\"\$tool_calls\""
check "and the info line says so" "grep -q $'\tinverted=1\t' <<<\"\$out\""
out=$(SANDBOX_IMAGE_MEAN=0.5 "${click_ocr[@]}" --explain)
check "a mean of exactly 0.5 is not dark" "grep -q $'\tinverted=0\t' <<<\"\$out\""

# The target window the click will check.
target=$XDG_RUNTIME_DIR/voxcmd/click-target
rm -f "$target"
"${click_ocr[@]}" >/dev/null
check "the captured window is recorded for the click" "[[ \$(jq -r '.window.stableId' '$target') == 18000004 && \$(jq -r '.captured_at | type' '$target') == number ]]"
check "in a directory only the owner can enter" "[[ \$(stat -c %a '$XDG_RUNTIME_DIR/voxcmd') == 700 ]]"
check "and no half-written copy is left beside it" "[[ -z \$(ls '$XDG_RUNTIME_DIR/voxcmd' | grep '^click-target\.') ]]"
rm -f "$target"
SANDBOX_ACTIVEWINDOW_JSON='{"at": [100, 50], "size": [160, 96], "monitor": 0, "stableId": "18000004", "class": "kitty"}'
out=$("${click_ocr[@]}" --explain)
check "--explain starts with the info line" "[[ \$(head -1 <<<\"\$out\") == $'#info\tclass=kitty\tmode=toplevel\tsize=160x96\timage=256x154\tscale_x=1.600\tscale_y=1.604\tinverted=0\tstrips=1\tocr_ms='* ]]"
check "then the window line" "[[ \$(sed -n 2p <<<\"\$out\") == '#window 100 50 160 96 256 154' ]]"
check "and leaves the click target alone" "[[ ! -e '$target' ]]"
SANDBOX_ACTIVEWINDOW_JSON=$default_window

# --window reads that client, wherever the focus is.
SANDBOX_CLIENTS_JSON='[{"stableId": "other", "at": [0, 0], "size": [10, 10]}, {"stableId": "77", "class": "foot", "at": [300, 400], "size": [160, 96]}]'
: >"$log"
out=$("${click_ocr[@]}" --window 77)
check "--window captures the named client by its stable id" "[[ \$(head -1 <<<\"\$out\") == '#window 300 400 160 96 256 154' ]] && grep -q 'grim -t ppm -T 77' '$log'"
check "and records that client as the target" "[[ \$(jq -r .window.class '$target') == foot ]]"
out=$("${click_ocr[@]}" --window 99 2>&1)
status=$?
check "an unknown client is no such window, exit 2" "[[ $status == 2 && '$out' == 'no such window' ]]"
SANDBOX_CLIENTS_JSON='[]'
out=$("${click_ocr[@]}" --bogus 2>&1)
status=$?
check "an option it does not know is a usage error, exit 2" "[[ $status == 2 && '$out' == 'usage: click-ocr [--window <stableId>] [--explain]' ]]"
SANDBOX_ACTIVEWINDOW_JSON='{"at": [100, 50], "size": [0, 0], "monitor": 0}'
out=$("${click_ocr[@]}" 2>&1)
status=$?
check "a window without size is an error, exit 2" "[[ $status == 2 && '$out' == 'focused window has no size' ]]"
SANDBOX_ACTIVEWINDOW_JSON=$default_window

section "routing with --dry-run"
config=$root/config
mkdir -p "$config/integrations.d" "$config/replacements.d"
# The bash build loads integrations.d only; the Rust build takes the shipped TOML over the bash copy.
cp "$package/.config/voxcmd/integrations.d/click.sh" "$package/.config/voxcmd/integrations.d/keybinds.sh" "$config/integrations.d/"
copy_shipped_integrations "$config" click keybinds
# A bash integration of its own for the logger checks below to find: every shipped one here is TOML, whose lookups
# the Rust build does itself, so without it nothing would show that the logger records the bash voxcmd's calls.
cat >"$config/integrations.d/stub-probe.sh" <<'STUB'
name="Stub probe"
verbs=("probe stubprobe {target}")
declare -A actions=([probe]=true)
candidates() { echo '[{"id": "1", "label": "probe"}]'; }
STUB
export VOXCMD_CONFIG_DIR=$config
# Both files are in the config; the Rust build must pick the TOML, the bash build can only load the .sh.
click_file='click\.sh'
keybinds_file='keybinds\.sh'
apps_file='apps\.sh'
[ -z "$rust_matcher" ] || {
  click_file='click\.toml'
  keybinds_file='keybinds\.toml'
  apps_file='apps\.toml'
}
# The bash form of the new CLI, for the sections 2.5 has not moved to the Rust build.
voxcmd=$package/tests/bin/voxcmd
# What routes and runs the phrases: the same, or under VOXCMD_BIN=rs the Rust build, which asks the bash voxcmd only for
# the integrations it has not taken over (the stub probe, click mode). That bash voxcmd sits behind a logger, so a check can
# show which of click.sh's functions it was still asked to run.
routed=$voxcmd
legacy_calls=$root/legacy-calls.log
if [ -n "$rust_matcher" ]; then
  routed=$rust_matcher
  : >"$legacy_calls"
  printf '#!/bin/sh\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$legacy_calls" "$package/.local/bin/voxcmd" >"$root/legacy-logger"
  chmod +x "$root/legacy-logger"
  export VOXCMD_LEGACY_BIN=$root/legacy-logger
fi
route() { "$routed" explain "$1" 2>&1; }

: >"$log"
out=$(route "click sign in")
check "a single strong match runs" "grep -q '^result:      run' <<<\"\$out\""
check "it is the Click integration's click" "grep -Eq 'Click \($click_file\).* action=click ' <<<\"\$out\""
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
check "bare 'right click' stays with the Cursor submap bind" "grep -Eq 'Keybinds \($keybinds_file\)' <<<\"\$out\" && ! grep -Eq 'Click \($click_file\)' <<<\"\$out\""
out=$(route "click")
check "bare 'click' stays with the keybinds" "! grep -Eq 'Click \($click_file\)' <<<\"\$out\""
# "click left", "click it" and the like are no click target: phrases.tsv records that they route as they did without
# Click. Here, that they do not even capture the screen.
: >"$log"
out=$(route "click left")
check "'click left' stays with the keybinds without capturing the screen" "grep -Eq 'Keybinds \($keybinds_file\)' <<<\"\$out\" && ! grep -q '^grim' '$log'"
out=$(route "show hints")
check "'show hints' launches wl-kbptr" "grep -q 'action=show_hints' <<<\"\$out\" && grep -q 'show_hints' <<<\"\$out\""
check "'show hints' is silent" "grep -q 'silent: true' <<<\"\$out\""
out=$(route "show click hints")
check "'show click hints' is the same" "grep -q 'action=show_hints' <<<\"\$out\""
out=$(route "keybind enter")
check "'keybind' still forces the keybinds" "grep -Eq 'forced to:   $keybinds_file' <<<\"\$out\""

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
check "bare 'triple click' needs a target and is not the Click integration's" "! grep -Eq 'Click \($click_file\)' <<<\"\$out\""

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
if [ -n "$rust_matcher" ]; then
  # The routes above captured through the Rust binary: the hook that did it was the built-in, not click.sh's candidates().
  rust_real=$(realpath "$rust_matcher")
  check "every capture of the routes and covered text came from the Rust binary, none from bash" "[[ -s '$SANDBOX_DIR/callers.log' ]] && ! grep -qv ' $rust_real\$' '$SANDBOX_DIR/callers.log'"
  # Without proof that the TOML is what ran, the absence below would hold for any file at all.
  check "explain names the shipped click.toml for the click" "grep -Eq 'Click \(click\.toml\).* action=click ' <<<\"\$(route 'click sign in')\""
  check "no lookup went through click.sh's candidates()" "! grep -Eq '^_legacy-hook candidates [^ ]*/click\.sh ' '$legacy_calls'"
  route "stubprobe anything" >/dev/null
  check "the logger sees the bash voxcmd's calls, so that absence means something" "grep -Eq '^_legacy-dump\$' '$legacy_calls' && grep -Eq '^_legacy-hook candidates [^ ]*/stub-probe\.sh ' '$legacy_calls'"
fi

section "click-explain"
# `voxcmd explain --window focused click` runs the same candidates() as a click, tracing; these check each reason line, and that it only
# reads. The window is the covered-text section's: "Sign in" centred at 175,82 and "Settings" at 230,132.
# The shim spells the focused window "--window focused" (see tests/bin/voxcmd); the Rust build takes it as it is, and
# prints the routing text before the click section.
explain_bin=$voxcmd
if [ -n "$rust_matcher" ]; then
  explain_bin=$rust_matcher
  # The numbered picks of an earlier run of this file re-export the legacy binary past the logger; name it here.
  export VOXCMD_LEGACY_BIN=$root/legacy-logger
fi
explain() { "$explain_bin" explain --window focused click "$@" 2>&1; }
explain_window() { "$explain_bin" explain --window "$1" click "${@:2}" 2>&1; }
: >"$SANDBOX_DIR/callers.log"
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
check "the routing and the click section share one capture: grim ran once for the phrase" "[[ \$(grep -c '^grim' '$log') == 1 ]]"
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
out=$(explain_window 18000009 "sign in")
check "--window captures that client by stableId and names its class" "grep -q '^grim .*-T 18000009' '$log' && grep -q '^window   other ' <<<\"\$out\""
out=$(explain_window 99999 "sign in")
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
if [ -n "$rust_matcher" ]; then
  rust_real=$(realpath "$rust_matcher")
  # The shim form prints no routing text: a trace that starts at the window line came from the bash click-explain.
  out=$(explain "sign in")
  check "the Rust trace prints the routing text first, then the click section" "[[ \$(head -1 <<<\"\$out\") == 'transcript:  click sign in' ]] && [[ \$(grep -n '^window   ' <<<\"\$out\" | head -1 | cut -d: -f1) -gt \$(grep -n '^why:' <<<\"\$out\" | head -1 | cut -d: -f1) ]]"
  check "every capture of the click-explain checks came from the Rust binary, none from bash" "[[ -s '$SANDBOX_DIR/callers.log' ]] && ! grep -qv ' $rust_real\$' '$SANDBOX_DIR/callers.log'"
  check "the click-explain trace names click.toml" "grep -Eq 'Click \(click\.toml\)' <<<\"\$out\""
  check "bash's click-explain was never asked, and the logger that would show it sees the bash voxcmd" "[[ -s '$legacy_calls' ]] && ! grep -Eq 'click-explain|^_legacy-hook candidates [^ ]*/click\.sh ' '$legacy_calls'"
fi

section "failures and toasts"
# click_at as voxcmd would eval it, with the stubs logging instead of acting.
# Under VOXCMD_BIN=rs it is the Rust build's hidden `internal click-at`, which prints the reason and exits 1 the same way.
run_click_at() {
  if [ -n "$rust_matcher" ]; then
    "$rust_matcher" internal click-at --target "sign in" "$1"
    return
  fi
  (
    # shellcheck disable=SC2034 # read by click.sh
    voxcmd_share_dir=$share_dir target="sign in"
    # shellcheck source=/dev/null
    source "$package/.config/voxcmd/integrations.d/click.sh"
    click_at "$1"
  )
}
: >"$SANDBOX_DIR/click-callers.log"
: >"$SANDBOX_DIR/callers.log"
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
PATH="$root/nowlrctl:$PATH" "$routed" run "click sign in" >/dev/null 2>&1 || real_status=$?
check "the engine sees a failed click as a failure" "[[ $real_status != 0 ]]"
check "the failed click is one error toast with the reason" "[[ \$(grep -c '^notify-send .*voxcmd failed' '$log') == 1 ]] && grep -q '^notify-send -a voxcmd voxcmd failed Click: click: wlrctl: no seat\$' '$log'"
check "no toast holds the screen text" "! grep -q -i 'sign' '$log'"

# An integration that does not declare private labels keeps its label in the failure toast.
public_config=$root/config-public
mkdir -p "$public_config/integrations.d" "$public_config/replacements.d"
printf 'name="Plain"\nverbs=("break {target}")\ndeclare -A actions=([break]=%s)\n' "'false'" >"$public_config/integrations.d/plain.sh"
: >"$log"
VOXCMD_CONFIG_DIR=$public_config "$routed" run "break widget" >/dev/null 2>&1
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
if [ -n "$rust_matcher" ]; then
  # Proof Rust ran: the two sections above clicked, toasted and captured from the Rust binary, with no function of
  # click.sh asked of the bash voxcmd (the toasts, the pointer, the lookups and the actions all were the built-ins).
  rust_real=$(realpath "$rust_matcher")
  check "every pointer move, click and toast came from the Rust binary, none from bash" "[[ -s '$SANDBOX_DIR/click-callers.log' ]] && ! grep -qv ' $rust_real\$' '$SANDBOX_DIR/click-callers.log' && grep -q '^wlrctl ' '$SANDBOX_DIR/click-callers.log' && grep -q '^hyprctl ' '$SANDBOX_DIR/click-callers.log' && grep -q '^notify-send ' '$SANDBOX_DIR/click-callers.log'"
  check "so did every capture" "[[ -s '$SANDBOX_DIR/callers.log' ]] && ! grep -qv ' $rust_real\$' '$SANDBOX_DIR/callers.log'"
  check "the click phrases ran from click.toml" "grep -Eq 'Click \(click\.toml\).* action=click ' <<<\"\$(route 'click sign in')\""
  check "none of click.sh's lookups, actions or box placing was asked of the bash voxcmd" "! grep -Eq '^_legacy-hook (candidates|run|pick-boxes) [^ ]*/click\.sh ' '$legacy_calls'"
  route "stubprobe anything" >/dev/null
  check "while the bash voxcmd was still asked for the integrations that stay on it" "grep -Eq '^_legacy-hook candidates [^ ]*/stub-probe\.sh ' '$legacy_calls'"
  rm -f "$config/integrations.d/stub-probe.sh"
fi

# ---- numbered on-screen picks: the integration hook, voxcmd-hints and its replies ---------------------------------------
# A copy of the package whose voxcmd-pick and voxcmd-autostop are the sandbox's stubs, so nothing asks a real picker or
# records audio; voxcmd-hints is the real one and finds the stub voxcmd-pick beside itself.

section "numbered picks"
pkg=$root/pkg
mkdir -p "$pkg"
cp -r "$package/.local" "$pkg/.local"
ln -sf "$SANDBOX_DIR/bin/voxcmd-pick" "$pkg/.local/bin/voxcmd-pick"
ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$pkg/.local/bin/voxcmd-autostop"
link_voxcmd_shim "$pkg"
pkg_voxcmd=$pkg/tests/bin/voxcmd
# The Rust voxcmd finds voxcmd-pick, voxcmd-confirm and the share files beside the bash voxcmd it falls back on; the
# bash one ignores this.
export VOXCMD_LEGACY_BIN=$pkg/.local/bin/voxcmd
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
"$pkg_voxcmd" run tap next >/dev/null 2>&1
check "several matches ask the integration's pick command" "grep -q '^fake-pick Which one? ' '$log' && ! grep -q 'voxcmd-pick' '$log'"
check "its choices carry each option's box" "grep -q '\"box\":\[100,50,60,20\]' '$log' && grep -q '\"box\":\[300,200,70,22\]' '$log'"
check "a typed command does not listen" "! grep -q 'fake-pick --listen' '$log'"
check "the pick's answer runs that option" "[[ \$(cat '$action_log') == '3,4,left,300,200,70,22' ]]"

VOXCMD_CONFIG_DIR=$(new_config unboxed 'pick_box() { return 1; }')
: >"$log"
"$pkg_voxcmd" run tap next >/dev/null 2>&1
check "an option without a box falls back to the text picker" "grep -q '^voxcmd-pick Which command?' '$log' && ! grep -q fake-pick '$log'"
# shellcheck disable=SC2016 # integration source, expanded when the integration runs
VOXCMD_CONFIG_DIR=$(new_config garbled 'pick_box() { case "$1" in 3,*) echo "not a box" ;; *) echo "1 2 3 4" ;; esac; }')
: >"$log"
"$pkg_voxcmd" run tap next >/dev/null 2>&1
check "a pick_box that prints garbage for one option falls back to the text picker" "grep -q '^voxcmd-pick Which command?' '$log' && ! grep -q fake-pick '$log'"
VOXCMD_CONFIG_DIR=$(new_config nofunction "")
: >"$log"
"$pkg_voxcmd" run tap next >/dev/null 2>&1
check "pick_command without pick_box falls back too" "grep -q '^voxcmd-pick ' '$log' && ! grep -q fake-pick '$log'"

# A spoken command: `internal watch` routes the transcript voxtype wrote, as `voxcmd listen` leaves it to do.
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
VOXCMD_DEBUG=1 "$pkg_voxcmd" internal watch route >/dev/null 2>&1
wait
rm -f "$debug_log"
check "a spoken command passes --listen to the pick command" "grep -q '^fake-pick --listen Which one? ' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxtype/state"

# voxcmd-hints: the sandbox's qs-ipc logs the pending state as it is when the overlay opens, then answers through the
# result FIFO as the bar would, with SANDBOX_CLICKHINTS_ANSWER: a number, a label or nothing.
hint_choices='[{"id":"a","label":"Next - top","box":[100,50,60,20]},{"id":"b","label":"Next - bottom","box":[300,200,70,22]}]'
run_hints() { "$pkg_voxcmd" ask hints "$@"; }
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
hints_reading_answer() { wait_until pgrep -f "head -n 1 $XDG_RUNTIME_DIR/voxcmd-hints\\." >/dev/null; }
: >"$log"
SANDBOX_CLICKHINTS_HOLD=1 "$pkg_voxcmd" ask hints "Which one?" "$hint_choices" >/dev/null &
waiter_pid=$!
hints_reading_answer
kill -TERM "$waiter_pid"
wait "$waiter_pid" && waiter_status=0 || waiter_status=$?
check "TERM exits 1 and dismisses the overlay" "[[ $waiter_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log'"
: >"$log"
start=$SECONDS
SANDBOX_CLICKHINTS_HOLD=1 VOXCMD_HINTS_TIMEOUT=0.2 run_hints "Which one?" "$hint_choices" >/dev/null && timeout_status=0 || timeout_status=$?
check "a reader timeout exits 1 and dismisses the overlay" "[[ $timeout_status == 1 ]] && grep -q 'qs-ipc call clickhints dismiss' '$log' && [[ $((SECONDS - start)) -lt 60 ]]"

# A signal during the open call itself: bash runs the trap only once the call returns, so the test sends TERM while the
# stub holds the call, then releases it. The overlay was requested, so it must still be dismissed.
: >"$log"
open_block=$root/open-block
SANDBOX_CLICKHINTS_HOLD=1 SANDBOX_CLICKHINTS_BLOCK=$open_block "$pkg_voxcmd" ask hints "Which one?" "$hint_choices" >/dev/null &
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
SANDBOX_VOXTYPE_TURNS=$root/held-turn SANDBOX_CLICKHINTS_HOLD=1 "$pkg_voxcmd" ask hints --listen "Which one?" "$hint_choices" >/dev/null &
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
reply_dry() { "$voxcmd" reply --dry-run "$1" 2>&1; }
check "a waiting voxcmd-hints is a pending pick that a reply finds" "grep -q 'picker:      Which one?' <<<\"\$(reply_dry two)\""
check "an ordinal picks by number" "grep -q 'result:      pick: 2. Next - bottom' <<<\"\$(reply_dry 'the second one')\""
check "a spoken number picks by number" "grep -q 'result:      pick: 3. ' <<<\"\$(reply_dry 3)\""
check "label words pick" "grep -q 'result:      pick: 3. Settings - middle' <<<\"\$(reply_dry settings)\""
check "a number past the choices is unclear" "grep -q 'unclear: there are only 3 choices' <<<\"\$(reply_dry 'number 8')\""
check "an ordinal with its own suffix picks" "grep -q 'result:      pick: 3. ' <<<\"\$(reply_dry 'the 3rd one')\""
check "an ordinal past the choices is unclear" "grep -q 'unclear: there are only 3 choices' <<<\"\$(reply_dry 'the twelfth one')\""
check "a compound ordinal is a position" "grep -q 'unclear: there are only 3 choices' <<<\"\$(reply_dry 'twenty first')\""
check 'last picks the last choice' "grep -q 'result:      pick: 3. ' <<<\"\$(reply_dry 'the last one')\""
check "an ordinal without its own suffix is no position" "! grep -q 'result:      pick: 2. ' <<<\"\$(reply_dry '2th')\" && ! grep -q 'there are only' <<<\"\$(reply_dry '2th')\""
check "cancel cancels" "grep -q 'result:      cancel' <<<\"\$(reply_dry 'never mind')\""

: >"$log"
touch "$listen_again"
"$pkg_voxcmd" reply "banana" >/dev/null 2>&1
check "an unclear reply listens once more" "[[ ! -e '$listen_again' ]] && grep -q 'voxtype record start' '$log'"
: >"$log"
"$pkg_voxcmd" reply "banana" >/dev/null 2>&1
check "and only once" "! grep -q 'voxtype record start' '$log'"
# The answer goes into the FIFO as the displayed label.
(timeout "$test_wait_secs" head -n 1 "$reply_fifo" >"$root/reply-answer") &
reader=$!
"$pkg_voxcmd" reply "two" >/dev/null 2>&1
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
copy_shipped_integrations "$all_config"
# Every shipped integration is TOML by now, so the witness that the bash voxcmd is still asked about its own kind needs
# a bash integration that is not shipped.
cat >"$all_config/integrations.d/click-witness.sh" <<'STUB'
name="Click witness"
verbs=("witness clickwitness {target}")
declare -A actions=([witness]=true)
candidates() { echo '[{"id": "1", "label": "witness"}]'; }
STUB
route_all() { VOXCMD_CONFIG_DIR=$all_config "$routed" explain "$1" 2>&1; }
for phrase in "click mode" "start clicking" "clicking mode" "enter click mode"; do
  out=$(route_all "$phrase")
  check "'$phrase' opens click mode, alone" "grep -q 'result:      run' <<<\"\$out\" && grep -Eq 'Click \($click_file\) action=click_mode' <<<\"\$out\" && [[ \$(grep -c '^option' <<<\"\$out\") == 1 ]]"
done
out=$(route_all "stop clicking")
check "'stop clicking' ends click mode instead of pausing media" "grep -Eq 'Click \($click_file\) action=stop_clicking' <<<\"\$out\" && [[ \$(grep -c '^option' <<<\"\$out\") == 1 ]]"
if [ -n "$rust_matcher" ]; then
  # Run for real: click mode opens, then "stop clicking" ends it, which shows the action ran. click.toml's mode action is
  # Rust's own, so the bash voxcmd is asked about the integrations that stay on it (a phrase for Apps proves the logger sees
  # its calls) and never about click.
  # The "numbered picks" section pointed VOXCMD_LEGACY_BIN at its own copy, past the logger.
  # Opening a mode looks for voxcmd-autostop beside the legacy binary, here the logger.
  ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$root/voxcmd-autostop"
  VOXCMD_LEGACY_BIN=$root/legacy-logger VOXCMD_CONFIG_DIR=$all_config "$routed" run "click mode" >/dev/null 2>&1
  session_file=$XDG_RUNTIME_DIR/voxcmd/session.json
  opened=0
  [ ! -e "$session_file" ] || opened=1
  : >"$legacy_calls"
  stop_status=0
  VOXCMD_LEGACY_BIN=$root/legacy-logger VOXCMD_CONFIG_DIR=$all_config "$routed" run "stop clicking" >/dev/null 2>&1 || stop_status=$?
  check "'click mode' opens a session and 'stop clicking' ends it" "[[ $opened == 1 && $stop_status == 0 && ! -e '$session_file' ]]"
  VOXCMD_LEGACY_BIN=$root/legacy-logger VOXCMD_CONFIG_DIR=$all_config "$routed" explain "clickwitness anything" >/dev/null 2>&1
  check "a mode action of click.toml runs natively, with the bash voxcmd asked about others but never about click" "grep -Eq '^_legacy-hook candidates [^ ]*/click-witness\\.sh ' '$legacy_calls' && ! grep -Eq '^_legacy-hook [a-z-]+ [^ ]*/click\\.' '$legacy_calls'"
fi
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

# The pick_box, session_rewrite and exit-phrase checks below read the bash click.sh, which stays until the bash loader goes.
# click.toml's counterparts are cargo tests: click/pick.rs (a box from an id), session/mode.rs (the rewrite and the
# exit and target phrases) and tests/toml_mode.rs (the whole mode run); this one only checks the TOML declares the picker.
if [ -n "$rust_matcher" ]; then
  check "click.toml numbers several matches on screen" "grep -q '^picker = \"hints\"' '$package/.config/voxcmd/integrations/click.toml'"
fi
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

# As voxcmd's session_turn matches them, after its own "done", "I'm done" and "that's all". Bare "exit" and "quit" are here
# because only "cortana exit" reaches this regex (default exits are off); run-sessions covers them bare, as targets.
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
  "click mode off" "exit" "quit" "exit click mode please" "alright please finish clicking now" "now exit click mode" "stop clicking okay"; do
  check "'$phrase' ends click mode" "click_mode_exits '$phrase'"
done
for phrase in stop close cancel "exit settings" "stop recording" "turn off" "click mode"; do
  check "'$phrase' stays a click mode target" "! click_mode_exits '$phrase'"
done

# ---- Timers and reminders ----------------------------------------------------------------------------------------

section "timers by voice"
# Nothing here starts a real timer: systemd-run and systemctl are the sandbox's stubs, which log their calls, and
# SANDBOX_TIMERS_JSON stands in for the running timers. Durations are relative to the clock the action reads, so a run
# compares the logged --on-calendar with now plus the spoken length, loosely.
timers_config=$root/timers-config
mkdir -p "$timers_config/integrations.d" "$timers_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/timers.sh" "$timers_config/integrations.d/"
copy_shipped_integrations "$timers_config" timers
[ -z "$rust_matcher" ] || check "explain names timers.toml" "VOXCMD_CONFIG_DIR='$timers_config' '$routed' explain 'list my timers' 2>&1 | grep -q 'Timers (timers\\.toml)'"
if [ -n "$rust_matcher" ]; then
  timers_toast() { grep '^notify-send ' "$log" | tail -n1; }
  timers_run() {
    : >"$log"
    VOXCMD_CONFIG_DIR=$timers_config "$routed" run "$1" >/dev/null 2>&1
  }
  # The seconds from now at which the last systemd-run call is due, and its description.
  timers_scheduled_in() {
    local when
    when=$(grep '^systemd-run ' "$log" | tail -n1 | sed -E 's/.*--on-calendar=([0-9-]+ [0-9:]+) .*/\1/')
    echo $(($(date -d "$when" +%s) - $(date +%s)))
  }
  timers_near() { [ "$1" -ge "$(($2 - 5))" ] && [ "$1" -le "$(($2 + 5))" ]; }
  timers_systemd_run_count() { grep -c '^systemd-run ' "$log" || true; }

  # Start by duration, with and without a label.
  timers_run "set a timer for 5 minutes"
  check "a timer for a duration schedules a voxcmd-timer- unit about that far ahead" "grep -q '^systemd-run --user --quiet --collect --unit=voxcmd-timer-[0-9]* --description=Timer: 5 minutes ' '$log' && timers_near \$(timers_scheduled_in) 300"
  check "its reply says the timer is set and when it rings" "timers_toast | grep -Eq 'Timer set: 5 minutes, rings '"
  timers_run "set a timer for 5 minutes for the pasta"
  check "a label after the duration is kept, capitalised" "grep -q -- '--description=Timer: Pasta, 5 minutes ' '$log' && timers_near \$(timers_scheduled_in) 300"
  timers_run "start a timer for twenty five minutes to call the bank"
  check "a spoken number and a to-label split like a digit one" "grep -q -- '--description=Timer: To call the bank, 25 minutes ' '$log'"
  timers_run "set a timer for half an hour for the oven"
  check "half an hour with a label is 30 minutes" "grep -q -- '--description=Timer: Oven, 30 minutes ' '$log' && timers_near \$(timers_scheduled_in) 1800"
  timers_run "set a timer for an hour and a half"
  check "an hour and a half is 90 minutes" "timers_near \$(timers_scheduled_in) 5400"
  timers_run "set a timer for 1 hour 30 minutes tea"
  check "digits split from the label like words" "grep -q -- '--description=Timer: Tea, ' '$log' && timers_near \$(timers_scheduled_in) 5400"

  # Start by clock: VOXCMD_NOW pins the parser, but the action compares with the real clock, so a future clock reads
  # the real time and a past one pins an old date.
  now_epoch=$(date +%s)
  : >"$log"
  VOXCMD_NOW=$now_epoch VOXCMD_CONFIG_DIR=$timers_config "$routed" run "set a timer for tomorrow at 9 am" >/dev/null 2>&1
  check "a timer for a clock time schedules a timer with the time of day as its description" "grep -Eq -- '--description=Timer: 9:00am ' '$log' && [[ \$(timers_scheduled_in) -gt 0 ]]"
  : >"$log"
  VOXCMD_NOW=1577880000 VOXCMD_CONFIG_DIR=$timers_config "$routed" run "set a timer for tomorrow at 9 am" >/dev/null 2>&1
  check "a clock time already past schedules nothing and says so" "[[ \$(timers_systemd_run_count) == 0 ]] && timers_toast | grep -q 'is in the past'"

  # Reminders in the four orderings.
  timers_run "remind me in 20 minutes to call the bank"
  check "remind: time, then to and the text" "grep -q -- '--description=Reminder: Call the bank ' '$log' && timers_near \$(timers_scheduled_in) 1200"
  timers_run "remind me to stretch in 10 minutes"
  check "remind: text, then the time" "grep -q -- '--description=Reminder: Stretch ' '$log' && timers_near \$(timers_scheduled_in) 600"
  timers_run "remind me about the oven in 5 minutes"
  check "remind: about the text, then the time" "grep -q -- '--description=Reminder: The oven ' '$log' && timers_near \$(timers_scheduled_in) 300"
  : >"$log"
  VOXCMD_NOW=$now_epoch VOXCMD_CONFIG_DIR=$timers_config "$routed" run "remind me tomorrow at 9 am to stretch" >/dev/null 2>&1
  check "remind: a clock time, then to and the text" "grep -q -- '--description=Reminder: Stretch ' '$log' && [[ \$(timers_scheduled_in) -gt 0 ]]"
  timers_run "remind me to stretch"
  check "a reminder with no time in it schedules nothing and says so" "[[ \$(timers_systemd_run_count) == 0 ]] && timers_toast | grep -q 'no time in'"
  timers_run "remind me in 5 minutes"
  check "a reminder with only a time rings with the default text" "grep -q -- '--description=Reminder: Time is up ' '$log'"

  # A target that names no time is left to others.
  check "a timer for a name that is no time offers no candidate, so the phrase stays unmatched" "VOXCMD_CONFIG_DIR='$timers_config' '$routed' explain 'start a timer for 5 minutes' 2>&1 | grep -q 'Timers (timers\\.toml) action=timer' && VOXCMD_CONFIG_DIR='$timers_config' '$routed' explain 'start a timer for acme' 2>&1 | grep -q 'result:      no match'"

  # What is running.
  timers_due=$(($(date +%s) + 600))
  timers_due_us=$((timers_due * 1000000))
  timers_two='[{"unit":"voxcmd-timer-1000.timer","next":'$timers_due_us'},{"unit":"voxcmd-timer-2000.timer","next":'$((timers_due_us + 60000000))'}]'
  timers_two_units='[{"unit":"voxcmd-timer-1000.timer","description":"Timer: Pasta, 10 minutes"},{"unit":"voxcmd-timer-2000.timer","description":"Reminder: Call the bank"}]'
  timers_one='[{"unit":"voxcmd-timer-1000.timer","next":'$timers_due_us'}]'
  timers_one_units='[{"unit":"voxcmd-timer-1000.timer","description":"Timer: Pasta, 10 minutes"}]'
  # The sandbox answers list-timers and list-units from one variable, so each fixture holds both: every row carries the
  # due time list-timers is read for and the description list-units is read for.
  timers_both() { jq -c -n --argjson due "$1" --argjson units "$2" '[$due, $units] | transpose | map(.[0] + .[1])'; }
  timers_state_two=$(timers_both "$timers_two" "$timers_two_units")
  timers_state_one=$(timers_both "$timers_one" "$timers_one_units")
  timers_run_with() {
    : >"$log"
    SANDBOX_TIMERS_JSON=$1 VOXCMD_CONFIG_DIR=$timers_config "$routed" run "$2" >/dev/null 2>&1
  }
  timers_run_with '[]' "list my timers"
  check "list with nothing running says so" "timers_toast | grep -q 'No timers or reminders\$'"
  timers_run_with "$timers_state_two" "list my timers"
  check "list reads every running timer on one line" "timers_toast | grep -q 'Timer: Pasta, 10 minutes, rings .*; Reminder .*: Call the bank'"
  timers_run_with '[]' "cancel all timers"
  check "cancel all with nothing running says so and stops nothing" "timers_toast | grep -q 'No timers or reminders are running' && ! grep -q '^systemctl --user stop' '$log'"
  timers_run_with "$timers_state_two" "cancel all timers"
  check "cancel all stops every running unit in one call" "grep -Fxq 'systemctl --user stop voxcmd-timer-1000.timer voxcmd-timer-2000.timer' '$log' && timers_toast | grep -q 'Cancelled 2 timers'"

  # Cancel one.
  timers_run_with '[]' "cancel the timer"
  check "a bare cancel with nothing running says so and stops nothing" "timers_toast | grep -q 'No timers or reminders are running' && ! grep -q '^systemctl --user stop' '$log'"
  timers_run_with '[]' "cancel the pasta timer"
  check "a named cancel with nothing running says so too" "timers_toast | grep -q 'No timers or reminders are running' && ! grep -q '^systemctl --user stop' '$log'"
  timers_run_with "$timers_state_one" "cancel the timer"
  check "one running timer is cancelled by a bare cancel" "grep -Fxq 'systemctl --user stop voxcmd-timer-1000.timer' '$log' && timers_toast | grep -q 'Cancelled'"
  timers_run_with "$timers_state_one" "cancel the pasta timer"
  check "one running timer is cancelled by its label" "grep -Fxq 'systemctl --user stop voxcmd-timer-1000.timer' '$log'"
  out=$(SANDBOX_TIMERS_JSON=$timers_state_two VOXCMD_CONFIG_DIR=$timers_config "$routed" explain "cancel the timer" 2>&1)
  check "a bare cancel with two running timers offers both to pick from" "[[ \$(grep -c '^option' <<<\"\$out\") == 2 ]]"
  timers_run_with "$timers_state_two" "cancel the bank reminder"
  check "a named cancel with two running picks the one the words name" "grep -Fxq 'systemctl --user stop voxcmd-timer-2000.timer' '$log' && ! grep -q 'voxcmd-timer-1000' '$log'"
  timers_run_with "$timers_state_one" "cancel the laundry timer"
  check "a name no running timer has reports no match and stops nothing" "timers_toast | grep -q 'No timer or reminder matches \"laundry\"' && ! grep -q '^systemctl --user stop' '$log'"
  # cancel_timer is the action's own guard, run through the hook library as an action does.
  timers_guard() (
    VOXCMD_SHARE_DIR=$share_dir VOXCMD_SELF=$routed
    # shellcheck disable=SC1091
    source "$package/.config/voxcmd/integrations/timers.sh"
    cancel_timer "$1"
  )
  check "a unit that is not a voxcmd timer is refused" "[[ \$(timers_guard other.timer 2>&1) == 'not a voxcmd timer: other.timer' ]] && ! timers_guard other.timer >/dev/null 2>&1"
fi

# ---- Answers: time zones, math and the weather popup --------------------------------------------------------------

section "answers by voice"
answers_config=$root/answers-config
mkdir -p "$answers_config/integrations.d" "$answers_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/answers.sh" "$answers_config/integrations.d/"
copy_shipped_integrations "$answers_config" answers
[ -z "$rust_matcher" ] || check "explain names answers.toml" "VOXCMD_CONFIG_DIR='$answers_config' '$routed' explain 'what time is it' 2>&1 | grep -q 'Answers (answers\\.toml)'"
if [ -n "$rust_matcher" ]; then
  answers_toast() { grep '^notify-send ' "$log" | tail -n1; }
  answers_run() {
    : >"$log"
    VOXCMD_CONFIG_DIR=$answers_config "$routed" run "$1" >/dev/null 2>&1
  }
  answers_explain() { VOXCMD_CONFIG_DIR=$answers_config "$routed" explain "$1" 2>&1; }

  # A name that ends in a tail word keeps the bare name: the verbs' tail takes "thanks", the lazy target stops before it.
  for phrase in "what time is it in tokyo thanks" "how far ahead is tokyo please" "what is the time difference with tokyo thank you"; do
    out=$(answers_explain "$phrase")
    check "'$phrase' captures the bare zone name" "grep -q 'Answers (answers\\.toml) action=zone_' <<<\"\$out\" && grep -q \"target='tokyo'\" <<<\"\$out\""
  done
  answers_run "what time is it in tokyo thanks"
  check "a zone with a trailing tail word is still found" "answers_toast | grep -q 'in Tokyo' && ! answers_toast | grep -q 'No time zone'"
  answers_run "how far ahead is tokyo please"
  check "its offset question is answered too" "answers_toast | grep -Eq 'Tokyo is .* (ahead|behind)|Tokyo is on the same time'"
  answers_run "what time is it in nowhereville"
  check "an unknown zone says so" "answers_toast | grep -q 'No time zone called Nowhereville'"
  answers_run "what is 1 pm eastern in pacific thanks"
  check "a conversion reads the raw transcript and drops its tail word" "answers_toast | grep -Eq 'Eastern.* is .*Pacific'"
  out=$(answers_explain "what is 1 pm eastern in pacific")
  check "a conversion routes to zone_convert, not calculate" "grep -q 'Answers (answers\\.toml) action=zone_convert' <<<\"\$out\""

  # Math reads the raw transcript, which keeps "%" and decimal points.
  answers_run "what's 15 percent of 80 please"
  check "a spoken percentage is calculated and its tail word dropped" "answers_toast | grep -q '15% of 80 = 12'"
  answers_run "what's 2.5% of 40"
  check "a symbol and a decimal point survive to qalc" "answers_toast | grep -q '2.5% of 40 = 1'"
  answers_run "convert 5 miles to kilometers"
  check "a unit conversion is answered" "answers_toast | grep -q 'kilometer\|km'"

  # The weather popup is the answer: no toast, and the popup opens.
  answers_run "what's the weather"
  check "the weather opens its popup and sends no toast" "grep -q '^qs-ipc call popup open weather' '$log' && ! grep -q '^notify-send ' '$log'"
fi

# ---- Firefox: firefox-tab and firefox.sh, on a made-up profile -----------------------------------------------------

section "firefox"
firefox_tab=$share_dir/firefox-tab
firefox_root=$HOME/.config/mozilla/firefox
make_profile() { rm -rf -- "${firefox_root:?}" && "$here/firefox-profile" "$firefox_root"; }
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

make_profile
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

# The tab typed for is in another window or another tab than the focused window's current one (0x3002 shows the Inbox).
inbox_window=$(firefox_window 0x3002)
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_SWITCHED_TITLE="Cart - Example Shop" "$firefox_tab" focus 0x3002 "Cart - Example Shop")
check "focus focuses the window" "grep -q \"^hyprctl dispatch hl.dsp.focus({ window = 'address:0x3002' })\" '$log'"
check "then types Ctrl+L, % and the title, then Down and Return to pick the first open tab" "[[ \"\$(typed | paste -sd'|')\" == '-M ctrl l -m ctrl|-- % Cart - Example Shop|-k Down|-k Return' ]]"
: >"$log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus 0x3002 "Cart - Example Shop") || status=$?
check "a tab switch that doesn't land presses Escape and fails" "[[ \$status != 0 && \$out == *'did not switch'* && \"\$(typed | tail -n 1)\" == '-k Escape' ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_SWITCHED_TITLE="Funny cat video - TubeSite" "$firefox_tab" focus 0x3002 "Funny cat video - TubeSite")
check "a tab of another window is typed for too" "[[ \"\$(typed | paste -sd'|')\" == '-M ctrl l -m ctrl|-- % Funny cat video - TubeSite|-k Down|-k Return' ]]"
: >"$log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus 0x3002 "A tab closed since") || status=$?
check "a title no open tab has is refused" "[[ \$status != 0 && \$out == *'nothing was typed'* ]]"
check "and nothing is typed, as a miss would search the web in the current tab" "[[ -z \$(typed) ]] && grep -q 'hyprctl dispatch' '$log'"
: >"$log"
rm -rf -- "${firefox_root:?}"/*/sessionstore-backups
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus 0x3002 "Cart - Example Shop") || true
check "a store that is gone leaves nothing typed" "[[ -z \$(typed) ]] && [[ \$out == *'nothing was typed'* ]]"
make_profile
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus 0x3002 "Inbox - Mailbox")
check "the tab the window shows is not typed for: the address bar skips it, and a miss would search" "[[ -z \$(typed) ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus 0x3002 "")
check "an empty title only focuses the window" "grep -q 'hyprctl dispatch' '$log' && [[ -z \$(typed) ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus 0x3002 $' \n ')
check "so does one of control characters alone" "[[ -z \$(typed) ]]"
: >"$log"
status=0
out=$("$firefox_tab" focus 0x3002 "Cart - Example Shop") || status=$?
check "nothing is typed when the window does not take focus" "[[ \$status != 0 && -z \$(typed) ]]"
check "and it says so" "[[ \$out == 'the Firefox window did not take focus' ]]"
: >"$log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON=$(firefox_window 0x1003) \
  "$firefox_tab" focus 0x3002 "Cart - Example Shop") || status=$?
check "typing stops when focus leaves Firefox after the first step" "[[ \$status != 0 && \$(typed | wc -l) == 1 ]]"
check "so the title and Return are never typed" "! typed | grep -q 'Cart\\|Return' && [[ \$out == 'focus left Firefox, so the rest was not typed' ]]"
: >"$log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON=$(firefox_window 0x3001) \
  "$firefox_tab" open --here https://example.com/) || status=$?
check "typing also stops when another Firefox window takes focus" "[[ \$status != 0 && \$(typed | wc -l) == 1 ]]"
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_SWITCHED_TITLE="Notes rm -rf ~ [31m - Wiki" "$firefox_tab" focus 0x3002 $'Notes\nrm -rf ~\x1b[31m - Wiki')
check "a title's newline and control characters are typed as spaces" "[[ \"\$(typed | paste -sd'|')\" == '-M ctrl l -m ctrl|-- % Notes rm -rf ~ [31m - Wiki|-k Down|-k Return' ]]"

: >"$log"
status=0
SANDBOX_CLIENTS_JSON='[]' "$firefox_tab" goto --running https://tubesite.example >/dev/null || status=$?
check "goto --running leaves a closed Firefox to the caller" "[[ \$status == 3 ]] && ! grep -q 'dispatch\\|firefox' '$log'"

make_profile
: >"$log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$(firefox_window 0x3001) "$firefox_tab" goto https://tubesite.example)
check "goto focuses the most recent tab on the site" "[[ \"\$(typed | grep '^-- ')\" == '-- % Another cat video - TubeSite' ]]"
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

# ---- Firefox with the extension's host answering: tabs listed live and switched by id -----------------------------

section "firefox live"
live_requests=$root/live-requests.log
fake_host_pid=""
start_fake_host() {
  stop_fake_host
  : >"$live_requests"
  "$here/firefox-fake-host" "$here/fixtures/firefox/live-tabs.json" "$live_requests" "$@" &
  fake_host_pid=$!
  wait_until test -S "$XDG_RUNTIME_DIR/voxcmd/firefox.sock"
}
stop_fake_host() {
  [[ -z $fake_host_pid ]] || kill "$fake_host_pid" 2>/dev/null
  fake_host_pid=""
  rm -f "$XDG_RUNTIME_DIR/voxcmd/firefox.sock"
}
mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
chmod 700 "$XDG_RUNTIME_DIR/voxcmd"
: >"$debug_log"
make_profile
# Two windows show the same tab title; the extension marks the one holding the activated tab with the nonce.
export VOXCMD_FIREFOX_NONCE=vxtest1
marked_clients=$(jq -c 'map(if .address == "0x3001" then .title = "Cart - Example Shop — Mozilla Firefox" elif .address == "0x3002" then .title = "vxtest1 Cart - Example Shop — Mozilla Firefox" else . end)' <<<"$SANDBOX_CLIENTS_JSON")
cart_window=$(jq -c '.[] | select(.address == "0x3002")' <<<"$marked_clients")
reloading_clients=$(jq -c 'map(if .address == "0x3002" then .title = "vxtest1 (3) Cart - Example Shop — Mozilla Firefox" else . end)' <<<"$marked_clients")

start_fake_host
out=$("$firefox_tab" tabs)
check "tabs come from the extension, an unloaded tab among them" "jq -e 'any(.[]; .tab_id == 12 and .title == \"Unloaded Wiki Page\")' <<<\"\$out\" >/dev/null"
check "each live tab is matched to its window as the store's are" "[[ \$(jq -r '[.[] | select(.tab_id == 21) | .address] | join(\" \")' <<<\"\$out\") == 0x3002 ]]"
check "a window the extension does not list is still listed by its title" "jq -e 'any(.[]; .tab_id == null and .address == \"0x3003\")' <<<\"\$out\" >/dev/null"
out=$("$firefox_tab" candidates tabs "wiki" --raw "go to wiki")
check "a candidate carries the tab id and its title" "[[ \$(jq -r '[.[] | select(.match_text == \"Unloaded Wiki Page\") | .id] | join(\"|\")' <<<\"\$out\") == 'tab:12 Unloaded Wiki Page' ]]"
check "candidates are listed by site name too" "jq -e 'any(.[]; .match_text == \"wiki example\" and .id == \"tab:12 Unloaded Wiki Page\")' <<<\"\$out\" >/dev/null"
check "a window with no live tab is a candidate under the old id" "jq -e 'any(.[]; .id == \"0x3003 Private notes\")' <<<\"\$out\" >/dev/null"

check "hidden tabs are left out, as the store's are" "! jq -e 'any(.[]; .tab_id == 31)' <<<\"\$(\"\$firefox_tab\" tabs)\" >/dev/null"
: >"$log"
: >"$live_requests"
out=$(SANDBOX_CLIENTS_JSON=$marked_clients SANDBOX_ACTIVEWINDOW_JSON=$cart_window "$firefox_tab" focus tab:22 "Cart - Example Shop")
check "focus tab:<id> activates the tab through the extension, naming a nonce" "[[ \$(jq -c '[.cmd, .tab_id, .preface]' <<<\"\$(grep activate '$live_requests')\") == '[\"activate\",22,\"vxtest1\"]' ]]"
check "then focuses the window carrying the nonce, not the other one with the same title" "grep -q \"^hyprctl dispatch hl.dsp.focus({ window = 'address:0x3002' })\" '$log' && ! grep -q \"address:0x3001\" '$log'"
check "and gives the title back" "[[ \$(jq -c '[.cmd, .window_id]' <<<\"\$(tail -n 1 '$live_requests')\") == '[\"clear_preface\",2]' ]]"
check "and types nothing" "[[ -z \$(typed) ]]"
: >"$log"
out=$(SANDBOX_CLIENTS_JSON=$reloading_clients SANDBOX_ACTIVEWINDOW_JSON=$cart_window "$firefox_tab" focus tab:22 "Cart - Example Shop")
check "a title that changes while the tab loads does not matter" "grep -q \"address:0x3002\" '$log' && [[ -z \$(typed) ]]"
: >"$log"
out=$(SANDBOX_CLIENTS_JSON=$marked_clients SANDBOX_ACTIVEWINDOW_JSON=$cart_window "$firefox_tab" goto https://shop.example.com/)
check "goto activates the most recent live tab on the site" "[[ \$(grep -c '\"tab_id\": 22' '$live_requests') == 3 ]] && [[ -z \$(typed) ]]"
: >"$log"
status=0
out=$(VOXCMD_FIREFOX_PREFACE_WAIT=0.2 SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus tab:22 "Cart - Example Shop" 2>&1) || status=$?
check "a window that never shows the nonce is no failure once the tab switched" "[[ \$status == 0 && -z \$(typed) ]] && ! grep -q 'dispatch' '$log'"
check "but another Firefox window having focus is said, not taken for the tab's" "[[ \$out == *'could not be focused'* ]]"
status=0
plain_cart_window=$(jq -c '.title = "Cart - Example Shop — Mozilla Firefox"' <<<"$cart_window")
out=$(VOXCMD_FIREFOX_PREFACE_WAIT=0.2 SANDBOX_ACTIVEWINDOW_JSON=$plain_cart_window "$firefox_tab" focus tab:22 "Cart - Example Shop" 2>&1) || status=$?
check "while a focused Firefox window showing the tab counts" "[[ \$status == 0 && \$out != *'could not be focused'* ]]"
status=0
out=$(VOXCMD_FIREFOX_PREFACE_WAIT=0.2 "$firefox_tab" focus tab:22 "Cart - Example Shop" 2>&1) || status=$?
check "but unfocused Firefox is said" "[[ \$status == 0 && \$out == *'could not be focused'* ]]"

start_fake_host silent-activate
: >"$log"
: >"$debug_log"
status=0
out=$(VOXCMD_FIREFOX_HOST_TIMEOUT=0.3 SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_SWITCHED_TITLE="Cart - Example Shop" "$firefox_tab" focus tab:22 "Cart - Example Shop") || status=$?
check "an activation that times out is reported, not retried through the address bar" "[[ \$status != 0 && \$out == *'address bar was not tried'* && -z \$(typed) ]]"
start_fake_host malformed-activate
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus tab:22 "Cart - Example Shop") || status=$?
check "so is a malformed answer to it" "[[ \$status != 0 && \$out == *'malformed'* && -z \$(typed) ]]"
start_fake_host malformed-tabs
out=$("$firefox_tab" tabs)
check "a malformed tab list falls back to the session store" "jq -e 'all(.[]; .tab_id == null) and length > 0' <<<\"\$out\" >/dev/null"

start_fake_host
chmod 775 "$XDG_RUNTIME_DIR/voxcmd"
: >"$debug_log"
out=$("$firefox_tab" tabs)
check "a socket in a directory others can write to is not used" "jq -e 'all(.[]; .tab_id == null)' <<<\"\$out\" >/dev/null && grep -q 'others can write' '$debug_log'"
chmod 755 "$XDG_RUNTIME_DIR/voxcmd"
out=$("$firefox_tab" tabs)
check "one others can only read, as voxcmd creates it, is used" "jq -e 'any(.[]; .tab_id == 22)' <<<\"\$out\" >/dev/null"
chmod 700 "$XDG_RUNTIME_DIR/voxcmd"
out=$(env -u XDG_RUNTIME_DIR "$firefox_tab" tabs)
check "without XDG_RUNTIME_DIR nothing is looked for in /tmp" "jq -e 'all(.[]; .tab_id == null)' <<<\"\$out\" >/dev/null"
out=$("$firefox_tab" tabs)
check "a private directory is used" "jq -e 'any(.[]; .tab_id == 22)' <<<\"\$out\" >/dev/null"

start_fake_host error
: >"$log"
: >"$debug_log"
status=0
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window "$firefox_tab" focus tab:22 "Cart - Example Shop") || status=$?
check "an error answer to an activation is reported, not retried through the address bar" "[[ \$status != 0 && \$out == *'answered with an error: refused'* && -z \$(typed) ]]"
out=$("$firefox_tab" tabs)
check "but an error answer to the tab list falls back to the session store" "jq -e 'all(.[]; .tab_id == null) and any(.[]; .title == \"Cart - Example Shop\")' <<<\"\$out\" >/dev/null"
check "saying why in the debug trace" "grep -q 'answered with an error: refused' '$debug_log'"

stop_fake_host
: >"$log"
: >"$debug_log"
out=$(SANDBOX_ACTIVEWINDOW_JSON=$inbox_window SANDBOX_SWITCHED_TITLE="Cart - Example Shop" "$firefox_tab" focus tab:22 "Cart - Example Shop")
check "with no socket a tab id is looked up by title and switched through the address bar" "[[ \"\$(typed | paste -sd'|')\" == '-M ctrl l -m ctrl|-- % Cart - Example Shop|-k Down|-k Return' ]]"
check "saying why in the debug trace" "grep -q 'is not usable' '$debug_log'"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$XDG_RUNTIME_DIR/voxcmd/firefox.sock"
out=$("$firefox_tab" tabs)
check "a stale socket nobody listens on is no extension either" "jq -e 'all(.[]; .tab_id == null) and length > 0' <<<\"\$out\" >/dev/null"
out=$("$firefox_tab" candidates tabs "cart" --raw "go to cart")
check "and candidates keep the old id form" "[[ \$(jq -r '[.[] | select(.match_text == \"Cart - Example Shop\") | .id] | join(\"|\")' <<<\"\$out\") == '0x3002 Cart - Example Shop' ]]"
rm -f "$XDG_RUNTIME_DIR/voxcmd/firefox.sock" "$debug_log"

firefox_config=$root/firefox-config
mkdir -p "$firefox_config/integrations.d" "$firefox_config/replacements.d"
cp "$package"/.config/voxcmd/integrations.d/{apps,firefox,firefox-sites,keybinds}.sh "$firefox_config/integrations.d/"
copy_shipped_integrations "$firefox_config" apps firefox firefox-sites keybinds
out=$(VOXCMD_CONFIG_DIR=$firefox_config "$routed" explain "go to inbox mailbox" 2>&1)
check "a tab shown in a second window is one tab, not also that window" "[[ \$(grep -c '^option' <<<\"\$out\") == 1 ]] && grep -q 'action=focus_tab' <<<\"\$out\""
out=$(VOXCMD_CONFIG_DIR=$firefox_config "$routed" explain "go to private notes" 2>&1)
check "a private window is found by its title" "grep -q \"action=focus_tab .* id='0x3003 Private notes'\" <<<\"\$out\""
rm -f "$firefox_config/integrations.d/firefox.sh" "$firefox_config/integrations/firefox.toml" "$firefox_config/integrations/firefox.sh"
out=$(VOXCMD_CONFIG_DIR=$firefox_config "$routed" explain "go to inbox mailbox" 2>&1)
check "without firefox.toml, Apps still focuses the window by its title and Firefox no longer answers" "grep -Eq 'Apps \($apps_file\) action=focus' <<<\"\$out\" && ! grep -q 'Firefox (firefox\.toml' <<<\"\$out\""
if [ -n "$rust_matcher" ]; then
  # The hook yields what Apps, Keybinds, Sessions and Keeptabs own; it carries its own copy of Apps' checks. This
  # section's binds are click binds only, so the keybind checks bring their own.
  firefox_binds='[{"description": "Go to Workspace 2", "has_description": true, "submap": "", "key": "2"}]'
  firefox_yields() { SANDBOX_BINDS_JSON=$firefox_binds VOXCMD_SELF=$routed bash -c '. "$1"; "$2" "$3"' _ "$package/.config/voxcmd/integrations/firefox.sh" "$@"; }
  check "firefox yields a described keybind" "firefox_yields spoken_as_keybind 'workspace 2'"
  check "firefox yields a keybind said with a plural and a digit word" "firefox_yields spoken_as_keybind 'workspaces two'"
  # Both only mean something while the binds above are readable, which the positive checks just showed.
  check "firefox does not yield a tab title that is no keybind" "firefox_yields spoken_as_keybind 'workspace 2' && ! firefox_yields spoken_as_keybind 'weekly sync notes'"
  check "firefox yields a session or an agent" "firefox_yields names_session_or_agent 'work session' && firefox_yields names_session_or_agent 'the beta agent'"
  check "firefox does not yield a plain tab" "! firefox_yields names_session_or_agent 'weekly sync notes'"
fi

section "screenshot menu by voice"
# Each phrase runs for real and must hand screenshot.sh the flag of the menu row it names.
screenshot_config=$root/screenshot-config
mkdir -p "$screenshot_config/integrations.d" "$screenshot_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/screenshot.sh" "$screenshot_config/integrations.d/"
copy_shipped_integrations "$screenshot_config" screenshot
screenshot_flags=(
  "screenshot region|--region"
  "take a frozen screenshot|--freeze"
  "screenshot the screen|--screen"
  "screenshot a window|--window"
  "screenshot this window|--focused"
  "grab text from a region|--text"
  "pick a color|--pixel"
  "scroll text|--scroll-text"
  "scrolling screenshot|--scroll-image"
)
for entry in "${screenshot_flags[@]}"; do
  : >"$log"
  VOXCMD_CONFIG_DIR=$screenshot_config "$voxcmd" run "${entry%|*}" >/dev/null 2>&1
  check "'${entry%|*}' runs screenshot.sh ${entry#*|}" "[[ \$(grep -c 'screenshot.sh' '$log') == 1 ]] && grep -Eq 'screenshot.sh ${entry#*|}\$' '$log'"
done

section "keys by voice"
# Each phrase runs for real and must press the keys it names, as many times as it counts, capped at 20.
keys_config=$root/keys-config
mkdir -p "$keys_config/integrations.d" "$keys_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/keys.sh" "$keys_config/integrations.d/"
copy_shipped_integrations "$keys_config" keys
keys_pressed=(
  "press enter|wtype -k Return"
  "send it|wtype -k Return"
  "press down three times|wtype -k Down -k Down -k Down"
  "hit tab twice|wtype -k Tab -k Tab"
  "press up arrow|wtype -k Up"
  "press left three times|wtype -k Left -k Left -k Left"
  "hit right arrow|wtype -k Right"
  "press shift tab|wtype -M shift -k Tab -m shift"
  "press page down once|wtype -k Next"
  "press backspace 2 times|wtype -k BackSpace -k BackSpace"
  "hit escape|wtype -k Escape"
  "press home|wtype -k Home"
  "press end|wtype -k End"
  "press delete twice|wtype -k Delete -k Delete"
  "press space bar|wtype -k space"
  "press Y.|wtype -k y"
  "hit why|wtype -k y"
  "press the letter n|wtype -k n"
  "press a|wtype -k a"
  "press down 50 times|wtype$(printf ' -k Down%.0s' {1..20})"
  "press down 18446744073709551616 times|wtype$(printf ' -k Down%.0s' {1..20})"
)
for entry in "${keys_pressed[@]}"; do
  : >"$log"
  VOXCMD_CONFIG_DIR=$keys_config "$voxcmd" run "${entry%|*}" >/dev/null 2>&1
  check "'${entry%|*}' runs ${entry#*|}" "[[ \$(grep -c '^wtype' '$log') == 1 ]] && grep -Fxq '${entry#*|}' '$log'"
done
: >"$log"
VOXCMD_CONFIG_DIR=$keys_config "$voxcmd" run "press tab banana" >/dev/null 2>&1
check "a count that is none presses nothing" "! grep -q '^wtype' '$log'"

# No client has focus (activewindow is {}): a key goes to an open bar popup that takes the keyboard, or to either
# overview, and to nothing otherwise. Fields: popup state, popup keyboard, overview, tmux overview, expected.
keys_bar_surface_cases=(
  "open weather|yes|||pressed"
  "opening notifications|yes|||pressed"
  "open weather|no|||refused"
  "open weather|no|open||pressed"
  "closing weather|no|||refused"
  "closed|no|||refused"
  "closed|no|open||pressed"
  "closed|no||open|pressed"
)
for entry in "${keys_bar_surface_cases[@]}"; do
  IFS='|' read -r popup_answer keyboard_answer overview_answer tmux_overview_answer expected <<<"$entry"
  : >"$log"
  echo "$popup_answer" >"$SANDBOX_DIR/popup-state"
  echo "${keyboard_answer:-no}" >"$SANDBOX_DIR/popup-keyboard"
  echo "${overview_answer:-closed}" >"$SANDBOX_DIR/overview-state"
  echo "${tmux_overview_answer:-closed}" >"$SANDBOX_DIR/tmux_overview-state"
  SANDBOX_ACTIVEWINDOW_JSON='{}' VOXCMD_CONFIG_DIR=$keys_config "$voxcmd" run "press enter" >/dev/null 2>&1
  case_name="no client, popup '$popup_answer' keyboard ${keyboard_answer:-no} overview '${overview_answer:-closed}' tmux overview '${tmux_overview_answer:-closed}'"
  if [ "$expected" = pressed ]; then
    check "$case_name: enter is pressed" "grep -Fxq 'wtype -k Return' '$log'"
  else
    check "$case_name: enter is refused" "! grep -q '^wtype' '$log' && grep -q 'no window or bar surface has focus' '$log'"
  fi
done
rm -f "$SANDBOX_DIR/popup-state" "$SANDBOX_DIR/popup-keyboard" "$SANDBOX_DIR/overview-state" "$SANDBOX_DIR/tmux_overview-state"

section "devices by voice"
# The volume, mute and default-device actions run for real against the wpctl and bluetoothctl stubs, which log each
# call. Firefox has two streams, so one phrase must reach both; mpv has one.
devices_config=$root/devices-config
mkdir -p "$devices_config/integrations.d" "$devices_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/"{devices,media,system}.sh "$devices_config/integrations.d/"
copy_shipped_integrations "$devices_config" devices media system
devices_pw_dump=$(jq -c '. + [
  {id: 70, type: "PipeWire:Interface:Node", info: {props: {"media.class": "Stream/Output/Audio", "application.name": "Firefox", "application.process.binary": "firefox"}}},
  {id: 71, type: "PipeWire:Interface:Node", info: {props: {"media.class": "Stream/Output/Audio", "application.name": "Firefox", "application.process.binary": "firefox"}}},
  {id: 72, type: "PipeWire:Interface:Node", info: {props: {"media.class": "Stream/Output/Audio", "application.name": "mpv", "application.process.binary": "mpv"}}}]' "$here/fixtures/pw-dump.json")
# Fields: phrase, then the wpctl set calls and bluetoothctl calls it must log, in order, joined by "; ".
devices_calls=(
  "turn firefox down by 20|wpctl set-volume -l 1.0 70 20%-; wpctl set-volume -l 1.0 71 20%-"
  "turn up mpv|wpctl set-volume -l 1.0 72 5%+"
  "mpv volume up|wpctl set-volume -l 1.0 72 5%+"
  "set firefox volume to 30|wpctl set-volume 70 30%; wpctl set-volume 71 30%"
  "set firefox volume to 250 percent|wpctl set-volume 70 100%; wpctl set-volume 71 100%"
  "mute firefox|wpctl set-mute 70 1; wpctl set-mute 71 1"
  "unmute mpv|wpctl set-mute 72 0"
  "switch output to headphones|wpctl set-default 51"
  "use the microphone|wpctl set-default 52"
  "turn bluetooth on|bluetoothctl power on"
  "turn bluetooth off|bluetoothctl power off"
  "connect my headphones|bluetoothctl power on; bluetoothctl connect AA:BB:CC:DD:EE:FF"
  "reconnect my headphones|bluetoothctl power on; bluetoothctl connect AA:BB:CC:DD:EE:FF"
  "disconnect my headphones|bluetoothctl disconnect AA:BB:CC:DD:EE:FF"
)
# One paired device whose name holds a tab, which its candidate row must carry as a space.
export SANDBOX_BT_DEVICES=$'Device AA:BB:CC:DD:EE:FF Head\tphones'
[ -z "$rust_matcher" ] || check "a tab in a device name reaches the candidate as a space" "SANDBOX_PW_DUMP_JSON='$devices_pw_dump' VOXCMD_CONFIG_DIR='$devices_config' '$routed' explain 'connect my headphones' 2>&1 | grep -q \"label='Head phones (Headphones)'\""
for entry in "${devices_calls[@]}"; do
  : >"$log"
  SANDBOX_PW_DUMP_JSON=$devices_pw_dump VOXCMD_CONFIG_DIR=$devices_config "$routed" run "${entry%%|*}" >/dev/null 2>&1
  check "'${entry%%|*}' logs ${entry#*|}" "[[ \$(grep -E '^(wpctl set-|bluetoothctl (power|connect|disconnect))' '$log' | paste -sd'|' | sed 's/|/; /g') == '${entry#*|}' ]]"
done
# An app name that plays nothing and is no command leaves the phrase to Media and System: no per-app call, and their
# own command runs instead. Fields: phrase, then the call that proves who took it.
devices_yields=(
  "set the volume to 20|pamixer --set-volume 20"
  "make the volume 40|pamixer --set-volume 40"
  "turn the volume up|pamixer --increase 5"
  "turn brightness down|brightnessctl -n1 set 10%-"
)
for entry in "${devices_yields[@]}"; do
  : >"$log"
  SANDBOX_PW_DUMP_JSON=$devices_pw_dump VOXCMD_CONFIG_DIR=$devices_config "$routed" run "${entry%%|*}" >/dev/null 2>&1
  check "'${entry%%|*}' is left to Media or System: ${entry#*|}" "! grep -q '^wpctl set-' '$log' && grep -Fxq '${entry#*|}' '$log'"
done
# A command that plays nothing is reported, not silently unmatched: bash is on PATH but has no stream.
: >"$log"
SANDBOX_PW_DUMP_JSON=$devices_pw_dump VOXCMD_CONFIG_DIR=$devices_config "$routed" run "mute bash" >/dev/null 2>&1
check "an app that is not playing is reported" "grep -q 'bash (not playing)\|not playing anything' '$log' && ! grep -q '^wpctl set-' '$log'"
unset SANDBOX_BT_DEVICES

section "screenshot.sh beside a recording"
# The real script, with the sandbox's stub for qs-ipc beside it and a pidof that names a harmless process as the recorder.
recorder_work=$root/recorder-work
mkdir -p "$recorder_work/bin"
cp "$package/../hypr/.config/hypr/scripts/screenshot.sh" "$recorder_work/screenshot.sh"
ln -s "$(dirname "$(command -v wl-copy)")/.stub" "$recorder_work/qs-ipc"
# A background job of a script ignores SIGINT, which python restores.
python3 -c 'import signal, time; signal.signal(signal.SIGINT, signal.default_int_handler); time.sleep(300)' 2>/dev/null &
fake_recorder=$!
printf '#!/bin/sh\necho %s\n' "$fake_recorder" >"$recorder_work/bin/pidof"
chmod +x "$recorder_work/bin/pidof"
: >"$log"
PATH=$recorder_work/bin:$PATH "$recorder_work/screenshot.sh" --region >/dev/null 2>&1
check "a capture flag leaves a running recording alone and takes its shot" "kill -0 $fake_recorder && grep -q 'qs-ipc call screenshot select false toolbar' '$log'"
PATH=$recorder_work/bin:$PATH "$recorder_work/screenshot.sh" --scroll-image >/dev/null 2>&1
check "so does a scroll capture" "kill -0 $fake_recorder && grep -q 'qs-ipc call screenshot select false scroll_image' '$log'"
: >"$log"
PATH=$recorder_work/bin:$PATH "$recorder_work/screenshot.sh" >/dev/null 2>&1
# The sleep is this shell's child, so a stopped one stays a zombie until reaped, which wait_until_gone counts as gone.
check "the menu key still stops it" "wait_until_gone $fake_recorder"
check "and opens no bar menu" "! grep -q 'qs-ipc call screenshot open' '$log'"
kill "$fake_recorder" 2>/dev/null
# A record flag stops a running recording too; the stop exits before any recorder starts, so the sandbox runs none.
# Until python has set its SIGINT handler, the background job's inherited ignore swallows the signal, so wait for the file.
rm -f "$recorder_work/record-ready"
python3 -c 'import signal, sys, time; signal.signal(signal.SIGINT, signal.default_int_handler); open(sys.argv[1], "w").close(); time.sleep(300)' "$recorder_work/record-ready" 2>/dev/null &
record_recorder=$!
wait_for_path "$recorder_work/record-ready"
printf '#!/bin/sh\necho %s\n' "$record_recorder" >"$recorder_work/bin/pidof"
# The sandbox's activewindow is {} by default, which cancels the record before wf-recorder; a window lets a fall-through reach it.
: >"$log"
SANDBOX_ACTIVEWINDOW_JSON='{"at":[10,20],"size":[300,200]}' PATH=$recorder_work/bin:$PATH "$recorder_work/screenshot.sh" --record-focused >/dev/null 2>&1
check "a record flag stops a running recording" "wait_until_gone $record_recorder"
check "and starts no new one" "! grep -q '^wf-recorder' '$log'"
kill "$record_recorder" 2>/dev/null

section "near misses"
# A last tier for a phrase nothing else could use: a verb whose words are all there in another order is offered as a weak
# pick. The stub integration's verbs stand for any integration's: a target verb, a verb with no placeholder, one with a
# digit slot and twelve verbs of the same words, for the cap.
near_config=$root/config-near
mkdir -p "$near_config/integrations.d" "$near_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/apps.sh" "$package/.config/voxcmd/integrations.d/devices.sh" "$package/.config/voxcmd/integrations.d/sessions.sh" "$near_config/integrations.d/"
copy_shipped_integrations "$near_config" apps sessions
near_actions=$root/near-actions.log
{
  cat <<'STUB'
name="Near"
verbs=(
  "raise raise the (blinds|shades) {target}"
  "lock lock all doors"
  "dim dim the lights"
  "level set the level to {number}"
  "zoom zoom {target}"
STUB
  for number in $(seq 1 12); do printf '  "note%s note {target}"\n' "$number"; done
  echo ')'
  printf 'declare -A actions=([raise]=%s [lock]=%s [dim]=%s [level]=%s [zoom]=%s' "'echo \"raise \$id\" >> $near_actions'" "'echo lock >> $near_actions'" "'echo dim >> $near_actions'" "'echo level >> $near_actions'" "'echo zoom >> $near_actions'"
  for number in $(seq 1 12); do printf ' [note%s]=%s' "$number" "'echo note$number >> $near_actions'"; done
  echo ')'
} >"$near_config/integrations.d/near.sh"
near_dry() { VOXCMD_CONFIG_DIR=$near_config "$voxcmd" explain "$1" 2>&1; }
near_live() { VOXCMD_CONFIG_DIR=$near_config "$pkg_voxcmd" run "$1" >/dev/null 2>&1; }
near_miss_log=$XDG_STATE_HOME/voxcmd/no-match.log
rm -f "$near_miss_log"

out=$(near_dry "kitchen blinds raise")
check "a reordered phrase is a near miss, never a run" "grep -q 'result:      ask with the picker (1 options' <<<\"\$out\" && grep -q 'Near (near.sh) \[near miss\] action=raise target=.kitchen.' <<<\"\$out\""
check "it is a weak match, so a spoken one listens for the reply" "grep -q 'weak: true' <<<\"\$out\" && grep -q 'listens for the reply when spoken' <<<\"\$out\""
out=$(near_dry "raise the blinds kitchen")
check "a phrase that matches as spoken is no near miss" "grep -q 'result:      run' <<<\"\$out\" && ! grep -q 'near miss' <<<\"\$out\""
out=$(near_dry "doors lock all please")
check "a verb without a placeholder takes the filler 'please' left over" "grep -q 'action=lock ' <<<\"\$out\" && grep -q '\[near miss\]' <<<\"\$out\""
out=$(near_dry "lock all doors please now maybe")
check "stray speech beside the verb's words stays no match" "grep -q 'result:      no match' <<<\"\$out\""
out=$(near_dry "lock doors")
check "a missing word stays no match" "grep -q 'result:      no match' <<<\"\$out\""
out=$(near_dry "blinds raise")
check "a target verb with nothing left for the target stays no match" "grep -q 'result:      no match' <<<\"\$out\""
out=$(near_dry "level 40 the set to")
check "a digit slot takes a digit word" "grep -q 'action=level ' <<<\"\$out\""
out=$(near_dry "level forty set the to")
check "a digit slot does not take a number word" "grep -q 'result:      no match' <<<\"\$out\""
out=$(near_dry "foo note")
check "at most ten options are offered" "grep -q 'ask with the picker (10 options' <<<\"\$out\""
out=$(near_dry "big zoom view")
check "a target split by a slot's word stays no match" "grep -q 'result:      no match' <<<\"\$out\""
out=$(near_dry "view big zoom")
check "a target in one run is a near miss" "grep -q 'action=zoom target=.view big.' <<<\"\$out\""
out=$(printf 'focus\t(go to|take me to|focus) tab {target}\n' | NEAR_MISS_PHRASE="tab focus firefox take me to" awk -f "$package/.local/share/voxcmd/near-miss.awk")
check "of two alternatives that fit, the one leaving fewer words wins" "[[ \$out == \$'focus\\tfocus firefox\\ttrue\\t3' ]]"
out=$(near_dry "open session notes")
check "a target naming no candidate offers no 'not found' report" "grep -q 'result:      no match' <<<\"\$out\""
# near_dry runs the bash voxcmd, which can only load apps.sh
out=$(near_dry "firefox open")
check "other integrations' verbs reorder too: Apps" "grep -Eq 'Apps \(apps\.sh\) \[near miss\] action=open target=.firefox.' <<<\"\$out\""
out=$(near_dry "bluetooth turn on")
check "other integrations' verbs reorder too: Devices" "grep -q 'Devices (devices.sh) \[near miss\] action=bluetooth_on' <<<\"\$out\""
out=$(near_dry "force.. kitchen blinds raise")
check "a phrase that no prefix forces is still a near miss" "grep -q 'near miss' <<<\"\$out\""

: >"$log"
: >"$near_actions"
near_live "kitchen blinds raise"
check "a near miss opens the picker" "grep -q '^voxcmd-pick Which command?' '$log'"
check "and runs the option only once it is picked" "[[ \$(cat '$near_actions') == 'raise kitchen' ]]"
: >"$log"
: >"$near_actions"
near_live "kitchen blinds raise no wait lock all doors"
check "a correction retry that matches wins over the whole phrase's near miss" "[[ \$(cat '$near_actions') == lock ]] && ! grep -q '^voxcmd-pick' '$log'"
out=$(near_dry "kitchen blinds raise no wait lock all doors")
check "the dry run shows the retry, not the near miss" "grep -q '^corrected:' <<<\"\$out\" && ! grep -q 'near miss' <<<\"\$out\""
: >"$near_actions"
near_live "blinds raise kitchen no wait lock doors"
check "a retry that is itself no match leaves the whole phrase's near miss" "[[ \$(cat '$near_actions') == 'raise kitchen no wait lock doors' ]]"

: >"$log"
check "a near miss reached no log line" "[[ ! -e '$near_miss_log' ]]"
near_live "lock all doors please now maybe"
check "a phrase that still matches nothing is logged" "[[ \$(wc -l <'$near_miss_log') == 1 ]] && grep -qP '^\\d{4}-\\d\\d-\\d\\dT[0-9:+-]+\\tlock all doors please now maybe\$' '$near_miss_log'"
check "stray speech picked nothing" "! grep -q '^voxcmd-pick' '$log'"
near_live "Lock  Doors!"
check "the logged phrase is the normalized one" "tail -n 1 '$near_miss_log' | grep -qP '\\tlock doors\$'"
VOXCMD_CONFIG_DIR=$near_config "$voxcmd" explain "nothing matches this at all" >/dev/null 2>&1
check "a dry run logs nothing" "[[ \$(wc -l <'$near_miss_log') == 2 ]]"
out=$(VOXCMD_CONFIG_DIR=$near_config "$pkg_voxcmd" log misses 1)
check "voxcmd misses prints the last lines" "grep -qP '\\tlock doors\$' <<<\"\$out\" && [[ \$(wc -l <<<\"\$out\") == 1 ]]"
if [ "${VOXCMD_BIN:-bash}" = rs ]; then
  # The bash voxcmd also answers `misses`, so show the Rust build did: `voxcmd` is the release binary and the logger in
  # front of the bash voxcmd saw no call.
  check "voxcmd is the Rust build" "[[ \$(readlink -f '$pkg_voxcmd') == '$package/target/release/voxcmd' ]]"
  : >"$legacy_calls"
  VOXCMD_LEGACY_BIN=$root/legacy-logger "$pkg_voxcmd" log misses 1 >/dev/null
  check "and the bash voxcmd was not asked for the log" "[[ ! -s '$legacy_calls' ]]"
fi
near_live $'lock doors\nquickly'
check "a transcript over two lines is one record" "[[ \$(wc -l <'$near_miss_log') == 3 ]] && tail -n 1 '$near_miss_log' | grep -qP '\\tlock doors\$'"

mkdir -p "$XDG_RUNTIME_DIR/voxtype" "$XDG_RUNTIME_DIR/voxcmd"
near_watch() {
  echo recording >"$XDG_RUNTIME_DIR/voxtype/state"
  echo "$1" >"$XDG_RUNTIME_DIR/voxcmd/transcript.txt"
  : >"$debug_log"
  (
    wait_for_line 'watch: voxtype recording' "$debug_log"
    echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  ) &
  VOXCMD_DEBUG=1 VOXCMD_CONFIG_DIR=$near_config "$pkg_voxcmd" internal watch route "${2:--}" "${3:-0}" >/dev/null 2>&1
  wait
  rm -f "$debug_log" "$XDG_RUNTIME_DIR/voxtype/state"
}
near_watch "secret words nobody routes" - 1
check "a transcript heard in a private mode is not logged" "! grep -q secret '$near_miss_log'"
near_watch "public words nobody routes" - 0
check "the same heard in an ordinary mode is" "grep -q 'public words nobody routes' '$near_miss_log'"

rm -f "$near_miss_log"
{
  for line in $(seq 1 1100); do printf '2026-01-01T00:00:00+00:00\told %s\n' "$line"; done
} >"$near_miss_log"
near_live "one more stray phrase"
check "the log keeps its last 1000 lines" "[[ \$(wc -l <'$near_miss_log') == 1000 ]] && tail -n 1 '$near_miss_log' | grep -q 'one more stray phrase'"

section "sessions.sh launches by name"
sessions_config=$root/sessions-config
mkdir -p "$sessions_config/integrations.d" "$sessions_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/sessions.sh" "$package/.config/voxcmd/integrations.d/tmux.sh" "$sessions_config/integrations.d/"
copy_shipped_integrations "$sessions_config" sessions tmux
export SANDBOX_LAUNCHER_SESSIONS=$'work\n🌐 Browsing'
: >"$log"
VOXCMD_CONFIG_DIR=$sessions_config "$voxcmd" run "open the browsing session" >/dev/null 2>&1
check "a session is launched by its exact name" "grep -Fq '.launch(\"🌐 Browsing\")' '$log'"
: >"$log"
VOXCMD_CONFIG_DIR=$sessions_config "$voxcmd" run "open the nowhere session" >/dev/null 2>&1
check "an unknown name launches nothing, but still asks Hyprland for the names" "grep -q 'write_names' '$log' && ! grep -Fq '.launch(' '$log'"
: >"$log"
VOXCMD_CONFIG_DIR=$sessions_config "$voxcmd" run "open the work tmux session" >/dev/null 2>&1
check "a tmux phrase launches no launcher session" "! grep -Fq '.launch(' '$log'"
# Sessions' "skip" verb offers nothing, so the phrase passes on to Tmux rather than stopping at Sessions.
check "Sessions yields a tmux phrase to Tmux" "VOXCMD_CONFIG_DIR='$sessions_config' '$voxcmd' explain 'open the work tmux session' 2>&1 | grep -q '^option 1: *Tmux'"
unset SANDBOX_LAUNCHER_SESSIONS

section "keeptabs.toml jumps to agents"
# Three agents in keeptabs-pick's order (waiting, done, then idle), with a stub keeptabs-pick of our own first on PATH:
# it lists SANDBOX_AGENTS_JSON, logs --focus calls, and sits beside a lib.sh whose session_focused is true for the pids
# in KEEPTABS_FOCUSED_PIDS, as keeptabs' own lib.sh decides which agents the user is looking at.
keeptabs_config=$root/keeptabs-config
keeptabs_stub=$root/keeptabs-stub
mkdir -p "$keeptabs_config/integrations.d" "$keeptabs_config/replacements.d" "$keeptabs_stub/bin" "$keeptabs_stub/share/keeptabs"
cp "$package/.config/voxcmd/integrations.d/keeptabs.sh" "$keeptabs_config/integrations.d/"
copy_shipped_integrations "$keeptabs_config" keeptabs
# shellcheck disable=SC2016 # the stub expands its own variables
printf '#!/bin/sh\ncase "$*" in\n*--json*) printf "%%s" "$SANDBOX_AGENTS_JSON" ;;\n*) echo "keeptabs-pick $*" >> "%s" ;;\nesac\n' "$log" >"$keeptabs_stub/bin/keeptabs-pick"
chmod +x "$keeptabs_stub/bin/keeptabs-pick"
# shellcheck disable=SC2016 # lib.sh is sourced by the hook, which expands it
printf 'session_focused() {\n  printf "%%s|%%s|%%s|%%s\\n" "$1" "$2" "$3" "$4" >> "%s"\n  case " $KEEPTABS_FOCUSED_PIDS " in *" $1 "*) return 0 ;; esac\n  return 1\n}\n' "$keeptabs_stub/focus-args" >"$keeptabs_stub/share/keeptabs/lib.sh"
# shellcheck disable=SC2089,SC2090 # the \t is JSON's escape, meant literally
SANDBOX_AGENTS_JSON='[{"id":"w","title":"Wait","project":"pw","state":"waiting","pid":1,"tmux_socket":"sock","tmux_pane":"%1","nvim":"nv"},{"id":"d","title":"Fin","project":"pd","state":"done","pid":2},{"id":"i","title":"Idle one","project":"pi","state":"idle","pid":3},{"id":"j","title":"Idle\ttwo","project":"pj","state":"idle","pid":4}]'
# shellcheck disable=SC2090 # see above
export SANDBOX_AGENTS_JSON
keeptabs_say() {
  : >"$log"
  PATH="$keeptabs_stub/bin:$PATH" VOXCMD_CONFIG_DIR=$keeptabs_config "$routed" run "$1" >/dev/null 2>&1
}
keeptabs_say "go to the waiting agent"
check "the waiting agent is focused and named in a toast" "grep -q '^keeptabs-pick --focus w\$' '$log' && grep -q '^notify-send .*Wait (pw)\$' '$log'"
keeptabs_say "go to the done agent"
check "the done agent is focused silently" "grep -q '^keeptabs-pick --focus d\$' '$log' && ! grep -q '^notify-send' '$log'"
keeptabs_say "go to the beta agent"
check "an unknown agent name focuses nothing and fails loudly" "! grep -q -- '--focus' '$log' && grep -q '^notify-send .*no tracked agent matches \"beta\"' '$log'"
keeptabs_say "go to the idle one agent"
check "a named agent is focused silently, matched on its title" "grep -q '^keeptabs-pick --focus i\$' '$log' && ! grep -q '^notify-send' '$log'"
keeptabs_say "go to the agent that needs me"
check "the spoken alternative of the waiting jump works too" "grep -q '^keeptabs-pick --focus w\$' '$log'"
keeptabs_say "next agent"
check "next with none focused starts at the first agent" "grep -q '^keeptabs-pick --focus w\$' '$log'"
keeptabs_say "go to the previous agent"
check "previous with none focused starts at the last agent" "grep -q '^keeptabs-pick --focus j\$' '$log'"
: >"$log"
KEEPTABS_FOCUSED_PIDS="4" PATH="$keeptabs_stub/bin:$PATH" VOXCMD_CONFIG_DIR=$keeptabs_config "$routed" run "next agent" >/dev/null 2>&1
check "next from the last agent wraps to the first" "grep -q '^keeptabs-pick --focus w\$' '$log'"
: >"$log"
KEEPTABS_FOCUSED_PIDS="2" PATH="$keeptabs_stub/bin:$PATH" VOXCMD_CONFIG_DIR=$keeptabs_config "$routed" run "previous agent" >/dev/null 2>&1
check "previous steps back one agent" "grep -q '^keeptabs-pick --focus w\$' '$log'"
check "session_focused gets pid, socket, pane and nvim, empty fields kept in place" "[[ \$(sort -u '$keeptabs_stub/focus-args' | tr '\\n' ' ') == '1|sock|%1|nv 2||| 3||| 4||| ' ]]"
check "a failing jump exits non-zero and a good one zero" "! PATH='$keeptabs_stub/bin:'\$PATH VOXCMD_CONFIG_DIR='$keeptabs_config' '$routed' run 'go to the beta agent' >/dev/null 2>&1 && PATH='$keeptabs_stub/bin:'\$PATH VOXCMD_CONFIG_DIR='$keeptabs_config' '$routed' run 'go to the waiting agent' >/dev/null 2>&1"
: >"$log"
KEEPTABS_FOCUSED_PIDS="2 3" PATH="$keeptabs_stub/bin:$PATH" VOXCMD_CONFIG_DIR=$keeptabs_config "$routed" run "next agent" >/dev/null 2>&1
check "next steps over agents that share the focused pane" "grep -q '^keeptabs-pick --focus j\$' '$log'"
: >"$log"
KEEPTABS_FOCUSED_PIDS="1 2 3 4" PATH="$keeptabs_stub/bin:$PATH" VOXCMD_CONFIG_DIR=$keeptabs_config "$routed" run "next agent" >/dev/null 2>&1
check "with every agent focused it says so and moves nothing" "! grep -q -- '--focus' '$log' && grep -q '^notify-send .*no other agent to go to' '$log'"
SANDBOX_AGENTS_JSON='[{"id":"i","title":"Idle","project":"pi","state":"idle","pid":3}]' keeptabs_say "go to the waiting agent"
check "no waiting agent toasts that and focuses nothing" "! grep -q -- '--focus' '$log' && grep -q '^notify-send .*no agent is waiting' '$log'"
SANDBOX_AGENTS_JSON='[{"id":"i","title":"Idle","project":"pi","state":"idle","pid":3}]' keeptabs_say "next done agent"
check "no done agent toasts that despite the silent action" "! grep -q -- '--focus' '$log' && grep -q '^notify-send .*no agent is done' '$log'"
SANDBOX_AGENTS_JSON='[]' keeptabs_say "next agent"
check "no tracked agents toasts that" "grep -q '^notify-send .*no agents are tracked' '$log'"
keeptabs_say "go to the idle two agent"
check "a tab in a title is blanked, so the agent still matches by its title" "grep -q '^keeptabs-pick --focus j\$' '$log'"
unset SANDBOX_AGENTS_JSON

section "apps by voice"
# Apps runs for real against the sandbox's hyprctl and notify-send stubs, over the fixture desktop: kitty is focused
# (700x1000, workspace 1), Firefox is beside it, Slack is on workspace 2.
apps_config=$root/apps-config
mkdir -p "$apps_config/integrations.d" "$apps_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/apps.sh" "$apps_config/integrations.d/"
copy_shipped_integrations "$apps_config" apps
if [ -n "$rust_matcher" ]; then
  apps_fixtures=$package/tests/fixtures
  apps_env=(XDG_DATA_HOME="$apps_fixtures" XDG_DATA_DIRS="$apps_fixtures" VOXCMD_CONFIG_DIR="$apps_config"
    SANDBOX_CLIENTS_JSON="$(cat "$apps_fixtures/clients.json")" SANDBOX_MONITORS_JSON="$(cat "$apps_fixtures/monitors.json")"
    SANDBOX_ACTIVEWINDOW_JSON="$(jq -c '.[] | select(.focusHistoryID == 0)' "$apps_fixtures/clients.json")"
    SANDBOX_BINDS_JSON="$(cat "$apps_fixtures/binds.json")")
  apps_run() {
    : >"$log"
    env "${apps_env[@]}" "$routed" run "$1" >/dev/null 2>&1
  }
  apps_dispatches() { sed -n 's/^hyprctl dispatch //p' "$log"; }
  apps_explain() { env "${apps_env[@]}" "$routed" explain "$1" 2>&1; }
  # shellcheck disable=SC2016 # the single quotes are bash -c's own script, expanded by the child
  apps_help() { env "${apps_env[@]}" VOXCMD_SHARE_DIR="$package/.local/share/voxcmd" bash -c '. "$1"; help_apps' _ "$apps_config/integrations/apps.sh"; }
  out=$(apps_explain "close slack")
  check "explain names apps.toml" "grep -q 'Apps (apps\\.toml)' <<<\"\$out\""
  check "closing a window asks first" "grep -q 'confirm: true' <<<\"\$out\" && grep -q \"id='0x1002'\" <<<\"\$out\""
  out=$(apps_explain "open play the song thanks")
  check "a target ending in a tail word stays whole" "grep -q 'Apps (apps.toml, normal): matched verb .* action=open target=play the song thanks' <<<\"\$out\""

  # The candidate hooks decide what Apps offers; the veto checks show what it leaves to the keybinds.
  out=$(apps_explain "open firefox")
  check "open offers the installed app by its desktop entry" "grep -q \"action=open target='firefox' id='firefox.desktop'\" <<<\"\$out\""
  out=$(apps_explain "move firefox to workspace 3")
  check "move offers the window and the workspace as one id" "grep -q \"action=move .* id='0x1001 3'\" <<<\"\$out\""
  out=$(apps_explain "switch firefox to workspace 4")
  check "move_with_window offers the same pair, under its own action" "grep -q \"action=move_with_window .* id='0x1001 4'\" <<<\"\$out\""
  out=$(apps_explain "open terminal")
  check "a phrase that names a keybind is left to the keybinds: Apps offers nothing" "grep -q 'result: *no match' <<<\"\$out\" && grep -q 'hook Apps open: 0 line' <<<\"\$out\""

  apps_run "resize the window to 1200 by 800"
  check "a resize to an exact size moves the width first, by the difference" "[[ \$(apps_dispatches | head -n1) == \"hl.dsp.window.resize({ window = 'address:0x1003', x = 500, y = 0, relative = true })\" ]]"
  apps_run "1200 by 800"
  check "a size said alone, read from the transcript, resizes the active window" "[[ \$(apps_dispatches | head -n1) == \"hl.dsp.window.resize({ window = 'address:0x1003', x = 500, y = 0, relative = true })\" ]]"
  apps_run "make it wider"
  check "a direction with no amount says how much, and resizes nothing" "grep -q '^notify-send .*Say how much' '$log' && [[ -z \$(apps_dispatches) ]]"
  apps_run "swap this window with firefox"
  check "swap names the focused window as the source" "[[ \$(apps_dispatches) == \"hl.dsp.window.swap({ window = 'address:0x1003', target = 'address:0x1001' })\" ]]"
  apps_run "swap this window with slack"
  check "and refuses a window on another workspace" "[[ -z \$(apps_dispatches) ]] && grep -q 'another workspace' '$log'"
  apps_run "focus firefox"
  check "focus dispatches the window's address" "[[ \$(apps_dispatches) == \"hl.dsp.focus({ window = 'address:0x1001' })\" ]]"
  check "Tab in Voice Help lists every installed app once, by name" "[[ \$(apps_help | cut -f2 | paste -sd,) == 'Calendar,Firefox,kitty,Slack' ]]"
fi

section "voice help"
# Voice Help lists every integration's examples, the fallbacks last, and Tab on one lists what it offers to run. The
# package copy's voxcmd-pick answers what $help_answer holds and logs its arguments; no such file makes it exit 1, as a
# cancelled pick does, and an empty one answers nothing with exit 0.
help_pkg=$root/help-pkg
mkdir -p "$help_pkg"
cp -r "$package/.local" "$help_pkg/.local"
link_voxcmd_shim "$help_pkg"
help_voxcmd=$help_pkg/tests/bin/voxcmd
help_answer=$root/help-answer
rm -f "$help_pkg/.local/bin/voxcmd-pick"
# shellcheck disable=SC2016 # the stub expands its own arguments
printf '#!/bin/sh\necho "voxcmd-pick $*" >> "%s"\n[ -f "%s" ] || exit 1\ncat "%s"\n' "$log" "$help_answer" "$help_answer" >"$help_pkg/.local/bin/voxcmd-pick"
chmod +x "$help_pkg/.local/bin/voxcmd-pick"
export VOXCMD_LEGACY_BIN=$help_pkg/.local/bin/voxcmd
[ -z "$rust_matcher" ] || check "the Rust build is what runs under rs" "[[ \$(readlink -f '$help_voxcmd') == '$package/target/release/voxcmd' ]]"
help_actions=$root/help-actions.log
help_config=$root/config-help
mkdir -p "$help_config/integrations.d" "$help_config/replacements.d"
cat >"$help_config/integrations.d/lamp.sh" <<STUB
name="Lamp"
verbs=("on lamp on")
examples=("lamp on" "lamp dim to <level>")
declare -A actions=([on]='echo lit >> $help_actions' [set]='echo "set \$id" >> $help_actions')
help_action=set
candidates() { printf '[{"id":"low","label":"Low"},{"id":"high","label":"High"}]'; }
STUB
cat >"$help_config/integrations.d/aaa-fallback.sh" <<STUB
name="Zed"
fallback=1
verbs=("any anything at all")
examples=("fallback phrase")
declare -A actions=([any]='true')
STUB
help_run() {
  printf '%s' "$1" >"$help_answer"
  : >"$log"
  : >"$help_actions"
  VOXCMD_CONFIG_DIR=$help_config "$help_voxcmd" help >/dev/null 2>&1
  help_status=$?
}

help_run "say:lamp on"
check "a picked example runs as if spoken" "[[ \$(cat '$help_actions') == lit && \$help_status == 0 ]]"
check "the picker is Voice Help over every example, the fallback after the others" "grep -Eq '^voxcmd-pick Voice Help .*\"label\":\"Lamp: lamp on\".*\"label\":\"Zed: fallback phrase\"' '$log'"
check "an integration with runnables gets a Tab expansion, one without none" "[[ \$(grep -o '\"expand\":\"[a-z]*\"' '$log' | sort -u) == '\"expand\":\"lamp\"' ]]"
check "the expansion lists the help_action's candidates as run ids" "grep -q '\"lamp\":{\"choices\":\[{\"id\":\"run:0\",\"label\":\"Low\"},{\"id\":\"run:1\",\"label\":\"High\"}\],\"title\":\"Lamp\"}' '$log' || grep -q '\"lamp\":{\"title\":\"Lamp\",\"choices\":\[{\"id\":\"run:0\",\"label\":\"Low\"},{\"id\":\"run:1\",\"label\":\"High\"}\]}' '$log'"
help_run "say:lamp dim to <level>"
check "a placeholder example is a toast to say, markup escaped, and runs nothing" "grep -q '^notify-send .*voxcmd Say: lamp dim to &lt;level&gt;\$' '$log' && [[ ! -s '$help_actions' && \$help_status == 0 ]]"
help_run "run:1"
check "a runnable runs its action on that entry" "[[ \$(cat '$help_actions') == 'set high' && \$help_status == 0 ]]"
rm -f "$help_answer"
: >"$log"
: >"$help_actions"
VOXCMD_CONFIG_DIR=$help_config "$help_voxcmd" help >/dev/null 2>&1
help_status=$?
check "a cancelled picker runs nothing and is not a failure" "[[ ! -s '$help_actions' && \$help_status == 0 ]] && ! grep -q '^notify-send' '$log'"
# The bash routes an empty phrase; the Rust build cancels, on purpose.
help_run ""
[ -z "$rust_matcher" ] || check "an empty answer with exit 0 cancels the same way" "[[ ! -s '$help_actions' && \$help_status == 0 ]] && ! grep -q '^notify-send' '$log'"
rm -f "$help_config/integrations.d/aaa-fallback.sh"
printf 'name="Lamp"\nverbs=("on lamp on")\ndeclare -A actions=([on]=true)\n' >"$help_config/integrations.d/lamp.sh"
help_run "say:lamp on"
check "with no examples declared it toasts, asks nothing and exits 1" "grep -q '^notify-send .*voxcmd No integration declares examples\$' '$log' && ! grep -q '^voxcmd-pick' '$log' && [[ \$help_status == 1 ]]"
if [ -n "$rust_matcher" ]; then
  # The shipped keybinds.toml, against binds of its own: a Delete submap, a Delete Line bind for the delete confirm
  # regex, and a password bind that must never be offered.
  keybinds_help_config=$root/config-help-keybinds
  mkdir -p "$keybinds_help_config/integrations.d" "$keybinds_help_config/replacements.d"
  copy_shipped_integrations "$keybinds_help_config" keybinds
  keybinds_help_binds='[
    {"description": "Delete Line", "submap": "", "dispatcher": "__lua", "has_description": true, "mouse": false, "key": "D", "arg": "601"},
    {"description": "Show Password", "submap": "", "dispatcher": "__lua", "has_description": true, "mouse": false, "key": "P", "arg": "602"},
    {"description": "Open Notes", "submap": "", "dispatcher": "__lua", "has_description": true, "mouse": false, "key": "N", "arg": "603"},
    {"description": "Wipe", "submap": "Delete", "dispatcher": "__lua", "has_description": true, "mouse": false, "key": "W", "arg": "604"}]'
  rm -f "$help_answer"
  : >"$log"
  SANDBOX_BINDS_JSON=$keybinds_help_binds VOXCMD_CONFIG_DIR=$keybinds_help_config "$help_voxcmd" help >/dev/null 2>&1
  check "Keybinds' Tab lists the submaps, then Exit submap, then the binds" "grep -qF '\"choices\":[{\"id\":\"run:0\",\"label\":\"Submap: Delete\"},{\"id\":\"run:1\",\"label\":\"Exit submap\"},{\"id\":\"run:2\",\"label\":\"Delete Line\"},{\"id\":\"run:3\",\"label\":\"Open Notes\"},{\"id\":\"run:4\",\"label\":\"Wipe (Delete)\"}]' '$log'"
  check "a password bind is never offered" "! grep -qi 'password' '$log'"
  out=$(SANDBOX_BINDS_JSON=$keybinds_help_binds VOXCMD_CONFIG_DIR=$keybinds_help_config "$help_voxcmd" explain "show password" 2>&1)
  check "and saying its description runs nothing" "grep -q '^result: *no match' <<<\"\$out\""
  out=$(SANDBOX_BINDS_JSON=$keybinds_help_binds VOXCMD_CONFIG_DIR=$keybinds_help_config "$help_voxcmd" explain "delete line" 2>&1)
  check "a bind named Delete asks before it runs" "grep -q 'id=.601.' <<<\"\$out\" && grep -q 'confirm: true' <<<\"\$out\""
  out=$(SANDBOX_BINDS_JSON=$keybinds_help_binds VOXCMD_CONFIG_DIR=$keybinds_help_config "$help_voxcmd" explain "delete submap" 2>&1)
  check "entering the Delete submap does not" "grep -q 'id=.submap:Delete.' <<<\"\$out\" && grep -q 'confirm: false' <<<\"\$out\""
fi
unset VOXCMD_LEGACY_BIN

finish
