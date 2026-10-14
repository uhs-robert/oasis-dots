# shellcheck shell=bash disable=SC2034,SC2016
# Every row of the bar's screenshot menu by voice, through the screenshot tool's own flags (hypr/scripts/screenshot.sh),
# so a capture lands where the Print key's does. Recording is in recording.sh. Format: ~/.config/voxcmd/README.md

name="Screenshot"
confirm=0
# Each capture opens the bar's selector or saves with its own notification.
silent_actions=(region frozen screen pick_window focused text pixel scroll_text scroll_image)

screenshot_tool="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/screenshot.sh"

# "screenshot" alone is not a verb here: it stays with the Keybinds fallback, which opens the menu.
shot="((take|grab|capture|make) )?(an? |the |my )?screenshot( of)?"
area="(region|area|selection|part of the screen)"
current="(this|the|my|current|focused|active)( current| focused| active)?"

# Scroll and text first: "text from a scrolling capture" must not read as a plain region.
verbs=(
  "scroll_text   scroll(ing)? (text|ocr)|(grab|get|read|copy) (the )?text from (a )?scroll(ing)?( capture| screenshot)?"
  "scroll_image  scroll(ing)? (screenshot|capture)|(take|grab|make) (a )?scroll(ing)? (screenshot|capture)|${shot} (a )?scroll(ing)?( ${area}| page)?"
  "pixel         pick (a |the )?(pixel )?colou?r|(pick|get|grab) (a |the )?pixel( colou?r)?|colou?r picker|eyedropper"
  "text          (grab|get|read|copy|extract) (the )?text (from|of) (a |the )?${area}|ocr (a |the )?${area}|text from (a |the )?${area}"
  "frozen        ${shot} (a |the )?(frozen|still) ${area}|((take|grab|capture|make) )?(an? )?(frozen|still) screenshot( of (a |the )?${area})?"
  "focused       ${shot} ${current} window"
  "pick_window   ${shot} (a |any )?window"
  "screen        ${shot} (the |my |this )?((whole|entire|full) )?(screen|display|monitor)"
  "region        ${shot} (a |an |the )?${area}"
)

examples=(
  "screenshot region"
  "screenshot this window"
  "screenshot the screen"
  "take a frozen screenshot"
  "grab text from a region"
  "pick a color"
  "scrolling screenshot"
  "scroll text"
)

declare -A actions=(
  [region]='capture --region'
  [frozen]='capture --freeze'
  [screen]='capture --screen'
  [pick_window]='capture --window'
  [focused]='capture --focused'
  [text]='capture --text'
  [pixel]='capture --pixel'
  [scroll_text]='capture --scroll-text'
  [scroll_image]='capture --scroll-image'
)

# screenshot.sh waits for the selector or the capture to finish; detached, voxcmd does not.
capture() {
  if [ ! -x "$screenshot_tool" ]; then
    echo "$screenshot_tool is missing"
    return 1
  fi
  setsid -f "$screenshot_tool" "$@" >/dev/null 2>&1 </dev/null
}
