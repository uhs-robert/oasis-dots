# shellcheck shell=bash
# Hook library of keybinds.toml: sourced before every hook and action of the integration.

# Binds whose description contains any of these (case-insensitive) are never offered: the voice keys themselves,
# and anything near passwords or secrets.
excluded_descriptions=(
  "voice command"
  "voice help"
  "rapid mode"
  "wake word"
  "speech to text"
  "voxtype"
  "password"
  "passphrase"
  "rbw"
  "bitwarden"
  "secret"
)

# The lists the actions choose from, as {binds, submaps, mode_binds}. binds are the described binds from every submap,
# one per description (the global one when there is one), labelled with the submap they live in. Left out besides the
# exclusions: submap navigation ("+Name" entries, "Back", "Exit <submap>"), one-character descriptions (hyprvim's mark
# and register letters), and lid and other switch binds. submaps are every submap with a bind, entered by name.
# mode_binds are the binds named "<X> mode" that are not a submap ("Command mode (:)"): enter_submap claims every
# "X mode" phrase, so it offers these too or "command mode" could never run its bind.
# An unreachable Hyprland reads as no binds, so every list is empty and the integration yields.
bind_lists() {
  local binds
  binds=$(hyprctl binds -j) || binds='[]'
  jq -c --args '
    ($ARGS.positional | map(ascii_downcase)) as $excluded
    | ([.[].submap | select(. != "")] | unique) as $submap_names
    | ($submap_names | map(ascii_downcase)) as $lowered_submap_names
    | (to_entries
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
    ) as $binds
    | {
        binds: $binds,
        submaps: ($submap_names | map({id: "submap:\(.)", label: "Submap: \(.)", match_text: .})),
        mode_binds: ($binds | map((.match_text | sub("\\s*\\([^)]*\\)$"; "")) as $bare
          | select($bare | test(" mode$"; "i"))
          | ($bare | sub(" mode$"; ""; "i")) as $mode
          | select($mode | ascii_downcase | IN($lowered_submap_names[]) | not)
          | . + {match_text: $mode}))
      }
  ' "${excluded_descriptions[@]}" <<<"$binds" 2>/dev/null || echo '{}'
}

# Verbs that act on the whole machine, and the words that only name it: "lock the computer", "reboot the system" and
# "power off my laptop" mean the Lock, Reboot and Power Off binds. Without this the object is a word the bind lacks,
# which makes it a weak match and puts a picker before the confirmation.
machine_verbs='lock|suspend|sleep|hibernate|reboot|log ?out|log off|power off|shut ?down'
machine_words='computer|pc|laptop|machine|screen|system|session|desktop'

# id<TAB>label<TAB>match_text per candidate, from a JSON array on stdin. Ids are stringified because a bind's `arg` may
# be a number. Tabs and newlines in a description would split the row, and an empty id is no candidate. Prints nothing
# for an empty list, which is how an unreachable Hyprland or a missing bind yields: the spoken text never becomes an id.
candidate_rows() {
  jq -r '.[]
    | select((.id // "" | tostring) != "")
    | [(.id | tostring), (.label // ""), (.match_text // .label // "")] | map(gsub("[\t\n\r]"; " ")) | join("\t")' 2>/dev/null
}

submap_candidates() {
  bind_lists | jq -c '(.submaps // []) + (.mode_binds // [])' | candidate_rows
}

# A machine verb said with a machine word matches a bind named for that verb alone, or for it and a machine word, as if
# the bind said what was spoken. The verbs are compared without spaces, so "log out" is a Logout bind.
# A {focus} form said first ("focus workspace 3", "switch to workspace 3") likewise matches a bind starting with any
# other {focus} form ("Go to Workspace 3"): the forms are one intent, and bind authors pick whichever they like.
bind_candidates() {
  bind_lists | jq -c --arg target "$VOXCMD_ARG_TARGET" --arg verbs "$machine_verbs" --arg machine_words "$machine_words" \
    --argjson focus_forms "$("$VOXCMD_SELF" util intents focus | jq -R -s -c 'split("\n") | map(select(. != ""))')" '
    def squeezed: gsub("[^a-z]"; "");
    def with_spoken_focus_form:
      ([$focus_forms[] | select(. as $form | $target | startswith($form + " "))] | max_by(length)) as $spoken
      | if $spoken == null then . else
          map(.match_text as $text
            | ([$focus_forms[] | select(. as $form | $text | ascii_downcase | startswith($form + " "))] | max_by(length)) as $written
            | if $written == null then . else .match_text = $spoken + $text[($written | length):] end)
        end;
    ([$target | capture("^(?<verb>\($verbs))( (the|my|this))? (\($machine_words))$")] | .[0].verb // "") as $spoken_verb
    | (.binds // [])
    | with_spoken_focus_form
    | if $spoken_verb == "" then . else
        map((.match_text | ascii_downcase) as $description
          | if ($description | test("^(\($verbs))( (\($machine_words)))?$"))
              and ($description | sub(" (\($machine_words))$"; "") | squeezed) == ($spoken_verb | squeezed)
            then .match_text = $target else . end)
      end
    ' | candidate_rows
}

# Tab in Voice Help lists every submap, then "Exit submap" (a static row in keybinds.toml), then every bind.
submap_help() {
  bind_lists | jq -r '(.submaps // [])[] | [.id, .label] | map(gsub("[\t\n\r]"; " ")) | join("\t")'
}

bind_help() {
  bind_lists | jq -r '(.binds // [])[] | select((.id // "" | tostring) != "") | [(.id | tostring), .label] | map(gsub("[\t\n\r]"; " ")) | join("\t")'
}

# A bind is dispatched like Keybind Help does: leave any active submap first, then call the bind through the Lua
# registry. A "submap:<name>" id enters that submap the way its "+Name" bind does, through whichever Submap module
# registered it (the repo's or hyprvim's), so its enter hooks and which-key run; hyprvim's own activation bind clears
# the pending count first, so this does too.
run_keybind() {
  if [[ "$1" == submap:* ]]; then
    local submap_name="${1#submap:}"
    if ! [[ "$submap_name" =~ ^[A-Za-z0-9\ _-]+$ ]]; then
      echo "not a submap: $submap_name"
      return 1
    fi
    hyprctl_eval "
      local name = \"$submap_name\"
      local repo_submaps = package.loaded['lib.key.submap']
      if repo_submaps and repo_submaps.registry[name] then return repo_submaps.enter(name) end
      local hyprvim_submaps = package.loaded['hyprvim.lib.submap']
      if hyprvim_submaps and hyprvim_submaps.registry[name] then
        require('hyprvim.vim').count.clear()
        return hyprvim_submaps.enter(name)
      end
      error('no submap named ' .. name)"
    return
  fi
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "not a keybind: $1"
    return 1
  fi
  hyprctl_eval 'hl.dispatch(hl.dsp.submap("reset"))' || return 1
  if [ "$VOXCMD_CONFIRMED" = 1 ]; then
    run_bind_skipping_power_prompt "$1"
  else
    hyprctl_eval "debug.getregistry()[$1]()"
  fi
}

# The Lock, Logout, Reboot and Power Off binds open the bar's own prompt, a second question after the confirm card
# that only a key can answer. The bind runs with exec_cmd rewriting that prompt's IPC call to the one that runs the
# action, so whatever else it does still happens, and a bind that never opens the prompt is untouched.
run_bind_skipping_power_prompt() {
  hyprctl_eval "
    local exec_cmd = hl.dsp.exec_cmd
    hl.dsp.exec_cmd = function(command, ...)
      if type(command) == 'string' then command = command:gsub(' call power confirm ', ' call power run ') end
      return exec_cmd(command, ...)
    end
    local ok, err = pcall(debug.getregistry()[$1])
    hl.dsp.exec_cmd = exec_cmd
    if not ok then error(err, 0) end"
}

# Back to the global map like the Exit binds, through both Submap modules so the current submap's exit hook runs
# (Cursor restores the cursor settings).
exit_submap() {
  hyprctl_eval "
    local hyprvim_submaps = package.loaded['hyprvim.lib.submap']
    if hyprvim_submaps and hyprvim_submaps.current ~= 'reset' then hyprvim_submaps.reset() end
    local repo_submaps = package.loaded['lib.key.submap']
    if repo_submaps then return repo_submaps.reset() end
    hl.dispatch(hl.dsp.submap('reset'))"
}

# hyprctl eval prints "ok" on success, which would become the notification text, and the error otherwise.
hyprctl_eval() {
  local output
  output=$(hyprctl eval "$1") || {
    echo "$output"
    return 1
  }
}
