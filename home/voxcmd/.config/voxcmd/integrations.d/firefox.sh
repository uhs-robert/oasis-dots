# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Focuses Firefox tabs and opens sites: "go to <tab>", "open <site> in firefox".
# Opening a site without saying where is firefox-sites.sh, a fallback after the apps. Format: ~/.config/voxcmd/README.md

name="Firefox"
confirm=0
# The tab or page that appears is the feedback; a failure still says why.
silent=1
# Tab titles and site names are matched by their words: a fuzzy hit on scattered letters would switch to the wrong tab.
target_match=words
# Candidate labels name the tab or page, which says what runs.
action_labels=0
# Kept in a global string too: voxcmd's match_ignore_words is local to its loader and gone when candidates() runs.
ignored_words="tab tabs website site page"
read -ra match_ignore_words <<<"$ignored_words"

# Specific before general: "go to the X tab" before "go to X", "open X in firefox" before nothing.
verbs=(
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
  "new tab"
  "close tab"
)

declare -A actions=(
  [focus_tab]='focus_tab "$id"'
  [open_site]='"$firefox_tab" open "$id"'
  [open_here]='"$firefox_tab" open --here "$id"'
  [search_site]='"$firefox_tab" search "$target"'
  [search_here]='"$firefox_tab" open --here "$target"'
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
