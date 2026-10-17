#!/usr/bin/env bash
# Writes the golden files the Rust tests compare `voxcmd ask` and `voxcmd reply` against: what the bash helpers and the
# bash voxcmd's reply did for a corpus of questions and answers. Run it by hand when the corpus changes, never from a
# check, and commit the outputs; `cargo test` reads them and needs no bash helper. A golden changes only with the
# owner's sign-off (voxcmd-port.md, Working rules).
#
#   home/voxcmd/tests/fixtures/gen-ask-goldens.sh
#
# Writes next to this script:
#   ask-goldens.tsv    voxcmd-pick, -confirm and -hints with the bar stubbed by ask/qs-ipc and ask/qs-picker: name, kind,
#                      env (a JSON object of GOLDEN_* settings for the stubs), args (a JSON array), exit status, stdout,
#                      and what the bar was shown (one line per call or file: "<n>.<call|pending|spec> <text>", JSON
#                      compacted, pids and private directories made fixed)
#   reply-goldens.tsv  `voxcmd --dry-run --reply` against a pending pick: name, pending pick (JSON, `-` for none), the
#                      expansion key on screen, reply, exit status, stdout and stderr
#
# Fields are tab separated with \ \n \t \r escaped.
set -uo pipefail

fixtures_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH='' cd -- "$fixtures_dir/../.." && pwd)
bin_dir=$package_dir/.local/bin
export HOME=/nonexistent LC_ALL=C
while IFS= read -r variable; do unset "$variable"; done < <(compgen -e | grep -E '^(VOXCMD_|GOLDEN_)' || true)

work=$(mktemp -d)
trap 'pkill -f "$work/" 2>/dev/null; rm -rf "$work"' EXIT

escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//$'\n'/\\n}
  text=${text//$'\t'/\\t}
  text=${text//$'\r'/\\r}
  printf '%s' "$text"
}

# The pid and the private directories change on every run; the goldens hold them fixed.
fixed_paths() { sed -E -e "s#$1#RT#g" -e 's#voxcmd-(pick|confirm|hints)\.[A-Za-z0-9]{6}#voxcmd-\1.X#g' -e 's#"pid":[0-9]+#"pid":0#'; }

# ---- ask --------------------------------------------------------------------------------------------------------------

ask_row() {
  local name=$1 kind=$2 env=$3 args=$4 run dumps runtime status stdout shown="" file pair arg
  run=$work/$name
  runtime=$run/runtime dumps=$run/dumps
  mkdir -p "$runtime" "$dumps" "$run/config/hypr/scripts"
  cp "$fixtures_dir/ask/qs-ipc" "$fixtures_dir/ask/qs-picker" "$run/config/hypr/scripts/"
  local -a argv=()
  while IFS= read -r arg; do argv+=("$arg"); done < <(jq -r '.[]' <<<"$args")
  stdout=$(
    export XDG_RUNTIME_DIR=$runtime XDG_CONFIG_HOME=$run/config GOLDEN_DUMPS=$dumps
    while IFS= read -r pair; do export "${pair%%=*}=${pair#*=}"; done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<<"$env")
    timeout 20 "$bin_dir/voxcmd-$kind" "${argv[@]}"
  )
  status=$?
  for file in "$dumps"/*; do
    [ -e "$file" ] || continue
    case "$file" in
    *.call) shown+="${file##*/} $(cat "$file")"$'\n' ;;
    *) shown+="${file##*/} $(jq -c . "$file")"$'\n' ;;
    esac
  done
  shown=$(fixed_paths "$runtime" <<<"${shown%$'\n'}")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$(escape "$env")" "$(escape "$args")" "$status" "$(escape "$stdout")" \
    "$(escape "$shown")"
}

hint_boxes='[{"id":"a","label":"Next - top","box":[100,50,60,20]},{"id":"b","label":"Next - bottom","box":[300,200,70.5,22]}]'
many_boxes=$(jq -n -c '[range(0; 11) | {id: tostring, label: "Item \(.)", box: [. * 10, 0, 8, 8]}]')
{
  ask_row pick-strings pick '{"GOLDEN_ANSWER": "2. Slack"}' '["Which?", "[\"Firefox\", \"Slack\"]"]'
  ask_row pick-shared-labels pick '{"GOLDEN_ANSWER": "2. Slack (b)"}' \
    '["Which command?", "[{\"id\": 7, \"label\": \"Slack\"}, {\"id\": \"b\", \"label\": \"Slack\"}, {\"id\": \"t\", \"label\": \"a\\tb\"}, {\"id\": \"x\"}, {\"id\": \"f\", \"label\": false}, \"Slack\"]"]'
  ask_row pick-expansion pick '{"GOLDEN_ANSWER": "more\t2. y"}' \
    '["Voice Help", "[{\"id\": \"a\", \"label\": \"A\", \"expand\": \"more\"}, {\"id\": \"b\", \"label\": \"B\", \"expand\": \"none\"}]", "{\"more\": {\"title\": \"More\", \"choices\": [\"x\", {\"id\": \"y1\", \"label\": \"y\"}]}, \"empty\": {\"title\": \"E\", \"choices\": []}, \"tab\\tkey\": {\"choices\": [\"z\"]}, \"untitled\": {\"choices\": [\"w\"]}}"]'
  ask_row pick-cancel pick '{"GOLDEN_ANSWER": ""}' '["Which?", "[\"Firefox\", \"Slack\"]"]'
  ask_row pick-unknown-answer pick '{"GOLDEN_ANSWER": "Thunderbird"}' '["Which?", "[\"Firefox\", \"Slack\"]"]'
  ask_row pick-empty-id pick '{"GOLDEN_ANSWER": "1. Blank"}' '["Which?", "[{\"id\": \"\", \"label\": \"Blank\"}]"]'
  ask_row pick-gone-expansion pick '{"GOLDEN_ANSWER": "gone\t1. x"}' '["Which?", "[\"Firefox\"]"]'
  ask_row hints-number hints '{"GOLDEN_ANSWER": "2"}' "$(jq -n -c --arg c "$hint_boxes" '["Which one?", $c]')"
  ask_row hints-label hints '{"GOLDEN_ANSWER": "1. Next - top"}' "$(jq -n -c --arg c "$hint_boxes" '["Which one?", $c]')"
  ask_row hints-cancel hints '{"GOLDEN_ANSWER": ""}' "$(jq -n -c --arg c "$hint_boxes" '["Which one?", $c]')"
  ask_row hints-past-the-end hints '{"GOLDEN_ANSWER": "7"}' "$(jq -n -c --arg c "$hint_boxes" '["Which one?", $c]')"
  ask_row hints-zero hints '{"GOLDEN_ANSWER": "0"}' "$(jq -n -c --arg c "$hint_boxes" '["Which one?", $c]')"
  ask_row hints-refused hints '{"GOLDEN_OPEN": "invalid", "GOLDEN_ANSWER": "2. Next - bottom"}' \
    "$(jq -n -c --arg c "$hint_boxes" '["Which one?", $c]')"
  ask_row hints-no-box hints '{"GOLDEN_ANSWER": "1. Next"}' '["Which one?", "[{\"id\": \"a\", \"label\": \"Next\"}, {\"id\": 2, \"box\": [1, 2, 3, 4]}]"]'
  ask_row hints-too-many hints '{"GOLDEN_ANSWER": "11. Item 10"}' "$(jq -n -c --arg c "$many_boxes" '["Which one?", $c]')"
  ask_row confirm-yes confirm '{"GOLDEN_ANSWER": "yes"}' '["--verb", "close", "Close Slack window: Inbox?"]'
  ask_row confirm-shouted confirm '{"GOLDEN_ANSWER": "YES"}' '["Close it?"]'
  ask_row confirm-no confirm '{"GOLDEN_ANSWER": "no"}' '["--verb", "quit", "Quit it?"]'
  ask_row confirm-cancel confirm '{"GOLDEN_ANSWER": ""}' '["Quit it?"]'
} >"$fixtures_dir/ask-goldens.tsv"

# ---- reply ------------------------------------------------------------------------------------------------------------

# A pending pick is trusted only while its pid's command line names an asker, so a copy of sleep stands in for one.
waiter=$work/voxcmd-hints
cp "$(command -v sleep)" "$waiter"
"$waiter" 600 &
waiter_pid=$!
reply_runtime=$work/reply-runtime
mkdir -p "$reply_runtime/voxcmd"
reply_fifo=$reply_runtime/result
mkfifo "$reply_fifo"
view_file=$reply_runtime/view

reply_row() {
  local name=$1 pending=$2 view=$3 reply=$4 output status
  rm -f "$reply_runtime/voxcmd/pending-pick.json"
  if [ "$pending" != - ]; then
    jq -c --argjson pid "$waiter_pid" --arg fifo "$reply_fifo" --arg view "$view_file" \
      '.pid = $pid | .fifo = $fifo | if has("view") then .view = $view else . end' <<<"$pending" \
      >"$reply_runtime/voxcmd/pending-pick.json"
  fi
  printf '%s' "$view" >"$view_file"
  output=$(XDG_RUNTIME_DIR=$reply_runtime VOXCMD_CONFIG_DIR=$fixtures_dir/speech "$bin_dir/voxcmd" --dry-run --reply "$reply" 2>&1)
  status=$?
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$(escape "$pending")" "$(escape "$view")" "$(escape "$reply")" "$status" \
    "$(escape "$output")"
}

three='{"pid":0,"fifo":"","label":"Which one?","kind":"hints","expansions":{},"choices":[{"id":"a","label":"1. Next - top"},{"id":"b","label":"2. Next - bottom"},{"id":"c","label":"3. Settings - middle"}]}'
four_boxes='{"pid":0,"fifo":"","label":"Which one?","kind":"hints","expansions":{},"choices":[{"id":"a","label":"1. Next - top left","box":[100,50,60,20]},{"id":"b","label":"2. Next - top right","box":[300,53,70,20]},{"id":"c","label":"3. Next - bottom left","box":[100,300,80,20]},{"id":"d","label":"4. Next - bottom right","box":[500,400,80,20]}]}'
four_unboxed=$(jq -c '.choices |= map(del(.box))' <<<"$four_boxes")
one='{"pid":0,"fifo":"","label":"Which command?","choices":[{"id":"0","label":"1. Session: Lock (System)"}],"expansions":{},"view":""}'
words='{"pid":0,"fifo":"","label":"Which command?","choices":[{"id":"0","label":"1. Lock (System)"},{"id":"1","label":"2. Close Window"},{"id":"2","label":"3. Closed Tabs"},{"id":"3","label":"4. Log Out"},{"id":"4","label":"5. Slack (b)"},{"id":"5","label":"6. Slack (c)"}],"expansions":{},"view":""}'
expanded='{"pid":0,"fifo":"","label":"Voice Help","choices":[{"id":"apps","label":"1. Apps","expand":"apps"},{"id":"media","label":"2. Media"}],"expansions":{"apps":{"title":"Apps phrases","choices":[{"id":"o","label":"1. open firefox"},{"id":"c","label":"2. close the window"}]}},"view":""}'
confirm='{"pid":0,"fifo":"","label":"Close Slack window: Inbox?","kind":"confirm","choices":[{"id":"yes","label":"Yes"},{"id":"no","label":"No"}],"expansions":{},"listen_again":"","verb":"close"}'
confirm_no_verb=$(jq -c '.verb = ""' <<<"$confirm")

pick_replies=(
  two "the second one" 3 "number 8" "the 3rd one" "the twelfth one" "twenty first" "twenty one" "the last one" last
  2th "never mind" nevermind "none of them" nothing "forget it" cancel settings "next top" next "pick the first"
  "go with option two" "choose number one" "the top one" top "the bottom one" "the left one" "the right one"
  rightmost lower "upper one" "the first one" zero "lock system" "locked computer" "closing window" "close" "log out"
  "logging out" slack "slack b" yes "that one" "no thanks" no "thats the one please" "lock it" "the system lock"
  "Next, Top!" "zzz" "one" "the one" "first one" "open firefox" "close the window" apps media
)
confirm_replies=(yes "yeah never mind" dont "do not" "close it" close closet stop banana "ok then" "yes please" no
  "nope" "go ahead" "Yes!" "leave it" "close slack" "sure thing" "dont close it")
{
  reply_row no-picker - "" two
  for reply in "${pick_replies[@]}"; do
    reply_row three "$three" "" "$reply"
    reply_row four-boxes "$four_boxes" "" "$reply"
    reply_row four-unboxed "$four_unboxed" "" "$reply"
    reply_row one "$one" "" "$reply"
    reply_row words "$words" "" "$reply"
    reply_row expanded-top "$expanded" "" "$reply"
    reply_row expanded-apps "$expanded" apps "$reply"
    reply_row expanded-gone "$expanded" gone "$reply"
  done
  for reply in "${confirm_replies[@]}"; do
    reply_row confirm "$confirm" "" "$reply"
    reply_row confirm-no-verb "$confirm_no_verb" "" "$reply"
  done
} >"$fixtures_dir/reply-goldens.tsv"
kill "$waiter_pid" 2>/dev/null
