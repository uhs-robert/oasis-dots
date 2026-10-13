# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Focuses Firefox tabs, opens sites and follows links by number: "go to <tab>", "open <site> in firefox", "show links",
# then "3" or "follow link 3". Link hints are Tridactyl's <A-F12> bind, defined in home/tridactyl's tridactylrc.
# Opening a site without saying where is firefox-sites.sh, a fallback after the apps. Format: ~/.config/voxcmd/README.md

name="Firefox"
confirm=0
# The tab, page or hints that appear are the feedback; a failure still says why.
silent=1
# Tab titles and site names are matched by their words: a fuzzy hit on scattered letters would switch to the wrong tab.
target_match=words
# Candidate labels name the tab or page, which says what runs.
action_labels=0
# Kept in a global string too: voxcmd's match_ignore_words is local to its loader and gone when candidates() runs.
ignored_words="tab tabs website site page"
read -ra match_ignore_words <<<"$ignored_words"

# Specific before general: "go to the X tab" before "go to X", "open X in firefox" before nothing. Link numbers are a
# target rather than {number}, so "follow link three" works as well as "follow link 3". "click link 3" stays Click's.
verbs=(
  "show_links   {show} (the )?(links|link hints)|link hints|hint links|number the links"
  "follow_link  (follow|open) (the )?link (number )?{target}"
  "hide_links   (hide|close|dismiss|remove) (the )?(links|link hints)"
  "new_tab      ({open} )?(a )?new tab"
  "close_tab    {close} (the |this |current |this current )?tab"
  "open_here    {open} {target} (here|in this tab|in the current tab|in the same tab)"
  "open_site    {open} {target} (in|on|with) (firefox|the browser|a new tab|new tab)"
  "open_site    {open} (the )?(website|web site|site|url|page|web page) {target}"
  "open_site    {open} (the )?{target} (website|web site|site)"
  "focus_tab    (find|{focus}) (the |my )?{target} tab"
  "focus_tab    {focus} (the )?tab {target}"
  "focus_tab    {focus} {target}"
)

examples=(
  "go to <tab>"
  "find the <tab> tab"
  "go to <site>.com"
  "open <site> in firefox"
  "open website <site>"
  "open <site> here"
  "show links"
  "follow link <number>"
  "hide links"
  "new tab"
  "close tab"
)

declare -A actions=(
  [focus_tab]='focus_tab "$id"'
  [open_site]='"$firefox_tab" open "$id"'
  [open_here]='"$firefox_tab" open --here "$id"'
  [search_site]='"$firefox_tab" search "$target"'
  [search_here]='"$firefox_tab" open --here "$target"'
  [show_links]='show_links'
  [follow_link]='follow_link "$(link_number "$target")"'
  [hide_links]='hide_links'
  [new_tab]='"$firefox_tab" new-tab'
  [close_tab]='"$firefox_tab" close-tab'
)

# A site found nowhere is searched for: the phrase said Firefox, so a search is what is left to do.
declare -A no_match_actions=(
  [open_site]='search_site'
  [open_here]='search_here'
)

# Tab in Voice Help lists every tab; picking one focuses it.
help_choices() {
  "$firefox_tab" candidates tabs "" 2>/dev/null | jq -c 'unique_by(.id) | sort_by(.label | ascii_downcase) | map({id, label, action: "focus_tab"})'
}

firefox_tab="$voxcmd_share_dir/firefox-tab"
apps_integration="$(dirname "${BASH_SOURCE[0]}")/apps.sh"
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-time.sh
source "$voxcmd_share_dir/spoken-time.sh"

candidates() {
  local action="$1" target="$2" kind
  case "$action" in
  focus_tab)
    if names_the_browser "$target" || left_to_apps_others "$target"; then
      echo '[]'
      return
    fi
    kind="tabs"
    ;;
  open_site | open_here) kind=sites ;;
  *) return ;;
  esac
  one_per_id "$target" "$("$firefox_tab" candidates "$kind" "$target" --raw "$raw_transcript" 2>/dev/null || echo '[]')"
}

# A tab is offered by its title and by its site's name; when both match, it would be offered twice, so only the first
# match of each id is kept, in voxcmd's own word matching (strong ones hide weak ones there too).
one_per_id() {
  local matched ignored
  read -ra ignored <<<"$ignored_words"
  matched=$(word_match "$1" "$2" "${ignored[@]}" 2>/dev/null)
  [ -n "$matched" ] || matched='[]'
  jq -c 'reduce .[] as $candidate ([]; if any(.[]; .id == $candidate.id) then . else . + [$candidate | del(.weak)] end)' <<<"$matched"
}

# "go to firefox" is the browser window, which apps.sh focuses.
names_the_browser() {
  [[ "$1" =~ ^((the|my|mozilla|web)\ )*(firefox|browser|web\ browser)$ ]]
}

# What apps.sh leaves to another integration is no tab either: a keybind's description ("go to workspace 2"), a tmux
# session or an agent. Its own checks are reused rather than copied, in a subshell so its globals stay there.
left_to_apps_others() {
  [ -f "$apps_integration" ] || return 1
  (
    # shellcheck source=/dev/null
    source "$apps_integration"
    spoken_as_keybind focus "$1" || names_session_or_agent "$1"
  )
}

# The id is "<window address> <tab title>" or "goto <url>".
focus_tab() {
  case "$1" in
  goto\ *) "$firefox_tab" goto "${1#goto }" ;;
  *) "$firefox_tab" focus "${1%% *}" "${1#* }" ;;
  esac
}

# The numbers are on screen, so the next utterance is probably one: a session that listens like a reply does ("3" is a
# turn) and, whatever ends it without a link followed, takes the hints down again (session_ended). The marker says
# the hints are still up. A Firefox that does not show them (no Tridactyl, no bind) opens nothing to listen for.
links_marker="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/links-shown"

show_links() {
  "$firefox_tab" hints || return
  mkdir -p "$(dirname "$links_marker")"
  : >"$links_marker"
  session_begin links "$file" "Link hints" reply
}

# Following ends the session; hint mode ends itself when a link is followed or its number is missing.
follow_link() {
  local status=0
  rm -f "$links_marker"
  "$firefox_tab" hints "$1" || status=$?
  session_end
  return "$status"
}

hide_links() {
  if session_state >/dev/null; then session_end; else session_ended; fi
}

session_ended() {
  [ -e "$links_marker" ] || return 0
  rm -f "$links_marker"
  "$firefox_tab" dismiss-hints
}

# A turn in the link session is a number ("3", "three", "link 3") or a way out; anything else names no link. Only a
# number is a target here, so any stop word is safe to take as leaving, with or without the hints named.
links_exit_filler='(okay|ok|alright|please|now)'
links_exit_object='(the )?(links|link hints|hints|link mode)'
links_exit_words="^($links_exit_filler )*((cancel|never ?mind|stop|close|hide|dismiss|exit|quit|end|leave|done|turn off|stop showing)( $links_exit_object)?|$links_exit_object off)( $links_exit_filler)*$"
session_rewrite() {
  local text="$1" number
  if [[ "$text" =~ $links_exit_words ]]; then
    printf 'hide links'
    return
  fi
  text="${text#follow }"
  text="${text#open }"
  text="${text#the }"
  text="${text#link }"
  text="${text#number }"
  number=$(link_number "$text")
  [[ "$number" =~ ^[1-9][0-9]*$ ]] && printf 'follow link %s' "$number"
  return 0
}

# "3", "three", "twenty one" as digits; anything else is printed as is, which firefox-tab refuses.
link_number() {
  local word total=0
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "$1"
    return
  fi
  for word in $1; do
    [ -n "${number_words[$word]-}" ] || {
      echo "$1"
      return
    }
    total=$((total + number_words[$word]))
  done
  echo "$total"
}
