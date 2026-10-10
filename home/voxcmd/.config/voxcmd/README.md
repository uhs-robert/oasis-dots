# voxcmd

Voice commands on top of [voxtype](https://github.com/peteonrails/voxtype). Speak a phrase, voxcmd matches it against the verbs your integrations declare and runs the action. The only integration shipped is `media.sh` (playerctl and pamixer); everything else is a drop-in file you write.

| Key                      | Does                                                     |
| ------------------------ | -------------------------------------------------------- |
| `CTRL + SHIFT + PERIOD`  | Start listening; press again to stop and run the command |
| Leader, `SHIFT + PERIOD` | Same, from the leader menu                               |

```bash
voxcmd listen                     # toggle: start a voxtype recording, or stop it and route the transcript
voxcmd "next track"               # route text directly
voxcmd --dry-run "volume to 40"   # show the match, candidates and command without running anything
voxcmd list                       # integrations and their verbs
```

`listen` records with `voxtype record start --file=...`, so the transcript is written to a file instead of being typed. Dictation keeps working as before.

## How a phrase is routed

1. The transcript is lowercased, punctuation is dropped and whitespace collapsed: `"Set volume to 40%."` becomes `set volume to 40`.
2. Replacement files in `replacements.d/` rewrite whole words, for words the speech model keeps getting wrong.
3. Each integration's verbs are tried in order against the whole phrase; the first match per integration counts.
4. A verb with a target whose integration lists candidates for that action fuzzy-matches the target against them (`fzf --filter`); an exact label wins outright.
5. A target that matches none of the candidates runs the action the integration names for that case in `no_match_actions`, if any.
6. One option runs (after a Yes/No picker if the integration sets `confirm=1`). Several open a picker, the Quickshell one when the bar is running and `rofi -dmenu` otherwise; cancelling does nothing. None sends a "no match" notification.

A notification reports what ran, or the last lines of the error.

## Integrations

Each `~/.config/voxcmd/integrations.d/*.sh` is a bash file sourced in its own subshell:

```bash
name="Windows"     # shown in notifications and the picker; defaults to the file name
confirm=0          # 1 asks before running any of this integration's actions

# "action  pattern": the pattern is an ERE matched against the whole normalized phrase.
# {target} captures free text, {number} digits; at most one per pattern, and put it last.
verbs=(
  "focus  (focus|switch to|go to) {target}"
)

# Commands are eval'd with $id (the chosen candidate's id, else the target) and $target (the spoken text).
declare -A actions=(
  [focus]='hyprctl dispatch "hl.dsp.focus({ window = \"address:$id\" })"'
)

# Optional. Called with the action name for verbs with a target; prints a JSON array of {id, label}.
# Printing nothing means "no candidates, use the target text"; printing [] means nothing can match.
candidates() {
  hyprctl clients -j | jq -c 'map({id: .address, label: "\(.class) \(.title)"})'
}
```

An integration whose targets are open-ended can catch a target that matches no candidate instead of letting it end as "no match":

```bash
# Optional. Maps an action to the one to run when its target matches no candidate; that action gets $target and an empty $id.
declare -A no_match_actions=(
  [open_project]='create_project'
)
```

Patterns are bash ERE, so there are no non-capturing groups; voxcmd finds the target's group by counting the `(` before the placeholder, which is why only one placeholder is allowed. Order verbs from specific to general, as `media.sh` does with `play` before `play {target}`. Integration files are plain shell, so helper functions defined in the file are available to its commands.

The tracked `integrations.d/` and `replacements.d/` ignore everything except what ships, so private integrations dropped into the stowed folders stay out of git.

## Replacements

`~/.config/voxcmd/replacements.d/*` hold `spoken = canonical` lines, applied as whole-word rewrites after normalization (`#` starts a comment):

```
paws = pause
fire fox = firefox
```

voxtype's own `[text.replacements]` run first, at transcription.

## LLM hook

Off by default and a stub: voxcmd never calls a model. Set `VOXCMD_LLM_CMD` to a shell command and, when no verb matches, it receives `{transcript, integrations: [{name, actions, verbs}]}` on stdin and should print `{integration, action, target}`. The answer goes through the same candidate matching and confirmation as a verb match.

## Picker

`voxcmd-pick <label> <choices-json>` is the blocking picker voxcmd uses, usable on its own. Choices are strings or `{id, label}` objects; it prints the picked id and exits 1 on cancel.
