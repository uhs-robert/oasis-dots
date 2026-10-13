# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Clicks visible text in the focused window by OCR: "click sign in", "right click settings", "double click readme", "triple click paragraph".
# Format: ~/.config/voxcmd/README.md

name="Click"
confirm=0
target_match=words
# The click itself is the feedback; only an error or a missing target shows a toast.
silent_actions=(click right_click double_click triple_click show_hints no_text)

# Every click verb needs a target, so a bare "click" or "right click" still reaches the Cursor submap's binds in
# Keybinds. The optional "on" is a filler word, so "click on settings" and "click settings" mean the same.
verbs=(
  "right_click   right ?click( on)? {target}"
  "double_click  double ?click( on)? {target}"
  "triple_click  triple ?click( on)? {target}"
  "click         (left )?click( on)? {target}"
  "show_hints    {show} (the )?(click |keyboard |pointer )?hints|hint mode"
)

examples=(
  "click <text on screen>"
  "right click <text on screen>"
  "double click <text on screen>"
  "triple click <text on screen>"
  "show hints"
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
  [no_text]='no_text'
)

click_ocr="$voxcmd_share_dir/click-ocr"
# Where click-ocr records the window it captured, and how long that record is trusted.
click_target_file="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/click-target"
click_target_max_age=60
click_match="$voxcmd_share_dir/click-match.awk"

# Whether the spoken text holds a word that is neither filler nor ignored.
has_target_word() {
  local word ignored=" $filler_words $ignored_target_words "
  for word in $(tr -cs 'a-z0-9' ' ' <<<"${1,,}"); do
    [[ "$ignored" == *" $word "* ]] || return 0
  done
  return 1
}

# Drops the candidates whose click point lies under something drawn above the focused window: its capture (grim -T)
# is the window's own buffer, so OCR also reads text that is covered on screen. Covering is a floating window over a
# tiled one, a pinned window over an unpinned one, and the monitor's reserved edges (the bar and other layer-shell
# surfaces). Between two floating windows the order is unknown, and the focused one is raised, so neither covers.
# Stdin and stdout are the candidate list; whatever hyprctl cannot answer covers nothing.
drop_covered() {
  local active clients monitors
  active=$(json_or '{}' hyprctl activewindow -j)
  clients=$(json_or '[]' hyprctl clients -j)
  monitors=$(json_or '[]' hyprctl monitors -j)
  jq -c --argjson active "$active" --argjson clients "$clients" --argjson monitors "$monitors" '
    def inside($x; $y; $left; $top; $width; $height):
      $x >= $left and $x < $left + $width and $y >= $top and $y < $top + $height;
    [$clients[] | select((.mapped // false) and ((.hidden // false) | not) and .at != null and .address != $active.address
        and (.workspace.id == $active.workspace.id or (.pinned // false))
        and (((.pinned // false) and (($active.pinned // false) | not)) or ((.floating // false) and (($active.floating // false) | not))))] as $above
    | [$monitors[] | (if (.transform // 0) % 2 == 1 then {w: .height, h: .width} else {w: .width, h: .height} end) as $pixels
        | {x, y, w: ($pixels.w / .scale), h: ($pixels.h / .scale), reserved: (.reserved // [0, 0, 0, 0])}] as $screens
    | def covered($x; $y):
        any($above[]; inside($x; $y; .at[0]; .at[1]; .size[0]; .size[1]))
        or any($screens[]; inside($x; $y; .x; .y; .w; .h)
          and ($x < .x + .reserved[0] or $y < .y + .reserved[1] or $x >= .x + .w - .reserved[2] or $y >= .y + .h - .reserved[3]));
      map(select(.id | split(",") | covered(.[0] | tonumber; .[1] | tonumber) | not))'
}

# Prints a command's JSON answer, or the default when it fails or answers something else.
json_or() {
  local default="$1" answer
  shift
  answer=$("$@" 2>/dev/null) && jq -e . >/dev/null 2>&1 <<<"$answer" && printf '%s\n' "$answer" || printf '%s\n' "$default"
}

# click-match.awk's candidates for the spoken text $2 over click-ocr's output $3, as JSON for $1's button. A fourth
# argument makes them the sub-spans of runs instead of whole runs.
ocr_matches() {
  CLICK_TARGET="$2" CLICK_SPANS="${4:-}" awk -f "$click_match" <<<"$3" |
    jq -R -s -c --arg button "$1" '
      split("\n") | map(select(. != "") | split("\t"))
      | map({id: "\(.[0]),\(.[1]),\($button),\(.[4]),\(.[5]),\(.[6]),\(.[7])", match_text: .[2], label: .[3]})'
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
  if ! output=$("$click_ocr" 2>"$error_file"); then
    message=$(tail -n 1 "$error_file")
    rm -f "$error_file"
    jq -n -c --arg target "$2" --arg message "${message:-capture failed}" '[{id: "error:\($message)", label: $message, match_text: $target}]'
    return
  fi
  rm -f "$error_file"
  found=$(ocr_matches "$button" "$2" "$output")
  if ! matches_whole_run "$2" "$found"; then
    spans=$(ocr_matches "$button" "$2" "$output" spans)
    [ "$spans" = '[]' ] || found=$spans
  fi
  visible=$(drop_covered <<<"$found")
  if [ "$visible" = '[]' ] && [ "$found" != '[]' ]; then
    jq -n -c --arg target "$2" '[{id: "covered:", label: "covered", match_text: $target}]'
    return
  fi
  printf '%s\n' "$visible"
}

# Tells the user a click failed, without the screen text: the label voxcmd would put in its own error toast is OCR text,
# and the bar keeps error toasts in its history. Nothing is returned as a failure, so voxcmd adds no toast of its own.
click_failed() {
  notify-send --app-name=voxcmd "voxcmd failed" "Click failed: $1"
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
    return 0
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
    return 0
  fi
  case "$button" in
  # wlrctl has no double or triple click.
  double) clicked=$(repeat_left_click 2) ;;
  triple) clicked=$(repeat_left_click 3) ;;
  *) clicked=$(wlrctl pointer click "$button" 2>&1) ;;
  esac || click_failed "$(tail -n 1 <<<"$clicked")"
  return 0
}

no_text() {
  notify-send --transient --app-name=voxcmd "No \"$target\" on screen"
}

# The same invocation as the Cursor submap's Floating Click (hypr/lib/actions/cursor.lua); detached, since it waits for
# a key.
show_hints() {
  setsid -f wl-kbptr -o modes=floating,click -o mode_floating.source=detect >/dev/null 2>&1 </dev/null
}
