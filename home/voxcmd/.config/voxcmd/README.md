# voxcmd

Voice commands on top of [voxtype](https://github.com/peteonrails/voxtype). Speak a phrase, voxcmd matches it against the verbs your integrations declare and runs the action. Seven integrations ship: `media.sh` (playerctl and pamixer), `apps.sh` (open apps, focus, move and close windows), `timers.sh` (timers and reminders as systemd user timers), `devices.sh` (audio output, input and per-app volume with wpctl, Bluetooth with bluetoothctl), `system.sh` (brightness, power profile, do not disturb, auto-lock), `answers.sh` (math, time and date questions, and the weather popup) and `keybinds.sh` (any described Hyprland keybind); everything else is a drop-in file you write.

| Key                                | Does                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------ |
| `SUPER + COMMA`, Leader, `COMMA`   | Voice Command: listen, stop [after a pause](#auto-stop), run the command |
| `SUPER + PERIOD`, Leader, `PERIOD` | Speech to Text: dictate until a voice key is pressed again, then type it |
| Leader, `CTRL + SLASH`             | [Voice Help](#voice-help): pick from example phrases                     |

`SUPER` is `Config.leader`, and Leader is the leader menu (`SUPER + SPACE`).

While voxtype records, any voice key only stops it, and the recording's own mode handles what was said: a voice command still runs, dictation is still typed. So `SUPER + COMMA` then `SUPER + PERIOD` runs a command, and `SUPER + PERIOD` then `SUPER + COMMA` types. A key pressed while voxtype transcribes does nothing. Speech to Text pauses playing media and resumes it when its recording ends, whichever key or timeout ends it.

While a voxcmd picker is open, Voice Command records a reply to it instead of a new command (see [Picker](#picker)).

Saying "never mind", "cancel", "forget it" or "nothing" as the whole command runs nothing, without a "no match" notification.

```bash
voxcmd listen                     # start a recording that stops itself after speech and a pause; while voxtype records, stop it
voxcmd "next track"               # route text directly
voxcmd --dry-run "volume to 40"   # show the match, candidates and command without running anything
voxcmd --reply "the second one"   # answer the open voxcmd picker, as a spoken reply would
voxcmd --dry-run --reply "two"    # show which choice a reply would pick
voxcmd list                       # integrations and their verbs
voxcmd help                       # pick from the integrations' example phrases
```

`listen` records with `voxtype record start --file=...`, so the transcript is written to a file instead of being typed. Dictation keeps working as before.

## Auto-stop

A voice command recording, a reply to a picker included, stops itself: `voxcmd-autostop` listens to the default source through `pw-record` and ends the recording once it has heard speech followed by `silence_secs` of quiet. Starting and then thinking for a moment does not stop it, since the pause only counts after speech. Nothing heard within `no_speech_secs` cancels the recording silently. A voice key still stops it early. Dictation has no auto-stop, because people pause while dictating.

Speech is anything `margin_db` above the room, whose level is measured over the first 300ms and then followed over the last two seconds, so a fan or music never counts as speech for long; the threshold never goes below -45 dBFS. Loud sounds shorter than 90ms, like a key click, are not speech. Set `threshold_db` to a fixed level instead when the room fools it.

Settings go in `~/.config/voxcmd/autostop.conf` (`name = value`, `#` comments; ignored by git), and the matching environment variable overrides each:

| Setting          | Environment                      | Default | Meaning                                                   |
| ---------------- | -------------------------------- | ------- | --------------------------------------------------------- |
| `enabled`        | `VOXCMD_AUTOSTOP`                | `true`  | `false` (or `0`, `no`, `off`) stops only with a voice key |
| `silence_secs`   | `VOXCMD_AUTOSTOP_SILENCE_SECS`   | `1.0`   | quiet after speech that ends the recording                |
| `no_speech_secs` | `VOXCMD_AUTOSTOP_NO_SPEECH_SECS` | `6`     | cancel when no speech is heard by then                    |
| `threshold_db`   | `VOXCMD_AUTOSTOP_THRESHOLD_DB`   | `auto`  | speech level in dBFS, e.g. `-35`; `auto` follows the room |
| `margin_db`      | `VOXCMD_AUTOSTOP_MARGIN_DB`      | `12`    | with `auto`, how far above the room speech is             |

To tune it, `voxcmd-autostop --verbose` prints each frame's level and the threshold. Run it while voxtype records, since it gives up after 3s otherwise, or on raw 16 kHz mono s16 audio with `--pcm FILE`. The microphone is released when the recording ends however it ends: stopped, cancelled, at voxtype's `max_duration_secs`, or with voxcmd gone.

## How a phrase is routed

1. The transcript is lowercased, punctuation is dropped and whitespace collapsed: `"Set volume to 40%."` becomes `set volume to 40`.
2. Replacement files in `replacements.d/` rewrite whole words, for words the speech model keeps getting wrong.
   "What can I say", "voice help" and "show voice commands" then open [Voice Help](#voice-help) before any integration is tried, and "never mind", "cancel", "forget it" and "nothing" end there, running nothing.
3. A phrase that starts with an integration's [force prefix](#force-prefixes) skips every other integration and the LLM hook: the rest of the phrase is matched against that integration's verbs alone, whatever its tier, then goes through steps 5, 6 and 8. Nothing matching there is a "no match", with no other integration tried.
4. Each integration's verbs are tried in order against the whole phrase; the first match per integration counts.
5. A verb with a target whose integration lists candidates for that action matches the target against them: fuzzy (`fzf --filter`, an exact label winning outright) or, for an integration with `target_match=words`, [word matching](#word-matching).
6. A target that matches none of the candidates runs the action the integration names for that case in `no_match_actions`, if any.
7. If nothing so far can run, the [LLM hook](#llm-hook) gets a turn, then the [fallback integrations](#fallback-integrations) go through steps 4 to 6.
8. One option runs (after a Yes/No picker if the integration sets `confirm=1` or the option's label matches its `confirm_labels`). Several, or a single weak word match, open a picker, the Quickshell one when the bar is running and `rofi -dmenu` otherwise, which can also be [answered by voice](#answering-by-voice); cancelling does nothing. None sends a "no match" notification with a Voice Help button.

A notification reports what ran, followed by the last line the command printed, if any, or the last lines of the error. Only errors stay in the notification history: a failed action, an action with no command, voxtype not ready or failing to start. Everything else (what ran, answers, "no match", "which one?", "Say: ...") is sent with `--transient`, so the bar shows it and drops it. An action marked [silent](#silent-actions) sends nothing when it succeeds.

## Integrations

Each `~/.config/voxcmd/integrations.d/*.sh` is a bash file sourced in its own subshell:

```bash
name="Windows"     # shown in notifications and the picker; defaults to the file name
confirm=0          # 1 asks before running any of this integration's actions

# "action  pattern": the pattern is an ERE matched against the whole normalized phrase.
# {target} captures free text, {number} digits; at most one per pattern.
verbs=(
  "focus  (focus|switch to|go to) {target}"
)

# Commands are eval'd with $id (the chosen candidate's id, else the target), $target (the spoken text) and
# $raw_transcript (the transcript before normalization and replacements, with its punctuation, digits and symbols).
# The last line a command prints is appended to the notification, so it can say what actually happened.
declare -A actions=(
  [focus]='hyprctl dispatch "hl.dsp.focus({ window = \"address:$id\" })"'
)

# Optional. Example phrases for Voice Help, with placeholders in angle brackets.
examples=(
  "focus <window title>"
)

# Optional. Called with the action name and the spoken target for verbs with a target; prints a JSON array of
# {id, label}. The target lets it list only what that phrase can mean, or [] to leave the phrase to a fallback;
# $raw_transcript is set here too.
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

An integration can also list everything it can run for [Voice Help](#voice-help)'s Tab:

```bash
help_action=focus   # Tab lists candidates "focus" "" and picking one runs focus on it

# Optional. Lists the entries instead, as [{id, label, action}]; action defaults to help_action.
help_choices() {
  hyprctl clients -j | jq -c 'map({id: .address, label: .title})'
}
```

Candidates may also carry `match_text`, the text the target is matched against when it should differ from the label shown (`keybinds.sh` matches the bare description and shows the submap after it).

Optional settings for integrations whose actions differ in risk, or whose targets need stricter matching:

```bash
fallback=1                       # tried only when no other integration can run the phrase
target_match=words               # word matching instead of fzf; see below
match_ignore_words=(run press)   # words dropped from both target and candidates before word matching
action_labels=0                  # leave the action word out of picker labels, for candidate labels that already say what runs
confirm_labels=('\bclose\b' '^lock\b')   # regexes (case-insensitive, jq syntax) on the option's label; a match asks Yes/No
```

Patterns are bash ERE, so there are no non-capturing groups; voxcmd finds the target's group by counting the `(` before the placeholder, which is why only one placeholder is allowed. Order verbs from specific to general, as `media.sh` does with `play` before `play {target}`. Integration files are plain shell, so helper functions defined in the file are available to its commands. voxcmd sources the file inside a function, though, so a `declare` at its top level is gone by the time a command runs: declare an array a helper reads with `declare -g`, as `timers.sh` does for its number words.

The tracked `integrations.d/` and `replacements.d/` ignore everything except what ships, so private integrations dropped into the stowed folders stay out of git.

### Silent actions

An action whose effect is already its feedback, like opening a bar popup, sends no notification on success, since a toast would only cover what it opened. A failure still sends the error.

```bash
silent=1                  # every action of this integration
silent_actions=(weather)  # only these actions
```

`keybinds.sh` is silent: a bind has a visible effect of its own, and many open bar popups. So are `media.sh`'s volume and mute actions, since the bar's volume OSD shows the change; play, pause, next and previous still notify. Opening Voice Help sends nothing either.

### Force prefixes

A phrase starting with one of an integration's `force_prefixes` goes to that integration alone, with the prefix dropped, even when another integration has a verb for the rest. Prefixes are normalized like the phrase and must be followed by at least one word; the first integration (by file name) whose prefix matches wins.

```bash
force_prefixes=(press keybind "key bind")   # "press toggle fullscreen" runs the keybind, never another verb
```

### Fallback integrations

An integration with `fallback=1` is tried only when the normal integrations, and the LLM hook, leave nothing to run: either no verb matched or every match ran out of candidates. That lets a fallback declare a catch-all verb such as `{target}` without making every phrase ambiguous with the integrations that understand it. Fallbacks are matched among themselves like normal integrations.

### Word matching

`target_match=words` is for long candidate lists where a fuzzy hit on scattered letters would run the wrong thing. Both the target and each candidate are lowercased and split into words; filler (`the`, `a`, `to`, `please`, ...) and `match_ignore_words` are dropped, number words become digits and plurals singular. Then:

- **strong**: the same words in any order, or the same letters run together (`full screen` for `fullscreen`). A single strong match runs.
- **weak**: the target's words all name words of the candidate and cover at least half of them (`close` for `Close Window`), or the target holds every candidate word plus one more (`open terminal` for `Terminal`). A spoken word of four letters or more also names a candidate word containing it. Weak matches always open the picker, the best ten first, even when there is only one.
- anything else is no match, so stray speech does nothing.

Strong matches hide weak ones.

### Timers

`timers.sh` sets timers and reminders as transient systemd user timers, `voxcmd-timer-<id>`, which ring through `voxcmd-alarm`: a critical notification (it stays up until dismissed and is kept in history) and the alarm sound, up to three times five seconds apart, stopping once the notification is closed. The sound is the bar's alarm for the current style (`qs-ipc call sound play alarm`), played even with Settings > Sound > Theme audio's notification sound off; without the bar it is the shipped `~/.config/quickshell/sounds/alarm.ogg` through `pw-play` or `paplay`. `VOXCMD_ALARM_RINGS` and `VOXCMD_ALARM_GAP` (seconds) change the count and spacing, in the user manager's environment (`systemctl --user set-environment`).

| Say | Does |
| --- | --- |
| "set a timer for 5 minutes", "timer 90 seconds", "set a 10 minute timer" | A timer; words after the time name it: "timer 10 minutes for the pasta" |
| "remind me in 20 minutes to call the bank", "remind me to stretch at 3 pm" | A reminder, the time before "to" or after the text |
| "list timers", "what timers are running", "how much time is left" | Lists them in the notification, with when each rings and a timer's time left |
| "cancel the timer", "cancel the reminder about the bank", "cancel the pasta timer" | Cancels one; several running open the picker |
| "cancel all timers" | Cancels every voxcmd timer |

- Durations take digits or number words, units of seconds, minutes and hours, and combinations: "an hour and a half", "two and a half minutes", "half an hour", "1 hour 30". The transcript has lost its punctuation by then, so "1.5 hours" arrives as `1 5 hours` and reads as 1.5.
- Clock times are "3 pm", "3:30 p.m.", "15:30", "three thirty pm", "noon", "midnight", optionally "today" or "tomorrow". A time already past today means tomorrow; with no am or pm, whichever of the morning and evening time comes next.
- Everything is scheduled at a wall-clock time (`--on-calendar`), timers too, so one that falls due while the machine sleeps rings on resume instead of late.
- The label is the unit's Description (`Timer: 5 minutes`, `Reminder: Call the bank`), which is how list and cancel find it. `systemctl --user list-timers 'voxcmd-timer-*'` shows the same set.
- Timers live in the user's systemd manager: they outlast voxcmd, but not a logout or reboot.
- Confirmations and the list give the time it rings, in the bar's Settings > Clock time format, with the day when it is not today: "Timer set: 1 minute, rings at 3:47pm", "Reminder tomorrow 9:00am: Call the bank".

### Devices

`devices.sh` switches the default audio output and input, sets the volume of single apps and connects Bluetooth devices.

| Say                                                               | Does                                                   |
| ----------------------------------------------------------------- | ------------------------------------------------------ |
| "switch audio to X", "switch output to X", "use X", "output to X" | `wpctl set-default` on the matching sink               |
| "use the X microphone", "switch mic to X", "set the input to X"   | `wpctl set-default` on the matching source             |
| "connect X", "reconnect X", "disconnect X"                        | `bluetoothctl connect`/`disconnect` on a paired device |
| "bluetooth on", "turn off bluetooth", "enable bluetooth"          | `bluetoothctl power on`/`off`                          |
| "turn Spotify down", "turn up Firefox", "Firefox volume up by 20" | `wpctl set-volume` on the app's streams, 5% a step     |
| "Spotify volume 30", "set Firefox volume to 50 percent"           | `wpctl set-volume` on the app's streams                |
| "mute Firefox", "unmute Spotify"                                  | `wpctl set-mute` on the app's streams                  |

- Sinks and sources come from `pw-dump`, labelled by description plus the device's active route or form factor, `USB Audio Analog Stereo (Speakers)` or `MOMENTUM 3 (Headphones)`, so "use the speakers" and "switch audio to headphones" work without naming the card. Only devices whose label holds every spoken word are offered, so "use the headset" with no headset matches nothing rather than an HDMI output by scattered letters. Several matches open the picker.
- Playing streams follow the new default through WirePlumber's `linking.follow-default-target`; a stream an app pinned to a device stays where it is.
- Bluetooth devices come from `bluetoothctl devices Paired`, labelled with their kind from BlueZ's icon (`Headphones`, `Keyboard`, `Mouse`, ...). `connect` powers the adapter on first.
- Tab on its Voice Help entries lists every output and input; picking one makes it the default. Bluetooth devices are not listed there, since labelling them asks BlueZ about each one.
- Plain "switch to X" is left to app switching, so output switching always says what it switches.
- An app has a volume only while it plays something: its PipeWire playback streams are what change, and an app with none has nothing to set. "turn Spotify down" with Spotify paused or closed says Spotify is not playing anything; a name that is no running app or command, such as "turn brightness down", is left to the other integrations.
- Apps are named by `application.name` and matched on their binary too, so an Electron app that calls itself Chromium still answers to its own name. All of an app's streams (every Firefox tab) change together.
- Volume is clamped to 0..100% of the stream's own volume, never boosted. Plain "volume up", "turn it up", "mute" and "volume 40" stay with Media, which sets the system volume.

### Keybinds

`keybinds.sh` is a fallback integration over `hyprctl binds -j`, so any phrase no other integration takes is matched against keybind descriptions: "close window", "toggle fullscreen", "go to workspace two". `run`, `press`, `keybind`, `do` and `trigger` are ignored words, so "run close window" is the same phrase.

As a fallback it never sees a phrase another integration takes. Starting the phrase with "press", "keybind" or "key bind" ([force prefixes](#force-prefixes)) sends it here first and only: "press open terminal" runs the Open Terminal bind even when another integration has a verb for "open terminal".

- Binds from every submap are offered, one per description, preferring the global one; a submap bind is labelled with its submap, `Lock (System)`. Submap navigation (`+Name`, `Back`, `Exit <submap>`), one-character descriptions and lid switches are left out; the phrases below take its place.
- "submap X", "X submap", "X mode", "enter X mode" or "enter the X submap" enter the submap named X, word matched against the submap names which-key shows (`cursor mode` is Cursor, `normal mode` is hyprvim's NORMAL). A name shared by several submaps (Delete and hyprvim's DELETE) opens the picker; a name that is no submap is a "no match". "X mode" also reaches a bind named "X mode" that is not a submap (`command mode`). As a fallback, these lose to any other integration's verb, so "performance mode" still sets the power profile.
- "exit submap", "leave the submap" or "reset submap" go back to the global map like the Exit binds. The voice key is not bound inside submaps, so these are for submaps that keep global keys, the CLI and Voice Help.
- `excluded_descriptions` hides the voice binds themselves and anything about passwords or secrets; edit the list in the file.
- `confirm_labels` asks before closing, killing, locking, logging out, powering off, rebooting, suspending, deleting or clearing.
- A bind that runs sends no notification ([silent](#silent-actions)); one that fails does.
- Tab on its Voice Help entries lists every submap (`Submap: Cursor`), "Exit submap" and every offered bind; picking one runs it as saying it would.
- A bind runs like Keybind Help runs it: the submap is reset, then `hyprctl eval 'debug.getregistry()[<arg>]()'`.
- A submap is entered like its `+Name` bind enters it, by `hyprctl eval` calling `enter` on the Submap module that registered it (the Hyprland config's `lib.key.submap` or hyprvim's), so its enter hooks and which-key run. Exiting calls their `reset`, which runs the current submap's exit hook.

### Apps

`apps.sh` opens installed apps and works on open windows, with word matching:

| Say                                                            | Does                                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------ |
| "open firefox", "launch slack", "start thunar"                 | focuses the app's most recent window if it has one, else starts it |
| "open new firefox", "open a new kitty"                         | always starts it                                                   |
| "focus slack", "switch to firefox", "go to tmux config"        | focuses the window                                                 |
| "move slack to workspace 3", "send firefox to workspace three" | moves the window there, leaving focus where it is                  |
| "close slack", "close the firefox window"                      | closes the window, after a Yes/No                                  |

- Apps are the desktop entries in `$XDG_DATA_HOME` and `$XDG_DATA_DIRS` (the first copy of an id wins), leaving out `NoDisplay`, `Hidden` and entries `OnlyShowIn`/`NotShowIn` keep off this desktop. An app matches by its `Name` and by the last part of its id (`code`, `nautilus`). It starts like the Quickshell apps picker starts it: the `Exec` line without field codes, in `Path`, and `Terminal=true` apps in the Hyprland config's terminal wrapper.
- An app counts as running when a window's class is its `StartupWMClass`, its id or the last part of its id.
- Windows come from `hyprctl clients -j` and match by app name (the desktop entry's `Name`, else the class) or by title. Several matching windows open the picker, labelled with their titles.
- `window`, `app`, `application` and `program` are ignored words, so "close window" and "open application" are left to the keybinds. A phrase that is a described keybind ("close browsers", "focus left", "go to workspace 2", "start menu") is left to them too, even when a window or app would match it, and so is "open X" when X is a bind's whole description and names no app ("open files" for a `Files` bind; "open firefox" stays here).
- Opening and focusing are [silent](#silent-actions), since the window that opens or takes focus shows it; moving and closing still say what they did.
- Tab on its Voice Help entries lists every installed app; picking one opens it like "open <app>".
- A target with the word `session` or `agent` in it matches nothing, so "switch to the X session" and "go to the X agent" are left to the integrations for those.

### System

`system.sh` sets system values through what the keys and the bar already use, so the OSD and bar stay in sync:

| Say                                                                          | Does                                                                                   |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| "brightness 40", "set brightness to 40 percent"                              | `brightnessctl set 40%` (clamped to 1-100), then `qs-ipc call brightness refresh` for the OSD |
| "brightness up" / "down" (optionally "by 20"), "brighter", "dimmer"          | 10% steps by default, like the brightness keys                                         |
| "brightness max" / "min", "full brightness"                                  | 100% / 1%                                                                              |
| "power saver", "balanced", "performance mode", "set power profile to X"      | `powerprofilesctl set`; X is matched against the profiles the machine offers           |
| "do not disturb on" / "off", "silence notifications", "notifications on"     | The bar's do not disturb, over `qs-ipc` `notifications get_dnd` / `toggle_dnd`         |
| "keep the screen awake", "caffeine on" / "off", "enable" / "disable autolock" | Stops or starts hypridle with `toggle-autolock.sh`, like the System submap's auto-lock key |

Brightness and do not disturb send no notification when they work ([silent](#silent-actions)), since the OSD and the bar's indicator show them; power profile and auto-lock still say what they set. Only the laptop backlight is driven; external monitors are not (no DDC/CI). A spoken power profile lasts until the next AC or battery change, when `power.sh` applies the one chosen in Settings, unless that is "keep".

### Answers

`answers.sh` answers math, time and date questions in the notification and opens the bar's weather popup for weather questions, with filler such as `hey`, `um`, `can you tell me` and a trailing `please` allowed around them:

| Say                                                                                                  | Answer                                                         |
| ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| "what's 15 percent of 230", "calculate 12 times 37", "convert 5 miles to km", "how many feet in a mile" | `qalc -t` result, also copied with `wl-copy`                   |
| "what time is it", "what's the time"                                                                 | the time, in the Settings > Clock format                       |
| "what's the date", "what day is it"                                                                  | `Saturday, October 10, 2026`                                   |
| "what's the weather", "how's the weather", "weather", "will it rain today", "do I need an umbrella"    | opens the Quickshell weather popup                             |

- Math is read from `$raw_transcript`, since normalizing drops `%`, `×`, `/` and decimal points. Number words become digits ("two hundred thirty point five"), and `times`, `divided by`, `plus`, `minus`, `squared`, `cubed`, `to the power of`, `square root of`, `percent of`, `half of`, `factorial` and `modulo` become qalc syntax.
- "what's" and "how much is" count as math only when a number follows, so "what's up" is left for the other integrations. Without a `to` (from "to", "in" or "into") qalc runs with units off, so a word it cannot place fails instead of becoming a unit.
- Weather opens the popup the Leader `W` (Weather) bind opens, with `~/.config/hypr/scripts/qs-ipc call popup open weather`, so it needs the Quickshell bar running.

## Voice Help

`voxcmd help` (leader `CTRL + SLASH`, saying "voice help" or "what can I say", or the button on a "no match" notification) shows every integration's `examples` in the picker, labelled with the integration's name and with fallback integrations last. Picking a phrase without placeholders runs it as if it had been spoken. A phrase with a placeholder (`set volume to <number>`) cannot be completed from a click, so it comes back as a "Say: ..." notification instead.

Tab on an entry of an integration that sets `help_action` or `help_choices` replaces the list with everything that integration can run, titled with its name (Keybinds: every submap and described bind), like Tab completing a command in HyprVim's prompt. Such entries show `Tab: <name> (<count>)`; Tab on the others does nothing. The list searches like any picker list, picking an entry runs it like the spoken phrase would (asking first where the integration's `confirm_labels` say so), and Backspace on an empty search goes back to the examples with the search and row restored. The rofi fallback shows the examples only.

The button works with any notification daemon that supports actions, the bar's included: `notify-send --action` waits for the notification to close, so a detached process waits on it instead of voxcmd.

## Replacements

`~/.config/voxcmd/replacements.d/*` hold `spoken = canonical` lines, applied as whole-word rewrites after normalization (`#` starts a comment):

```
paws = pause
fire fox = firefox
```

voxtype's own `[text.replacements]` run first, at transcription.

## LLM hook

Off by default and a stub: voxcmd never calls a model. Set `VOXCMD_LLM_CMD` to a shell command and, when no normal integration has anything to run, it receives `{transcript, integrations: [{name, actions, verbs}]}` on stdin and should print `{integration, action, target}`. The answer goes through the same candidate matching and confirmation as a verb match. Fallback integrations are tried only after it.

## Picker

`voxcmd-pick <label> <choices-json> [<expansions-json>]` is the blocking picker voxcmd uses, usable on its own. Choices are strings or `{id, label}` objects; it prints the picked id and exits 1 on cancel. Labels are shown numbered (`1. Acme Labs`); the number never reaches the printed id.

Expansions are `{key: {title, choices}}`, and a choice with `expand: key` opens that list on Tab in the Quickshell picker; its ids come back like any other. The picker writes the key it shows to a view file, so a voice reply answers from the list on screen.

### Answering by voice

Press the Voice Command key while a voxcmd picker is open and speak a reply; the recording stops itself after it, like a command. It can be:

- a choice's label, matched like targets are (exact, then substring, then fuzzy); it must single out one choice;
- an ordinal: `two`, `the second one`, `number 3`, `first`, `last`;
- `cancel`, `never mind` or `none`, which cancel like Esc.

A recording started while a picker waits is always a reply, so `cancel` there closes the picker rather than being discarded as a command.

The reply picks as if the choice had been clicked and closes the picker. A reply that matches nothing or several choices leaves the picker open and sends a notification; press the key again to retry.

While it waits, `voxcmd-pick` keeps `$XDG_RUNTIME_DIR/voxcmd/pending-pick.json` (`{pid, fifo, label, choices, expansions, view}`) and removes it when the pick ends however it ends. A file whose owner is gone is ignored. The reply goes into the picker's result FIFO, so `voxcmd-pick` closes the picker itself afterwards: the Quickshell one over `qs-ipc call picker close`, rofi by ending it.

Hyprland still runs binds while the Quickshell picker has the keyboard. rofi asks the compositor to inhibit shortcuts while it is open, and Hyprland honours that unless `binds:disable_keybind_grabbing` is set, so with the rofi fallback the key does nothing until rofi closes; pick with the keyboard or mouse there.
