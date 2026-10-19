# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Clicks visible text in the focused window by OCR: "click sign in", "right click settings", "double click readme", "triple click paragraph".
# "click mode" opens a voice session where each spoken target is clicked without repeating "click".
# Format: ~/.config/voxcmd/README.md

name="Click"
confirm=0
target_match=words
# The click itself is the feedback; only an error or a missing target shows a toast.
silent_actions=(click right_click double_click triple_click show_hints no_text click_mode stop_clicking)
# A target found nowhere is a turn that did nothing, which counts toward ending click mode.
session_miss_actions=(no_text)
# Labels are text read off the screen, so voxcmd's error toast, which the bar keeps in its history, leaves them out.
private_labels=1

# The ways out of click mode, as a command outside it and after "cortana" inside it. Inside, no bare word leaves: "done",
# "stop", "exit" and "close" are all button labels and stay targets, so default exits are off.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=mode-phrases.sh
source "$voxcmd_share_dir/mode-phrases.sh"
click_exit_object='(the )?(clicking|click mode|clicking mode)'
click_exit_phrase=$(mode_exit_phrase "$click_exit_object")
session_exit_phrases="done clicking|im done clicking|done with $click_exit_object|$click_exit_phrase|exit|quit"
session_exit_hint="say cortana done to stop"
session_default_exits=0
# What "cortana ..." runs inside click mode. A bare "rapid mode" is a click: session_allows_switches stays at 0.
mode_actions=(click_mode stop_clicking)

# Every click verb needs a target, so a bare "click" or "right click" still reaches the Cursor submap's binds in
# Keybinds. The optional "on" is a filler word, so "click on settings" and "click settings" mean the same.
# The mode verbs come first, or "click mode" would be a click on the text "mode". "stop clicking" is here too because
# Media's "stop {target}" and System's "turn off {target}" would otherwise hear it.
verbs=(
  "click_mode    ((start|enter|begin) )?(click|clicking) mode|start clicking"
  "stop_clicking $click_exit_phrase"
  "right_click   right ?click( on)? {target}"
  "double_click  double ?click( on)? {target}"
  "triple_click  triple ?click( on)? {target}"
  "click         (left )?click( on)? {target}"
  "show_hints    {show} (the )?(click |keyboard |pointer )?hints|hint mode"
)

examples=(
  "click mode"
  "click <text on screen>"
  "right click <text on screen>"
  "double click <text on screen>"
  "triple click <text on screen>"
  "show hints"
  "stop clicking"
)

# Words that are not a target even beside a click verb: "click left", "click it", "click here", "click and drag" and
# "left click and hold" are the Cursor submap's binds, which Keybinds runs when this integration yields nothing.
# A plain string, since candidates() runs after voxcmd has copied the arrays out of this file.
ignored_target_words="left right middle here and drag hold"
read -ra match_ignore_words <<<"$ignored_target_words"
# voxcmd's own filler words, which word_match drops as well.
filler_words="the a an my this that please to of on in for it"

# A target seen nowhere on screen is reported here instead of ending as "no match", which would hand "click settings"
# to Keybinds' catch-all. A target of ignored words only has no match to report, so it stays "no match".
declare -A no_match_actions=(
  [click]='no_text'
  [right_click]='no_text'
  [double_click]='no_text'
  [triple_click]='no_text'
)

declare -A actions=(
  [click]='click_at "$id"'
  [right_click]='click_at "$id"'
  [double_click]='click_at "$id"'
  [triple_click]='click_at "$id"'
  [show_hints]='show_hints'
  [click_mode]='session_begin click "$file" "Click mode"'
  [stop_clicking]='session_leave click done || true'
  [no_text]='no_text'
)

# Several matches are numbered on screen over each text's box, not listed as text: voxcmd-hints draws them and pick_box
# places an option from its id.
pick_command=voxcmd-hints

# $1 is an option id, "x,y,button,left,top,width,height"; prints the box as "left top width height".
pick_box() {
  local x y button left top width height
  IFS=, read -r x y button left top width height <<<"$1"
  [ -n "${height:-}" ] || return 1
  echo "$left $top $width $height"
}

# A turn in click mode is a target ("sign in") or a click phrase ("right click settings"). Prints the phrase to route,
# nothing when the turn names no target. "click mode off" names none either: it would reach the stop_clicking verb, but
# only "cortana ..." leaves the mode.
session_rewrite() {
  local text="$1"
  if [[ "$text" =~ ^((left|right|double) )?click$ || "$text" == click\ * && "$text" =~ ^($click_exit_phrase)$ ]]; then
    return
  elif [[ "$text" =~ ^((left|right|double) )?click\  || "$text" == "clicking mode" || "$text" == "start clicking" ]]; then
    printf '%s' "$text"
  else
    printf 'click %s' "$text"
  fi
}

click_ocr="$voxcmd_share_dir/click-ocr"
# Where click-ocr records the window it captured, and how long that record is trusted.
click_target_file="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/click-target"
click_target_max_age=60
click_match="$voxcmd_share_dir/click-match.awk"
# What click-explain adds: click-ocr's flags, and the file the matcher, word matching and the covering check trace to.
click_ocr_args=()
explain_file=""
explain_window_id=""

# Whether the spoken text holds a word that is neither filler nor ignored.
has_target_word() {
  local word ignored=" $filler_words $ignored_target_words "
  for word in $(tr -cs 'a-z0-9' ' ' <<<"${1,,}"); do
    [[ "$ignored" == *" $word "* ]] || return 0
  done
  return 1
}

# The window the candidates belong to: the focused one, or under click-explain's --window the client with that stableId.
target_window_json() {
  if [ -n "${explain_window_id:-}" ]; then
    json_or '[]' hyprctl clients -j | jq -c --arg id "$explain_window_id" 'first(.[] | select(.stableId == $id)) // {}'
  else
    json_or '{}' hyprctl activewindow -j
  fi
}

# Drops the candidates whose click point lies under something drawn above the focused window: its capture (grim -T)
# is the window's own buffer, so OCR also reads text that is covered on screen. Covering is a floating window over a
# tiled one, a pinned window over an unpinned one, and the monitor's reserved edges (the bar and other layer-shell
# surfaces). Between two floating windows the order is unknown, and the focused one is raised, so neither covers.
# Stdin and stdout are the candidate list; whatever hyprctl cannot answer covers nothing. With $1 = mark nothing is
# dropped: every candidate gains covered_by, the reason or null (click-explain).
drop_covered() {
  local active clients monitors
  active=$(target_window_json)
  clients=$(json_or '[]' hyprctl clients -j)
  monitors=$(json_or '[]' hyprctl monitors -j)
  jq -c --arg mark "${1:-}" --argjson active "$active" --argjson clients "$clients" --argjson monitors "$monitors" '
    def inside($x; $y; $left; $top; $width; $height):
      $x >= $left and $x < $left + $width and $y >= $top and $y < $top + $height;
    [$clients[] | select((.mapped // false) and ((.hidden // false) | not) and .at != null and .address != $active.address
        and (.workspace.id == $active.workspace.id or (.pinned // false))
        and (((.pinned // false) and (($active.pinned // false) | not)) or ((.floating // false) and (($active.floating // false) | not))))] as $above
    | [$monitors[] | (if (.transform // 0) % 2 == 1 then {w: .height, h: .width} else {w: .width, h: .height} end) as $pixels
        | {x, y, w: ($pixels.w / .scale), h: ($pixels.h / .scale), reserved: (.reserved // [0, 0, 0, 0])}] as $screens
    | def covered_by($x; $y):
        ([$above[] | select(inside($x; $y; .at[0]; .at[1]; .size[0]; .size[1]))] | if length > 0 then "another window" else null end)
        // ([$screens[] | select(inside($x; $y; .x; .y; .w; .h)
          and ($x < .x + .reserved[0] or $y < .y + .reserved[1] or $x >= .x + .w - .reserved[2] or $y >= .y + .h - .reserved[3]))]
          | if length > 0 then "a reserved edge (the bar)" else null end);
      def reason: .id | split(",") | covered_by(.[0] | tonumber; .[1] | tonumber);
      if $mark == "mark" then map(. + {covered_by: reason}) else map(select(reason == null)) end'
}

# Prints a command's JSON answer, or the default when it fails or answers something else.
json_or() {
  local default="$1" answer
  shift
  answer=$("$@" 2>/dev/null) && jq -e . >/dev/null 2>&1 <<<"$answer" && printf '%s\n' "$answer" || printf '%s\n' "$default"
}

# click-match.awk over stdin; under click-explain its trace goes to the explain file.
run_matcher() {
  if [ -n "$explain_file" ]; then
    awk -v explain=1 -f "$click_match" 2>>"$explain_file"
  else
    awk -f "$click_match"
  fi
}

# click-match.awk's candidates for the spoken text $2 over click-ocr's output $3, as JSON for $1's button. A fourth
# argument makes them the sub-spans of runs instead of whole runs.
ocr_matches() {
  CLICK_TARGET="$2" CLICK_SPANS="${4:-}" run_matcher <<<"$3" |
    jq -R -s -c --arg button "$1" '
      split("\n") | map(select(. != "") | split("\t"))
      | map({id: "\(.[0]),\(.[1]),\($button),\(.[4]),\(.[5]),\(.[6]),\(.[7])", match_text: .[2], label: .[3]})'
}

# Under click-explain, appends word_match's verdict on each of the candidates $2 for the spoken text $1 to the trace,
# tagged with the matcher pass $3.
trace_verdicts() {
  local -a ignored
  read -ra ignored <<<"$ignored_target_words"
  word_match_trace=1 word_match "$1" "$2" "${ignored[@]}" 2>/dev/null |
    jq -r --arg pass "$3" '.[]? | "~verdict\t\($pass)\t\(.id | split(",")[:2] | join(","))\t\(.kept)\t\(.verdict)"' >>"$explain_file"
}

# Whether voxcmd's word matching keeps any of the whole-run candidates $2 for the spoken text $1. When it keeps none,
# the target may be part of a longer run of words ("2 tasks" in a sentence), so candidates() looks for sub-spans.
# word_match is voxcmd's own, rather than a copy that could drift from it.
matches_whole_run() {
  local -a ignored
  read -ra ignored <<<"$ignored_target_words"
  local kept
  kept=$(word_match "$1" "$2" "${ignored[@]}" 2>/dev/null) || return 1
  [ -n "$kept" ] && [ "$(jq length <<<"$kept")" != 0 ]
}

# The ocr candidates for the spoken text, as {id: "x,y,button,left,top,width,height", label, match_text}; the box is the
# matched text's, for overlays that number the candidates. Voxcmd's word matching then decides
# which are strong and which weak. A failure, or every candidate being covered, is one candidate whose id says so,
# which click_at reports: an empty list would read as "not on screen".
candidates() {
  local button=left output error_file message found spans visible
  case "$1" in
  right_click) button=right ;;
  double_click) button=double ;;
  triple_click) button=triple ;;
  esac
  has_target_word "$2" || {
    echo '[]'
    return
  }
  error_file=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/voxcmd-click-error.XXXXXX")
  if ! output=$("$click_ocr" "${click_ocr_args[@]}" 2>"$error_file"); then
    message=$(tail -n 1 "$error_file")
    rm -f "$error_file"
    jq -n -c --arg target "$2" --arg message "${message:-capture failed}" '[{id: "error:\($message)", label: $message, match_text: $target}]'
    return
  fi
  rm -f "$error_file"
  [ -z "${explain_file:-}" ] || grep '^#info' <<<"$output" >>"$explain_file"
  found=$(ocr_matches "$button" "$2" "$output")
  [ -z "${explain_file:-}" ] || trace_verdicts "$2" "$found" whole
  if ! matches_whole_run "$2" "$found"; then
    spans=$(ocr_matches "$button" "$2" "$output" spans)
    [ "$spans" = '[]' ] || found=$spans
    [ -z "${explain_file:-}" ] || trace_verdicts "$2" "$spans" spans
  fi
  [ -z "${explain_file:-}" ] || printf '~used\t%s\n' "$([ "${spans:-[]}" != '[]' ] && [ "$found" = "$spans" ] && echo spans || echo whole)" >>"$explain_file"
  [ -z "${explain_file:-}" ] || drop_covered mark <<<"$found" |
    jq -r '.[] | "~covered\t\(.id | split(",")[:2] | join(","))\t\(.covered_by // "-")"' >>"$explain_file"
  visible=$(drop_covered <<<"$found")
  if [ "$visible" = '[]' ] && [ "$found" != '[]' ]; then
    jq -n -c --arg target "$2" '[{id: "covered:", label: "covered", match_text: $target}]'
    return
  fi
  printf '%s\n' "$visible"
}

# Reports why a click failed to voxcmd's error toast, as the reason only: the reason comes from a tool, never the screen.
click_failed() {
  echo "$1"
  return 1
}

# Whether the focused window is still the one click-ocr captured, at the same place and size, recently. Anything else
# means the captured coordinates may now point at other content.
target_window_unchanged() {
  local current
  [ -f "$click_target_file" ] || return 1
  current=$(json_or '{}' hyprctl activewindow -j)
  jq -e --argjson current "$current" --argjson now "$(date +%s)" --argjson max_age "$click_target_max_age" '
    def identity: {id: (.stableId // .address), at, size};
    $now - .captured_at <= $max_age and .window.at != null and (.window | identity) == ($current | identity)
  ' "$click_target_file" >/dev/null 2>&1
}

# Left-clicks $1 times, stopping at the first failure.
repeat_left_click() {
  local click_number
  for ((click_number = 0; click_number < $1; click_number++)); do
    wlrctl pointer click left 2>&1 || return 1
  done
}

# $1 is "x,y,button,left,top,width,height" in global logical coordinates; only the point is used here. Hyprland's Lua config has no movecursor dispatcher, and
# wlrctl can only move the pointer relative to where it is.
click_at() {
  local x y button _box moved clicked
  case "$1" in
  error:*)
    click_failed "${1#error:}"
    return
    ;;
  covered:*)
    notify-send --transient --app-name=voxcmd "\"$target\" is covered by another window"
    return 0
    ;;
  esac
  if ! target_window_unchanged; then
    notify-send --transient --app-name=voxcmd "The window changed; say it again"
    return 0
  fi
  IFS=, read -r x y button _box <<<"$1"
  moved=$(hyprctl dispatch "hl.dsp.cursor.move({x=$x,y=$y})") || moved="hyprctl failed"
  if [ "$moved" != ok ]; then
    click_failed "$(tail -n 1 <<<"$moved")"
    return
  fi
  case "$button" in
  # wlrctl has no double or triple click.
  double) clicked=$(repeat_left_click 2) ;;
  triple) clicked=$(repeat_left_click 3) ;;
  *) clicked=$(wlrctl pointer click "$button" 2>&1) ;;
  esac || click_failed "$(tail -n 1 <<<"$clicked")"
}

# ---- click-explain ---------------------------------------------------------------------------------------------------
# `voxcmd click-explain "<text>" [--window <stableId>]` runs candidates() as a click would, over the real capture, OCR,
# matcher, word matching and covering check, with each stage tracing its decisions to $explain_file, then prints them.
# It never routes, moves the pointer or notifies: the screen text goes to the terminal only, and the trace and capture
# are deleted on exit.

# Prints "kept strong (...)", "dropped: ..." and the like for the candidate at $2 from matcher pass $1, whose
# match kind is $3.
explain_verdict_text() {
  local pass="$1" point="$2" kind="$3" verdict="${verdict_of[$1:$2]-}" lead="" text
  [ "$kind" != span ] || lead="sub-span, "
  [ "$kind" != joined ] || lead="joined letters, "
  [ -n "$verdict" ] || {
    printf '%sno verdict' "$lead"
    return
  }
  if [ "${kept_of[$pass:$point]}" = true ]; then
    text="kept ${verdict%%:*} (${verdict#*: })"
    if [ "$pass" = "$used_pass" ] && [ "${covered_by_of[$point]:--}" != - ]; then
      text="$text, then dropped: covered by ${covered_by_of[$point]}"
    fi
  elif [[ "$verdict" == dropped:* ]]; then
    text="$verdict"
  else
    text="dropped: $verdict"
  fi
  printf '%s%s' "$lead" "$text"
}

# What voxcmd would do with the candidates left after covering ($1, JSON), as click would route them.
explain_outcome() {
  local visible="$1" options count first_id
  local -a ignored
  read -ra ignored <<<"$ignored_target_words"
  first_id=$(jq -r '.[0].id // ""' <<<"$visible")
  case "$first_id" in
  error:*)
    echo "capture or OCR failed (${first_id#error:}); a toast says the click failed"
    return
    ;;
  covered:*)
    echo "covered: every candidate is under another window or a reserved edge"
    return
    ;;
  esac
  options=$(word_match "$target" "$visible" "${ignored[@]}")
  count=$(jq length <<<"${options:-[]}")
  if [ "$count" = 0 ]; then
    echo "not on screen"
  elif needs_pick "$options"; then
    printf 'overlay with %s%s (the picker, if the bar cannot draw it or there are more than 10)\n' "$count" \
      "$([ "$count" != 1 ] || echo ", a weak match: asks \"this one?\"")"
  else
    printf 'click at %s\n' "$(jq -r '.[0].id | split(",")[:2] | join(",")' <<<"$options")"
  fi
}

# Prints the trace file for the target $1 and the candidates left after covering $2.
explain_render() {
  local target="$1" visible="$2" line pass="" run_id key
  local -a field=()
  local -A verdict_of=() kept_of=() covered_by_of=() info=() cands_of=()
  local used_pass=whole
  while IFS= read -r line; do
    IFS=$'\t' read -r -a field <<<"$line"
    case "${field[0]}" in
    '~pass') pass="${field[1]}" ;;
    '~verdict')
      verdict_of["${field[1]}:${field[2]}"]="${field[4]}"
      kept_of["${field[1]}:${field[2]}"]="${field[3]}"
      ;;
    '~covered') covered_by_of["${field[1]}"]="${field[2]}" ;;
    '~used') used_pass="${field[1]}" ;;
    '#info')
      for key in "${field[@]:1}"; do info["${key%%=*}"]="${key#*=}"; done
      ;;
    esac
  done <"$explain_file"

  if [ -n "${info[mode]-}" ]; then
    printf 'window   %s %s\n' "${info[class]:-?}" "${info[size]}"
    printf 'capture  %s, image %s, scale x%s y%s, %s, %s strip(s), OCR %s ms\n' "${info[mode]}" "${info[image]}" "${info[scale_x]}" \
      "${info[scale_y]}" "$([ "${info[inverted]}" = 1 ] && echo inverted || echo "not inverted")" "${info[strips]}" "${info[ocr_ms]}"
  fi
  printf 'target   "%s"\n' "$target"

  declare -A pending=()
  while IFS= read -r line; do
    IFS=$'\t' read -r -a field <<<"$line"
    case "${field[0]}" in
    '~pass')
      pass="${field[1]}"
      if [ "$pass" = whole ]; then
        echo "pass 1: whole runs"
      else
        echo "pass 2: sub-spans of runs (no whole run was kept by word matching)"
      fi
      ;;
    '~drop') printf '  word "%s" (conf %s) near %s,%s: dropped, %s\n' "${field[2]}" "${field[1]}" "${field[3]}" "${field[4]}" "${field[5]}" ;;
    '~cand') pending["$pass:${field[1]}"]+="${field[2]},${field[3]}"$'\t'"${field[4]}"$'\t'"${field[5]}"$'\n' ;;
    '~run')
      run_id="${field[1]}"
      printf '  run %s: %s\n' "$run_id" "${field[2]}"
      if [ -n "${pending[$pass:$run_id]-}" ]; then
        while IFS=$'\t' read -r point kind text; do
          [ -n "$point" ] || continue
          printf '    candidate %s "%s": %s\n' "$point" "$text" "$(explain_verdict_text "$pass" "$point" "$kind")"
        done <<<"${pending[$pass:$run_id]}"
      else
        printf '    %s\n' "${field[3]}"
      fi
      ;;
    esac
  done <"$explain_file"
  printf 'outcome  %s\n' "$(explain_outcome "$visible")"
}

# Reads the trace of one click of $1 on the focused window, or on the client with stableId $2.
explain_click() {
  local target="$1" visible
  explain_window_id="${2:-}"
  if ! has_target_word "$target"; then
    printf 'target   "%s"\noutcome  filler-only target: the screen is not read, and Keybinds'"'"' click binds get it\n' "$target"
    return 0
  fi
  click_ocr_args=(--explain)
  [ -z "$explain_window_id" ] || click_ocr_args+=(--window "$explain_window_id")
  explain_file=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/voxcmd-explain.XXXXXX")
  trap 'rm -f "$explain_file"' EXIT
  trap 'rm -f "$explain_file"; exit 130' INT TERM
  visible=$(candidates click "$target")
  explain_render "$target" "$visible"
}

no_text() {
  notify-send --transient --app-name=voxcmd "No \"$target\" on screen"
}

# The same invocation as the Cursor submap's Floating Click (hypr/lib/actions/cursor.lua); detached, since it waits for
# a key.
show_hints() {
  setsid -f wl-kbptr -o modes=floating,click -o mode_floating.source=detect >/dev/null 2>&1 </dev/null
}
