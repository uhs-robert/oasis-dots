# shellcheck shell=bash disable=SC2034,SC2016
# Runs any described Hyprland keybind by saying its description. Format: ~/.config/voxcmd/README.md

name="Keybinds"
confirm=0
# Tried only when no other integration can run the phrase, so "close window" works without a verb.
fallback=1
target_match=words
# Words that only say "run a keybind", ignored on both sides: "run close window" is "close window".
match_ignore_words=(run press keybind key bind shortcut "do" trigger)

verbs=(
  "run  {target}"
)

declare -A actions=(
  [run]='run_keybind "$id"'
)

# Binds whose description contains any of these (case-insensitive) are never offered: the voice keys themselves,
# and anything near passwords or secrets.
excluded_descriptions=(
  "voice command"
  "speech to text"
  "voxtype"
  "password"
  "passphrase"
  "rbw"
  "bitwarden"
  "secret"
)

# Regexes (case-insensitive) on the label; a match asks Yes/No before the bind runs.
confirm_labels=(
  '\bclose\b'
  '\bkill'
  '\b(exit|quit) hyprland\b'
  '\blog ?out\b'
  '\bshut ?down\b'
  '\bpower (off|button)\b'
  '\breboot\b'
  '\b(suspend|hibernate|sleep)\b'
  '^lock\b'
  '\block (screen|session)\b'
  '\bdelete\b'
  '\bclear\b'
)

# Described binds from every submap, one per description (the global one when there is one), labelled with the
# submap they live in. Left out besides the exclusions: submap navigation ("+Name" entries, "Back", "Exit <submap>"),
# one-character descriptions (hyprvim's mark and register letters), and lid and other switch binds.
# An unreachable Hyprland prints [] rather than nothing, which would turn the spoken text itself into the bind id.
candidates() {
  local binds
  binds=$(hyprctl binds -j) || binds='[]'
  jq -c --args '
    ($ARGS.positional | map(ascii_downcase)) as $excluded
    | to_entries
    | map(.value + {order: .key})
    | map(select(.has_description and .dispatcher == "__lua" and (.mouse | not) and (.key | startswith("switch:") | not)))
    | map(select(.description as $description | ($description | ascii_downcase) as $lowered
        | ($description | length) > 1
        and ($description | startswith("+") | not)
        and ($lowered != "back" and ($lowered | startswith("back to ") | not))
        and $lowered != ("exit " + (.submap | ascii_downcase))
        and (any($excluded[]; . as $word | $lowered | contains($word)) | not)))
    | group_by(.description | ascii_downcase)
    | map(min_by([.submap != "", .order]))
    | sort_by(.order)
    | map({id: .arg, label: (.description + if .submap != "" then " (\(.submap))" else "" end), match_text: .description})
  ' "${excluded_descriptions[@]}" <<<"$binds" 2>/dev/null || echo '[]'
}

# Dispatched like Keybind Help does: leave any active submap first, then call the bind through the Lua registry.
run_keybind() {
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "not a keybind: $1"
    return 1
  fi
  local output
  output=$(hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))' && hyprctl eval "debug.getregistry()[$1]()") || {
    echo "$output"
    return 1
  }
}
