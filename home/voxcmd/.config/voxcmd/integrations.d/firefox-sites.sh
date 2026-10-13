# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Opens a bookmark, a site from history or a domain when "open X" names no app: "open example", "open example.com".
# A fallback, so apps, keybinds and every other integration's "open" come first. Format: ~/.config/voxcmd/README.md

name="Firefox"
fallback=1
silent=1
target_match=words
action_labels=0

verbs=(
  "open_site  {open} {target}"
)

examples=(
  "open <bookmark or site>"
)

declare -A actions=(
  [open_site]='"$voxcmd_share_dir/firefox-tab" open "$id"'
)

# Only sites whose title or name is the target's words, or a domain said alone: unlike "open X in firefox", nothing
# here said a site was meant, so a near miss is no match rather than a picker of pages.
candidates() {
  local all strong
  all=$("$voxcmd_share_dir/firefox-tab" candidates sites "$2" --raw "$raw_transcript" 2>/dev/null) || all='[]'
  strong=$(word_match "$2" "$all" 2>/dev/null)
  jq -c 'reduce (.[] | select(.weak | not) | del(.weak)) as $site ([]; if any(.[]; .id == $site.id) then . else . + [$site] end)' <<<"${strong:-[]}"
}
