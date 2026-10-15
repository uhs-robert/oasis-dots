# shellcheck shell=bash disable=SC2034,SC2016
# Runs any described Hyprland keybind by saying its description. Format: ~/.config/voxcmd/README.md

name="Keybinds"
confirm=0
# Tried only when no other integration can run the phrase, so "close window" works without a verb.
fallback=1
# A bind's own effect is the feedback, often a bar popup that a success toast would cover.
silent=1
target_match=words
# "keybind toggle fullscreen" comes straight here even when another integration has a verb for "toggle fullscreen".
# "press" is only an ignored word, not a prefix: "press enter" is a key press (keys.sh), and "press <description>" still
# lands here, since no other integration's verb starts with "press".
force_prefixes=(keybind "key bind")
# Words that only say "run a keybind", ignored on both sides: "run close window" is "close window". "open" and
# "launch" are here because launcher binds are named for what they open ("Terminal"), so "open terminal" is that bind.
# "activate" and "engage" are the one-word {activate} forms that never start a description the way "start" or "enable" can.
match_ignore_words=(run press keybind key bind shortcut "do" trigger open launch activate engage a an any some new)

# Candidate labels name what runs ("Close Window", "Submap: Cursor"), so pickers leave the action word out.
action_labels=0

# Submap phrases before the catch-all, so "cursor mode" enters the Cursor submap rather than matching binds.
verbs=(
  "exit_submap   ({deactivate}|reset|quit) (the )?(current )?submap( mode)?"
  "enter_submap  (({activate}|{focus}|open) )?(the )?submap {target}"
  "enter_submap  (({activate}|{focus}|open) )?(the )?{target} (submap|mode)"
  "run           {target}"
)

# A few common binds rather than the whole list, which "<any keybind description>" stands for.
examples=(
  "toggle fullscreen"
  "close window"
  "go to workspace <number>"
  "cursor mode"
  "activate <submap name> submap"
  "exit submap"
  "<any keybind description>"
  "press <keybind description>"
)

declare -A actions=(
  [run]='run_keybind "$id"'
  [enter_submap]='run_keybind "$id"'
  [exit_submap]='exit_submap'
)

# Tab on these examples in Voice Help lists every submap and every bind help_choices() offers, and picking one runs it.
help_action=run

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
  # Not the Delete submaps, whose entry deletes nothing.
  '^(?!Submap: ).*\bdelete\b'
  '\bclear\b'
)

# The lists the actions choose from, as {binds, submaps, mode_binds}. binds are the described binds from every submap,
# one per description (the global one when there is one), labelled with the submap they live in. Left out besides the
# exclusions: submap navigation ("+Name" entries, "Back", "Exit <submap>"), one-character descriptions (hyprvim's mark
# and register letters), and lid and other switch binds. submaps are every submap with a bind, entered by name.
# mode_binds are the binds named "<X> mode" that are not a submap ("Command mode (:)"): enter_submap claims every
# "X mode" phrase, so it offers these too or "command mode" could never run its bind.
# An unreachable Hyprland prints [] rather than nothing, which would turn the spoken text itself into the bind id.
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

# A machine verb said with a machine word matches a bind named for that verb alone, or for it and a machine word, as if
# the bind said what was spoken. The verbs are compared without spaces, so "log out" is a Logout bind.
candidates() {
  case "$1" in
  enter_submap) bind_lists | jq -c '(.submaps // []) + (.mode_binds // [])' ;;
  *)
    bind_lists | jq -c --arg target "$2" --arg verbs "$machine_verbs" --arg machine_words "$machine_words" '
      def squeezed: gsub("[^a-z]"; "");
      ([$target | capture("^(?<verb>\($verbs))( (the|my|this))? (\($machine_words))$")] | .[0].verb // "") as $spoken_verb
      | (.binds // [])
      | if $spoken_verb == "" then . else
          map((.match_text | ascii_downcase) as $description
            | if ($description | test("^(\($verbs))( (\($machine_words)))?$"))
                and ($description | sub(" (\($machine_words))$"; "") | squeezed) == ($spoken_verb | squeezed)
              then .match_text = $target else . end)
        end'
    ;;
  esac
}

help_choices() {
  bind_lists | jq -c '(.submaps // []) + [{id: "", label: "Exit submap", action: "exit_submap"}] + (.binds // [])'
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
  if [ "${confirmed:-0}" = 1 ]; then
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
