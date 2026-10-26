# shellcheck shell=bash
# Hook library of firefox.toml: sourced before every hook and action of the integration.

firefox_tab="$VOXCMD_SHARE_DIR/firefox-tab"

# id<TAB>label<TAB>match_text per tab or site, from firefox-tab's JSON. A tab is offered by its title and by its site's
# name, so when both match it would be offered twice: the word match runs first (weak ones are kept, voxcmd re-judges
# them), then only the first row of each id stays, so a weak copy cannot hide a strong one. Tabs and newlines in a
# label would split the row, and a candidate with no match text is skipped. An empty id is no candidate.
firefox_rows() {
  local kind="$1"
  "$firefox_tab" candidates "$kind" "$VOXCMD_ARG_TARGET" --raw "$VOXCMD_RAW_TRANSCRIPT" 2>/dev/null |
    jq -r '.[]
      | select((.id // "") != "")
      | (.match_text // .label // "") as $match
      | select($match != "")
      | [.id, (.label // ""), $match] | map(gsub("[\t\n\r]"; " ")) | join("\t")' |
    "$VOXCMD_SELF" util word-match --ignore "$VOXCMD_MATCH_IGNORE_WORDS" "$VOXCMD_ARG_TARGET" 2>/dev/null |
    awk -F'\t' '!seen[$1]++'
}

site_candidates() { firefox_rows sites; }

# Yields (prints nothing) for what other integrations own: the browser window itself, a keybind's description ("go to
# workspace 2"), a tmux session or an agent.
#
# The tabs are read while the keybind check runs, since firefox-tab takes most of the time and does not depend on it.
# Their stderr is dropped: on a yield the reader is left to finish alone, and holding the hook's stderr open would keep
# voxcmd waiting for it.
tab_candidates() {
  local tabs_fd
  if names_the_browser "$VOXCMD_ARG_TARGET"; then
    return 0
  fi
  exec {tabs_fd}< <(firefox_rows tabs 2>/dev/null)
  if left_to_others "$VOXCMD_ARG_TARGET"; then
    exec {tabs_fd}<&-
    return 0
  fi
  cat <&"$tabs_fd"
  exec {tabs_fd}<&-
}

# "go to firefox" is the browser window, which Apps focuses.
names_the_browser() {
  [[ "$1" =~ ^((the|my|mozilla|web)\ )*(firefox|browser|web\ browser)$ ]]
}

left_to_others() {
  names_session_or_agent "$1" || spoken_as_keybind "$1"
}

# Duplicated in apps.sh (names_session_or_agent, spoken_as_keybind): each integration's library is sourced alone. Keep
# the two in step: a drift lets a tab and a session or keybind answer the same phrase.
names_session_or_agent() {
  [[ " $1 " =~ \ (session|sessions|agent|agents)\  ]]
}

# True when "<focus form> <target>" is a described Hyprland keybind, compared as word sets: filler and Apps' ignored
# words dropped, number words as digits, plurals singular.
spoken_as_keybind() {
  local phrases=() form
  while IFS= read -r form; do phrases+=("$form $1"); done < <("$VOXCMD_SELF" util intents focus)
  hyprctl binds -j 2>/dev/null | jq -e --args '
    {"one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10"} as $digits
    | (["the", "a", "an", "my", "this", "that", "please", "to", "of", "on", "in", "for", "it", "window", "app", "application", "program"]) as $ignored
    | def singular: if length > 3 and endswith("s") and (endswith("ss") | not) then .[:-1] else . end;
      def words: ascii_downcase | gsub("\u0027"; "") | [splits("[^a-z0-9]+") | select(. != "") | ($digits[.] // .) | singular]
        | map(select(IN($ignored[]) | not)) | unique;
    ($ARGS.positional | map(words)) as $spoken
    | any([.[] | select(.has_description) | .description] | unique | .[] | words; . as $bind | any($spoken[]; . == $bind))
  ' "${phrases[@]}" >/dev/null
}

# Tab in Voice Help lists every tab, once each, by title.
tab_help() {
  "$firefox_tab" candidates tabs "" 2>/dev/null |
    jq -r 'unique_by(.id) | sort_by((.label // "") | ascii_downcase) | .[]
      | select((.id // "") != "") | [.id, (.label // "")] | map(gsub("[\t\n\r]"; " ")) | join("\t")'
}

# The id is "<window address> <tab title>" or "goto <url>".
focus_tab() {
  case "$1" in
  goto\ *) "$firefox_tab" goto "${1#goto }" ;;
  *) "$firefox_tab" focus "${1%% *}" "${1#* }" ;;
  esac
}
