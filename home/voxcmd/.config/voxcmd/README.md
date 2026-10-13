# voxcmd

Voice commands on top of [voxtype](https://github.com/peteonrails/voxtype). Speak a phrase, voxcmd matches it against the verbs your integrations declare and runs the action. The integrations that ship, and how to write your own as a drop-in file, are under [Integrations](#integrations).

| Key                                | Does                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------ |
| `SUPER + COMMA`, Leader, `COMMA`   | Voice Command: listen, stop [after a pause](#auto-stop), run the command |
| `SUPER + PERIOD`, Leader, `PERIOD` | Speech to Text: dictate until a voice key is pressed again, then type it |
| `SUPER + SHIFT + COMMA`, Leader, `SHIFT + COMMA` | [Stop Voice](#stop-voice): end the session, picker and recording, running nothing |
| Leader, `CTRL + SLASH`             | [Voice Help](#voice-help): pick from example phrases                     |

`SUPER` is `Config.leader`, and Leader is the leader menu (`SUPER + SPACE`).

While voxtype records, any voice key only stops it, and the recording's own mode handles what was said: a voice command still runs, dictation is still typed. So `SUPER + COMMA` then `SUPER + PERIOD` runs a command, and `SUPER + PERIOD` then `SUPER + COMMA` types. A key pressed while voxtype transcribes does nothing. Speech to Text pauses playing media and resumes it when its recording ends, whichever key or timeout ends it.

While a voxcmd picker or confirm card is open, Voice Command records a reply to it instead of a new command (see [Picker](#picker) and [Confirm](#confirm)).

Saying "never mind", "cancel", "forget it" or "nothing" as the whole command runs nothing, without a "no match" notification.

```bash
voxcmd listen                     # start a recording that stops itself after speech and a pause; while voxtype records, stop it
voxcmd "next track"               # route text directly
voxcmd --dry-run "volume to 40"   # show the match, candidates and command without running anything
voxcmd --reply "the second one"   # answer the open voxcmd picker or confirm card, as a spoken reply would
voxcmd --dry-run --reply "two"    # show which choice a reply would pick
voxcmd end-session                # end the open voice session (click mode), if any
voxcmd stop                       # stop all voice activity: session, picker or card, and any recording (see Stop Voice)
voxcmd list                       # integrations and their verbs
voxcmd help                       # pick from the integrations' example phrases
voxcmd errors 5                   # the last 5 voxcmd notifications the bar kept, newest first (default 10)
```

`listen` records with `voxtype record start --file=...`, so the transcript is written to a file instead of being typed. Dictation keeps working as before.

`errors` reads the bar's notification history (`qs-ipc call notifications history N voxcmd`) and prints one line per notification: local date and time (in the Settings > Clock format), summary and body. voxcmd sends what ran, answers and hints as transient notifications, which the bar never keeps, so these are its errors ("voxcmd failed", "voxcmd error", voxtype not ready). It prints "bar not running" and exits 1 when the IPC call fails.

## Auto-stop

A voice command recording, a reply to a picker included, stops itself: `voxcmd-autostop` listens to the default source through `pw-record` and ends the recording once it has heard speech followed by `silence_secs` of quiet. Starting and then thinking for a moment does not stop it, since the pause only counts after speech. Nothing heard within `no_speech_secs` cancels the recording silently; voxtype drops a recording without speech too (Silero VAD), before Whisper can make words of it. A voice key still stops it early. Dictation has no auto-stop, because people pause while dictating.

Speech is anything `margin_db` above the room, whose level is measured over the first 300ms and then followed over the last two seconds, so a fan or music never counts as speech for long; the threshold never goes below -45 dBFS. A word said as the recording starts is first taken for the room, so until speech is heard every frame so far is scored again as the room level settles, and a lone "yes" at the start still counts. The frames are scored again before a pause ends the recording too: a microphone's first fraction of a second is often quieter than the room, which makes a steady fan sound like speech until the room level catches up, and against the real room that fan is no speech at all. Loud sounds shorter than 90ms, like a key click, are not speech, and speech must add up to `min_speech_secs` before a pause can end the recording. Speech short of that is a short word, not nothing: from `no_speech_secs` on any speech will do, so the recording stops after its pause and is transcribed instead of cancelled. A reply to a picker or confirm card wants only 0.1 s (`VOXCMD_REPLY_MIN_SPEECH_SECS`), so "yes" or "two" ends on its pause. Set `threshold_db` to a fixed level instead when the room fools it.

Settings go in `~/.config/voxcmd/autostop.conf` (`name = value`, `#` comments; ignored by git), and the matching environment variable overrides each:

| Setting           | Environment                       | Default | Meaning                                                   |
| ----------------- | --------------------------------- | ------- | --------------------------------------------------------- |
| `enabled`         | `VOXCMD_AUTOSTOP`                 | `true`  | `false` (or `0`, `no`, `off`) stops only with a voice key |
| `silence_secs`    | `VOXCMD_AUTOSTOP_SILENCE_SECS`    | `1.0`   | quiet after speech that ends the recording                |
| `min_speech_secs` | `VOXCMD_AUTOSTOP_MIN_SPEECH_SECS` | `0.25`  | speech needed before a pause ends the recording           |
| `no_speech_secs`  | `VOXCMD_AUTOSTOP_NO_SPEECH_SECS`  | `6`     | cancel when no speech is heard by then                    |
| `threshold_db`    | `VOXCMD_AUTOSTOP_THRESHOLD_DB`    | `auto`  | speech level in dBFS, e.g. `-35`; `auto` follows the room |
| `margin_db`       | `VOXCMD_AUTOSTOP_MARGIN_DB`       | `12`    | with `auto`, how far above the room speech is             |

`voxcmd-autostop --check` exits 0 when auto-stop is on and can listen, else 1 saying why; a [voice session](#voice-sessions) asks it before opening. To tune it, `voxcmd-autostop --verbose` prints each frame's level and the threshold. Run it while voxtype records, since it gives up after 3s otherwise, or on raw 16 kHz mono s16 audio with `--pcm FILE`. With the [debug log](#debug-log) on it appends a summary there: the room and threshold it calibrated, each run of frames it counted as speech (start, length, mean and peak level, the threshold then), speech it set aside as noise, and its verdict with the room, threshold and speech total at the end. The microphone is released when the recording ends however it ends: stopped, cancelled, at voxtype's `max_duration_secs`, or with voxcmd gone.

## How a phrase is routed

1. The transcript is lowercased, punctuation is dropped and whitespace collapsed: `"Set volume to 40%."` becomes `set volume to 40`.
2. Replacement files in `replacements.d/` rewrite whole words, for words the speech model keeps getting wrong.
   "What can I say", "voice help" and "show voice commands" then open [Voice Help](#voice-help) before any integration is tried, and "never mind", "cancel", "forget it" and "nothing" end there, running nothing.
3. A phrase that starts with an integration's [force prefix](#force-prefixes) skips every other integration and the LLM hook: the rest of the phrase is matched against that integration's verbs alone, whatever its tier, then goes through steps 5, 6 and 8. Nothing matching there is a "no match", with no other integration tried.
4. Each integration's verbs are tried in order against the whole phrase; the first match per integration counts.
5. A verb with a target whose integration lists candidates for that action matches the target against them: fuzzy (`fzf --filter`, an exact label winning outright) or, for an integration with `target_match=words`, [word matching](#word-matching).
6. A target that matches none of the candidates runs the action the integration names for that case in `no_match_actions`, if any. A [word matching](#word-matching) target with no words left after the filler and `match_ignore_words` are dropped names nothing, so it runs no such action and the phrase can fall through to the fallbacks.
7. If nothing so far can run, the [LLM hook](#llm-hook) gets a turn, then the [fallback integrations](#fallback-integrations) go through steps 4 to 6.
8. One option runs (after a [confirm card](#confirm) if the integration sets `confirm=1` or the option's label matches its `confirm_labels`). Several, or a single weak word match, open a picker, the Quickshell one when the bar is running and `rofi -dmenu` otherwise, which can also be [answered by voice](#answering-by-voice); cancelling does nothing. None sends a "no match" notification with a Voice Help button.

A notification reports what ran, followed by the last line the command printed, if any, or the last lines of the error. Only errors stay in the notification history: a failed action, an action with no command, voxtype not ready or failing to start. Everything else (what ran, answers, "no match", "which one?", "Say: ...") is sent with `--transient`, so the bar shows it and drops it. An action marked [silent](#silent-actions) sends nothing when it succeeds.

## Integrations

Each `~/.config/voxcmd/integrations.d/*.sh` is a bash file sourced in its own subshell:

```bash
name="Windows"     # shown in notifications and the picker; defaults to the file name
confirm=0          # 1 asks before running any of this integration's actions

# "action  pattern": the pattern is an ERE matched against the whole normalized phrase.
# {target} captures free text, {number} digits; at most one per pattern. {focus} is an intent (see Intents).
verbs=(
  "focus  {focus} {target}"
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

An integration whose options sit on screen can ask several matches to be shown there instead of listed as text:

```bash
pick_command=voxcmd-hints   # a blocking picker called like voxcmd-pick, found beside voxcmd or on PATH

# Prints "<left> <top> <width> <height>" in global logical pixels for an option id, or fails when it has none.
pick_box() {
  IFS=, read -r _ _ _ left top width height <<<"$1"
  echo "$left $top $width $height"
}
```

When every option of a pick comes from one integration with both, each choice gains `box: [left, top, width, height]` and `pick_command` asks it, with `Which one?`, instead of `voxcmd-pick`. A command that came by voice passes `--listen` to it whatever the number of options, since the user is looking at the choices. If any option has no box the text picker asks as usual. The command must be named `voxcmd-hints` (or `voxcmd-pick`/`voxcmd-confirm`) to be found by `voxcmd --reply`, which looks for those in the pending-pick owner's command line.

Candidates may also carry `match_text`, the text the target is matched against when it should differ from the label shown (`keybinds.sh` matches the bare description and shows the submap after it).

Optional settings for integrations whose actions differ in risk, or whose targets need stricter matching:

```bash
fallback=1                       # tried only when no other integration can run the phrase
target_match=words               # word matching instead of fzf; see below
match_ignore_words=(run press)   # words dropped from both target and candidates before word matching
action_labels=0                  # leave the action word out of picker labels, for candidate labels that already say what runs
confirm_labels=('\bclose\b' '^lock\b')   # regexes (case-insensitive, jq syntax) on the option's label; a match asks first
```

Patterns are bash ERE, so there are no non-capturing groups; voxcmd finds the target's group by counting the `(` before the placeholder (an escaped `\(` does not count), which is why only one placeholder is allowed. Intents are expanded before that count, so they can sit anywhere in a pattern. Order verbs from specific to general, as `media.sh` does with `play` before `play {target}`. Integration files are plain shell, so helper functions defined in the file are available to its commands. voxcmd sources the file inside a function, though, so a `declare` at its top level is gone by the time a command runs: declare an array a helper reads with `declare -g`, as `spoken-time.sh` does for its number words.

Helpers several integrations share live in `~/.local/share/voxcmd/`, since every file in `integrations.d/` is loaded as an integration; an integration sources one from `$voxcmd_share_dir`, which voxcmd resolves from its own real path. `spoken-time.sh` holds the spoken clock-time parser (`parse_clock`: "3 pm", "three thirty pm", "noon", "9 am tomorrow", "friday at 9"), the duration and day parsers (`parse_duration`, `parse_day`), the formatters for the times it prints (`format_at`, `format_length`) and the bar's clock format (`clock_time_format`), used by `timers.sh`, `answers.sh` and `calendar.sh`.

The tracked `integrations.d/` and `replacements.d/` ignore everything except what ships, so private integrations dropped into the stowed folders stay out of git.

### Intents

Verbs that mean the same thing in several integrations are written once, as an intent in braces: `{open} {target}`, `({activate} )?(the )?caffeine`. voxcmd expands each to a group of its spoken forms, so a synonym added to an intent reaches every integration that uses it. The verb narrows, the noun decides: "start" opens an app, turns on caffeine and starts a recording, and the words after it pick which.

| Intent         | Spoken forms                                                                  |
| -------------- | ----------------------------------------------------------------------------- |
| `{open}`       | open, launch, start, bring up, pull up                                        |
| `{show}`       | show, display, open, bring up, pull up                                        |
| `{focus}`      | focus, go to, switch to, jump to, take me to                                  |
| `{activate}`   | activate, enter, turn on, switch on, enable, engage, start                    |
| `{deactivate}` | deactivate, exit, leave, turn off, switch off, disable, disengage, end        |
| `{close}`      | close, quit, kill                                                             |
| `{set}`        | set, change, make, adjust                                                     |
| `{start}`      | start, begin, kick off                                                        |
| `{stop}`       | stop, end, finish                                                             |

The list lives in `voxcmd` itself (`intents`). Words of an integration's own, like Media's "play" and "pause" or Timers' "remind me", stay in its patterns. `intent_forms <intent>` prints an intent's forms one per line, for an integration that rebuilds phrases from them (`apps.sh` checks "<form> <target>" against the keybinds).

`~/.config/voxcmd/intents.local` (ignored by git) adds forms without editing the repo, one intent per line, normalized like the phrase:

```
focus = hop over to, zip to
close = shut
```

A name that is no intent yet declares a new one for your own integrations; `target` and `number` are placeholders and cannot be intents.

### Silent actions

An action whose effect is already its feedback, like opening a bar popup, sends no notification on success, since a toast would only cover what it opened. A failure still sends the error.

```bash
silent=1                  # every action of this integration
silent_actions=(weather)  # only these actions
```

An integration whose option labels hold private text, such as the screen text `click.sh` reads, sets `private_labels=1`. The error toast, which the bar keeps in its history, then names only the integration and action ("Click: click: wlrctl: no seat") and the debug log leaves the label out too; the command's own failure reason still follows.

```bash
private_labels=1          # error toasts leave out the option's label
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
- **weak**: the target's words all name words of the candidate and cover at least half of them (`close` for `Close Window`), or the target holds every candidate word plus one more (`open terminal` for `Terminal`). A spoken word of four letters or more also names a candidate word containing it. Weak matches always open the picker, the best ten first, even when there is only one. A single weak match from a spoken command [listens for the answer](#answering-by-voice) on its own.
- anything else is no match, so stray speech does nothing.

Strong matches hide weak ones.

### Timers

`timers.sh` sets timers and reminders as transient systemd user timers, `voxcmd-timer-<id>`, which ring through `voxcmd-alarm`: a critical notification (it stays up until dismissed and is kept in history) and the alarm sound, up to three times five seconds apart, stopping once the notification is closed. The sound is the bar's alarm for the current style (`qs-ipc call sound play alarm`), played even with Settings > Sound > Theme audio's notification sound off; without the bar it is the shipped `~/.config/quickshell/sounds/alarm.ogg` through `pw-play` or `paplay`. `VOXCMD_ALARM_RINGS` and `VOXCMD_ALARM_GAP` (seconds) change the count and spacing, in the user manager's environment (`systemctl --user set-environment`).

| Say | Does |
| --- | --- |
| "set a timer for 5 minutes", "timer 90 seconds", "set a 10 minute timer" | A timer; words after the time name it: "timer 10 minutes for the pasta" |
| "set a timer for 3 pm", "timer for three thirty", "set a timer for noon tomorrow" | A timer that rings at that time |
| "remind me in 20 minutes to call the bank", "remind me to stretch at 3 pm" | A reminder, the time before "to" or after the text |
| "list timers", "what timers are running", "how much time is left" | Lists them in the notification, with when each rings and a timer's time left |
| "cancel the timer", "cancel the reminder about the bank", "cancel the pasta timer" | Cancels one; several running open the picker |
| "cancel all timers" | Cancels every voxcmd timer |

- Durations take digits or number words, units of seconds, minutes and hours, and combinations: "an hour and a half", "two and a half minutes", "half an hour", "1 hour 30". The transcript has lost its punctuation by then, so "1.5 hours" arrives as `1 5 hours` and reads as 1.5.
- A timer phrase that names no time, like "start a timer for acme", is left to the other integrations (a time tracker's "start a timer for <client>"), so with nothing else matching it is a "no match", not a timer.
- Clock times are "3 pm", "3:30 p.m.", "15:30", "three thirty pm", "noon", "midnight", optionally "today" or "tomorrow". A time already past today means tomorrow; with no am or pm, whichever of the morning and evening time comes next.
- Everything is scheduled at a wall-clock time (`--on-calendar`), timers too, so one that falls due while the machine sleeps rings on resume instead of late.
- The label is the unit's Description (`Timer: 5 minutes`, `Timer: 3:00pm`, `Reminder: Call the bank`), which is how list and cancel find it. `systemctl --user list-timers 'voxcmd-timer-*'` shows the same set.
- Timers live in the user's systemd manager: they outlast voxcmd, but not a logout or reboot.
- Confirmations and the list give the time it rings, in the bar's Settings > Clock time format, with the day when it is not today: "Timer set: 1 minute, rings at 3:47pm", "Timer set for 3:00pm", "Reminder tomorrow 9:00am: Call the bank".

### Devices

`devices.sh` switches the default audio output and input, sets the volume of single apps and connects Bluetooth devices.

| Say                                                               | Does                                                   |
| ----------------------------------------------------------------- | ------------------------------------------------------ |
| "switch audio to X", "switch output to X", "use X", "output to X" | `wpctl set-default` on the matching sink               |
| "use the X microphone", "switch mic to X", "set the input to X"   | `wpctl set-default` on the matching source             |
| "connect X", "reconnect X", "disconnect X"                        | `bluetoothctl connect`/`disconnect` on a paired device |
| "bluetooth on", "turn off bluetooth", "activate bluetooth"        | `bluetoothctl power on`/`off`                          |
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

`keybinds.sh` is a fallback integration over `hyprctl binds -j`, so any phrase no other integration takes is matched against keybind descriptions: "close window", "toggle fullscreen", "go to workspace two". `run`, `press`, `keybind`, `do`, `trigger`, `activate` and `engage` are ignored words, so "run close window" and "activate toggle fullscreen" are the same phrase as the bare description.

As a fallback it never sees a phrase another integration takes. Starting the phrase with "press", "keybind" or "key bind" ([force prefixes](#force-prefixes)) sends it here first and only: "press open terminal" runs the Open Terminal bind even when another integration has a verb for "open terminal".

- Binds from every submap are offered, one per description, preferring the global one; a submap bind is labelled with its submap, `Lock (System)`. Submap navigation (`+Name`, `Back`, `Exit <submap>`), one-character descriptions and lid switches are left out; the phrases below take its place.
- "submap X", "X submap", "X mode", "enter X mode", "activate X mode" or "go to the X submap" (any `{activate}` or `{focus}` [intent](#intents), or "open") enter the submap named X, word matched against the submap names which-key shows (`cursor mode` is Cursor, `normal mode` is hyprvim's NORMAL). A name shared by several submaps (Delete and hyprvim's DELETE) opens the picker; a name that is no submap is a "no match". "X mode" also reaches a bind named "X mode" that is not a submap (`command mode`). As a fallback, these lose to any other integration's verb, so "performance mode" still sets the power profile.
- "exit submap", "leave the submap", "deactivate submap" (any `{deactivate}`) or "reset submap" go back to the global map like the Exit binds. The voice key is not bound inside submaps, so these are for submaps that keep global keys, the CLI and Voice Help.
- `excluded_descriptions` hides the voice binds themselves and anything about passwords or secrets; edit the list in the file.
- `confirm_labels` asks before closing, killing, locking, logging out, powering off, rebooting, suspending, deleting or clearing.
- A verb for the whole machine (`lock`, `suspend`, `sleep`, `hibernate`, `reboot`, `log out`, `power off`, `shut down`) followed by a word that only names it (`computer`, `pc`, `laptop`, `machine`, `screen`, `system`, `session`, `desktop`) is the bind named for the verb: "lock the computer" and "lock screen" are `Lock (System)` as a strong match, so they go straight to its confirmation rather than through a picker first. Edit `machine_verbs` and `machine_words` in the file.
- A bind that runs sends no notification ([silent](#silent-actions)); one that fails does.
- Tab on its Voice Help entries lists every submap (`Submap: Cursor`), "Exit submap" and every offered bind; picking one runs it as saying it would.
- A bind runs like Keybind Help runs it: the submap is reset, then `hyprctl eval 'debug.getregistry()[<arg>]()'`.
- A submap is entered like its `+Name` bind enters it, by `hyprctl eval` calling `enter` on the Submap module that registered it (the Hyprland config's `lib.key.submap` or hyprvim's), so its enter hooks and which-key run. Exiting calls their `reset`, which runs the current submap's exit hook.

### Apps

`apps.sh` opens installed apps and works on open windows, with word matching:

| Say                                                            | Does                                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------ |
| "open firefox", "launch slack", "bring up thunar"              | focuses the app's most recent window if it has one, else starts it |
| "open new firefox", "open a new kitty"                         | always starts it                                                   |
| "focus slack", "go to firefox", "take me to tmux config"       | focuses the window                                                 |
| "move slack to workspace 3", "send firefox to workspace three" | moves the window there, leaving focus where it is                  |
| "close slack", "quit the firefox window"                       | closes the window, after a confirm                                 |
| "resize the window to 400 pixels high", "make it 800 wide", "set the height to 400" | resizes the active window, keeping the size it does not name |
| "resize to 1200 by 800", "1200 by 800", "make it 1200x800"     | resizes the active window to that size                             |
| "make it taller by 100", "grow the window 200 pixels wider", "shrink it by 50 pixels", "make it narrower by 100" | resizes the active window by that much; grow and shrink without a direction change both |
| "increase width by 400", "decrease the height by 300", "add 200 to the width", "make it 200 more pixels wide", "make it 100 pixels narrower" | changes one dimension of the active window by that much |
| "resize horizontally by 300", "grow horizontally by 300", "shrink vertically by 100", "increase the height to 600" | horizontally is the width, vertically the height; "to" sets the size |
| "resize firefox to 1200 by 800", "make slack 800 wide", "increase slack's height by 200" | resizes the named window                                |

Opening, focusing and closing take every form of the `{open}`, `{focus}` and `{close}` [intents](#intents), and resizing every form of `{set}` ("make", "change", "adjust") as well as "resize"; growing takes "grow", "enlarge", "increase", "expand", "extend", "raise" and "add", shrinking "shrink", "decrease", "reduce" and "lower".

- Apps are the desktop entries in `$XDG_DATA_HOME` and `$XDG_DATA_DIRS` (the first copy of an id wins), leaving out `NoDisplay`, `Hidden` and entries `OnlyShowIn`/`NotShowIn` keep off this desktop. An app matches by its `Name` and by the last part of its id (`code`, `nautilus`). It starts like the Quickshell apps picker starts it: the `Exec` line without field codes, in `Path`, and `Terminal=true` apps in the Hyprland config's terminal wrapper.
- An app counts as running when a window's class is its `StartupWMClass`, its id or the last part of its id.
- Windows come from `hyprctl clients -j` and match by app name (the desktop entry's `Name`, else the class) or by title. Several matching windows open the picker, labelled with their titles.
- `window`, `app`, `application` and `program` are ignored words, so "close window" and "open application" are left to the keybinds. A phrase that is a described keybind ("close browsers", "focus left", "go to workspace 2", "start menu") is left to them too, even when a window or app would match it, and so is "open X" when X is a bind's whole description and names no app ("open files" for a `Files` bind; "open firefox" stays here).
- Opening, focusing and resizing are [silent](#silent-actions), since the window that opens, takes focus or changes size shows it; moving and closing still say what they did.
- Sizes are logical pixels, the ones `hyprctl clients -j` reports: on a monitor scaled 1.6, "400 high" covers 640 device pixels. Amounts are read as digits, as voxtype writes them ("1,200" too); number words are not. No size goes below 100 or past the window's monitor.
- A resize goes through `hl.dsp.window.resize` with the window's address, relative to its current size. A floating window takes the size as asked. A tiled window's size belongs to the layout: the resize moves its split, so the windows beside it give or take the space, and a dimension with no split along it (the height of a window in a single row) does not change. Which edge of the split moves shows only in the result, so a resize that went the wrong way, or was blocked that way, is sent the other way. The window is never floated to force a size. A size the layout or the monitor limited says so in a transient notification ("Slack: height stayed 686 (the tiled layout limits it)"), since that is no failure; only a missing window, a bad size or a dispatch error fails.
- "resize left", "resize submap", "reset size" and other phrases with no size are left to the Resize submap's keybinds. A resize of the active window that says which way but not how much ("resize horizontally and increase", "make it bigger") answers with a hint to say how much. After grow, shrink and the like, a bare amount needs its "by" or "pixels" ("shrink it by 50"), so "add slack to workspace 2" is no resize.
- The shipped `replacements.d/resize` turns Whisper's "pre-size", "presize" and "re-size" into "resize".
- Tab on its Voice Help entries lists every installed app; picking one opens it like "open <app>".
- A target with the word `session` or `agent` in it matches nothing, so "switch to the X session" and "go to the X agent" are left to the integrations for those.

### System

`system.sh` sets system values through what the keys and the bar already use, so the OSD and bar stay in sync:

| Say                                                                          | Does                                                                                   |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| "brightness 40", "set brightness to 40 percent"                              | `brightnessctl set 40%` (clamped to 1-100), then `qs-ipc call brightness refresh` for the OSD |
| "brightness up" / "down" (optionally "by 20"), "brighter", "dimmer"          | 10% steps by default, like the brightness keys                                         |
| "brightness max" / "min", "full brightness"                                  | 100% / 1%                                                                              |
| "power saver", "balanced", "activate performance mode", "set power profile to X" | `powerprofilesctl set`; X is matched against the profiles the machine offers; "deactivate power saver" or "performance" goes back to balanced |
| "do not disturb on" / "off", "enable" / "disable do not disturb", "silence notifications", "notifications on" | The bar's do not disturb, over `qs-ipc` `notifications get_dnd` / `toggle_dnd` |
| "keep the screen awake", "activate" / "deactivate caffeine", "caffeine on" / "off", "enable" / "disable autolock" | Stops or starts hypridle with `toggle-autolock.sh`, like the System submap's auto-lock key |

Brightness and do not disturb send no notification when they work ([silent](#silent-actions)), since the OSD and the bar's indicator show them; power profile and auto-lock still say what they set. Only the laptop backlight is driven; external monitors are not (no DDC/CI). A spoken power profile lasts until the next AC or battery change, when `power.sh` applies the one chosen in Settings, unless that is "keep".

### Answers

`answers.sh` answers math, time, time zone and date questions in the notification and opens the bar's weather popup for weather questions, with filler such as `hey`, `um`, `can you tell me` and a trailing `please` allowed around them:

| Say                                                                                                  | Answer                                                         |
| ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| "what's 15 percent of 230", "calculate 12 times 37", "convert 5 miles to km", "how many feet in a mile" | `qalc -t` result, also copied with `wl-copy`                   |
| "what time is it", "what's the time"                                                                 | the time, in the Settings > Clock format                       |
| "what time is it in Tokyo", "what's the time in London"                                             | `5:09am tomorrow in Tokyo (13 hours ahead)`                    |
| "what is 1 pm in Pacific time", "what is 1 pm Eastern in Pacific", "convert 3:30 pm Pacific to London time" | `1:00pm Eastern is 10:00am Pacific (3 hours behind)`           |
| "what time is 9 am tomorrow in Tokyo"                                                                | `9:00am tomorrow in Tokyo is 8:00pm today here (13 hours behind)` |
| "how far ahead is Tokyo", "what's the time difference with London"                                   | `London is 5 hours ahead, 9:09pm there`                        |
| "what's the date", "what day is it"                                                                  | `Saturday, October 10, 2026`                                   |
| "what's the weather", "how's the weather", "weather", "will it rain today", "do I need an umbrella"    | opens the Quickshell weather popup                             |

- Math is read from `$raw_transcript`, since normalizing drops `%`, `×`, `/` and decimal points. Number words become digits ("two hundred thirty point five"), and `times`, `divided by`, `plus`, `minus`, `squared`, `cubed`, `to the power of`, `square root of`, `percent of`, `half of`, `factorial` and `modulo` become qalc syntax.
- "what's" and "how much is" count as math only when a number follows, so "what's up" is left for the other integrations. Without a `to` (from "to", "in" or "into") qalc runs with units off, so a word it cannot place fails instead of becoming a unit.
- Time zones are computed by GNU `date` under `TZ`, so daylight saving comes from tzdata, and answered in the Settings > Clock format, also copied with `wl-copy`. "here", "local" and "my time" (or no zone) mean the system zone (`timedatectl`). A zone is any of the aliases below, a zone in the clock popup's `~/.local/state/quickshell/timezones.json`, or any city in `/usr/share/zoneinfo` by its last part ("tokyo" is Asia/Tokyo, "new york" America/New_York); a trailing "time" is dropped. Anything else answers "No time zone called X".
- "what time is <time> in <zone>" reads the time in that zone and answers here; "what is <time> in <zone>" and "convert <time> to <zone>" read it here, or in the zone named after it, and answer in the other. Days ("today", "tomorrow", a weekday) are against the local date and shown when either side is not today. A conversion needs am, pm, o'clock, noon, midnight or digit minutes ("15 30"), so "what's 15 in hex" stays math.

- Weather opens the popup the Leader `W` (Weather) bind opens, with `~/.config/hypr/scripts/qs-ipc call popup open weather`, so it needs the Quickshell bar running.

Time zone aliases (an unqualified "Central" is US Central):

| Say                                  | Zone                |
| ------------------------------------ | ------------------- |
| Pacific, PT, PST, PDT                | America/Los_Angeles |
| Mountain, MT, MST, MDT               | America/Denver      |
| Arizona                              | America/Phoenix     |
| Central, CT, CST, CDT                | America/Chicago     |
| Eastern, ET, EST, EDT                | America/New_York    |
| Alaska, AKST, AKDT                   | America/Anchorage   |
| Hawaii, HST                          | Pacific/Honolulu    |
| UTC, GMT, Zulu, Universal, Greenwich | UTC                 |
| UK, British, BST                     | Europe/London       |
| CET, CEST, Central European          | Europe/Paris        |
| EET, EEST, Eastern European          | Europe/Athens       |
| WET, Western European                | Europe/Lisbon       |
| India, Indian, IST                   | Asia/Kolkata        |
| Japan, JST                           | Asia/Tokyo          |
| China                                | Asia/Shanghai       |
| AEST, AEDT, Australian Eastern       | Australia/Sydney    |

### Agents

`keeptabs.sh` jumps to the coding agents [keeptabs](https://github.com/uhs-robert/keeptabs) tracks, through `keeptabs-pick --focus` like the bar's keeptabs popup, so the agent's window, tmux pane and nvim terminal all come forward.

| Say                                                          | Does                                                                      |
| ------------------------------------------------------------ | ------------------------------------------------------------------------- |
| "go to the waiting agent", "take me to the agent that needs me" | the agent that has waited longest for input; says so when none is waiting |
| "go to the done agent", "next done agent", "go to the agent that finished" | the agent that finished longest ago; says so when none is done |
| "next agent", "go to the next agent", "jump to next agent"      | the agent after the focused one, whatever its state, wrapping around      |
| "previous agent", "go to the previous agent"                    | the agent before the focused one                                          |
| "go to agent X", "go to the X agent"                            | the agent whose title, project or agent name matches X                    |

Every phrase takes any `{focus}` [intent](#intents) form: "go to", "switch to", "jump to", "focus", "take me to".

- Next and previous step through every tracked agent in `keeptabs-pick`'s order (waiting, done, running, idle, oldest first within each). The focused agent is the one whose window, tmux pane and nvim terminal keeptabs' own `session_focused` says has focus; with none focused, next starts at the first agent and previous at the last.
- An "agent X" that matches nothing says so instead of falling through to the keybinds.
- Tab on its Voice Help entries lists every tracked agent; picking one jumps to it.
- Jumping to a done agent marks it seen, so keeptabs drops it to idle and saying it again goes to the next oldest done agent, until "no agent is done".
- "go to agent X" and the done jump are [silent](#silent-actions), since the agent's window shows it worked; "no agent is done" comes as its own transient notification. The other jumps still notify with the agent they went to, because "no agent is waiting" is their only reply when nothing moves.

### Tmux

`tmux.sh` works on sessions by name, and every phrase names a session, so "switch to X" stays free for windows.

| Say                                                                                | Does                                                       |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| "go to the X session", "switch to session X", "open the X session", "attach X"     | focus or open the session                                  |
| "new session X", "open a new session X"                                            | a terminal on a new session X (attached if X already runs) |

Switching takes any `{focus}` or `{open}` [intent](#intents) form before the session ("take me to the X session", "launch session X"). Both are [silent](#silent-actions) when they work, since the session's terminal shows it; an unknown session still says so. X is matched against running sessions (`tmux list-sessions`) and the tmuxifier layouts in `~/.tmuxifier/layouts`, a layout by the `session_name` it sets or its file name. A layout goes through the Project picker's script (`hypr/scripts/rofi-tmux.sh <layout>`), which focuses its terminal or loads it in a new one. A running session without a layout focuses the terminal titled with its name, else opens a terminal attached to it. An X that matches nothing says so instead of falling through to the keybinds. Tab on its Voice Help entries lists every running session and layout; picking one switches to it.

### Notifications

`notifications.sh` drives the Quickshell bar, which is the notification daemon, over `qs-ipc` (`~/.config/hypr/scripts/qs-ipc`), so it needs the bar running:

| Say                                                          | Does                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------ |
| "clear notifications", "dismiss all notifications"           | empties the notification center (`notifications clear_all`)              |
| "read the last notification", "what was that notification"   | shows the newest history entry again as a toast, with its app and body   |
| "open notifications", "bring up the notification center"     | opens the bar's notifications popup (`notifications open`), any `{show}` |

- The repeat is read with `notifications get_last` and sent again with `notify-send --transient`, so it adds no second copy to the history. Under do not disturb it goes out critical, which do not disturb lets through, so it stays up until dismissed.
- The actions are [silent](#silent-actions), since each one's effect is its own feedback; an empty history says "No notifications".
- Do not disturb ("silence notifications", "notifications on") belongs to `system.sh`.

### Recording

`recording.sh` records the screen through the screenshot tool's own flags (`~/.config/hypr/scripts/screenshot.sh`, the `Print` key), so recordings land in `~/Videos/Recordings` with the same names, the bar's recording chip shows them, and "Recording Saved!" arrives the same way:

| Say                                                   | Does                                                                      |
| ----------------------------------------------------- | ------------------------------------------------------------------------- |
| "start recording", "begin recording", "record the screen" | records the focused monitor at once (`--record-geometry`)             |
| "record this window", "record the current window"     | records the focused window (`--record-focused`)                           |
| "record a window"                                     | picks a window to record (`--record-window`)                              |
| "record a region", "record an area"                   | opens the region selector to record (`--record-region`)                   |
| "stop recording", "finish the recording"              | stops it; screenshot.sh says where the file was saved                     |
| "is it recording", "am I recording"                   | how long it has run and the file it writes                                |

- Starting and stopping are [silent](#silent-actions), since the recording chip shows a start (screenshot.sh notifies when no bar shows one) and screenshot.sh sends "Recording Saved!" when it stops; starting while a recording runs says "Already recording" with its file instead, and stopping with none running says "Not recording".
- Any `wf-recorder` counts as the recording, as on the bar's chip, so the demo recorder's takes are stopped too, without a "Recording Saved!", which only screenshot.sh's own recordings get.
- Plain "stop" stays with Media, and "cancel the recording" matches nothing: "cancel" means discard to voxcmd, and stopping keeps the file.

### Click

`click.sh` clicks text it reads off the focused window. It captures the window's own buffer with `grim`, reads it with `tesseract`, and moves the pointer there with Hyprland before clicking with `wlrctl`.

| Say                                                    | Does                                                                  |
| ------------------------------------------------------ | --------------------------------------------------------------------- |
| `click <text>`, `left click <text>`, `click on <text>` | Left-clicks the text                                                  |
| `right click <text>`                                   | Right-clicks it                                                       |
| `double click <text>`                                  | Double-clicks it (two left clicks)                                    |
| `triple click <text>`                                  | Triple-clicks it (three left clicks)                                  |
| `show hints`, `show click hints`, `hint mode`          | Opens `wl-kbptr`'s floating hint mode, as the Cursor submap does; answer with keys |
| `click mode`, `start clicking`, `clicking mode`        | Opens a [click mode](#click-mode) session: say targets without "click"  |
| `stop clicking`, `exit click mode`, `turn off click mode` | Ends it: stop, exit, quit, end, leave, finish, close or turn off, then clicking or click mode; `click mode off` too (inside the session, `done` does as well) |

- Only the focused window is read, since unfocused windows are dimmed and lose words to OCR. With no focused window the command fails with "no focused window".
- A click verb always needs a target, so a bare "click" and "right click" still go to the Cursor submap's binds in Keybinds. So do "click left", "click it", "click here", "click and drag" and the like: a target of only filler words and `left`, `right`, `middle`, `here`, `and`, `drag` and `hold` is no target, and the screen is not even read. A real target found nowhere says `No "<text>" on screen` and does not fall through to Keybinds.
- Matching is [word matching](#word-matching) against each run of words OCR read on one line (a wide gap starts a new run). One strong match clicks; the text on its own as a button beats the same words inside a longer run. Several matches, or any weak one ("settings" for an "Open Settings" link), [number the matches on screen](#click-hints), answered by number key, click or voice ("two"); only if the bar cannot draw them, or there are more than ten, does the [picker](#picker) ask, with labels giving the text and where it is ("Next - top right"). A stray phrase never clicks: a word OCR read one edit away from the spoken one ("Clone" for "close", "Summit" for "submit") is another word as often as a misread one, so it is never taken for the spoken word. Because of that, a word is kept down to confidence 40 (instead of 60) when it equals a spoken word, or the spoken letters joined, by look-alike letters: white text on a blue button often reads at 50 to 55 ("Newtask" for "new task"). A doubtful word that is only close to a spoken one is still dropped.
- Tesseract reads a sentence as one run, so a link inside it ("2 tasks" in "2 tasks are flagged TODO.") is only part of a run and word matching drops the run. When no run matches whole, the words of a run that equal the spoken words, in order, are a candidate of their own, with the click point and box of just those words; one clicks, several are numbered on screen. A run that matches whole always wins, so "tasks" with a "Tasks" heading on screen never clicks inside a sentence.
- Look-alike letters are forgiven: `l`, `I`, `1` and `|` compare equal, `0` and `O` too, so "sign ln" is "sign in". Any other misread letter is not: the OCR word stays what it is, and voxcmd's word matching calls it weak or drops it.
- Text the window holds but the screen covers is not clicked: the capture is the window's own buffer, so candidates under a floating window above the focused one, a pinned window, or the monitor's reserved edges (the bar) are dropped. When every candidate is covered, a toast says `"<text>" is covered by another window`.
- A click goes only to the window that was read, where it was: when another window has focus by the time of the click (a picker answered seconds later), or the window moved or changed size, nothing is clicked and a toast says `The window changed; say it again`. The same holds when the read is more than 60 s old.
- A failed click is a failed turn: its error toast says only `Click: click: <reason>`, never the OCR text, since the bar keeps error toasts in its history (`private_labels=1`). In [click mode](#click-mode) it counts as a turn that did nothing, like a target found nowhere.
- A click is [silent](#silent-actions); the pointer landing on the text is the feedback.
- **Why didn't it click?** `voxcmd click-explain <text> [--window <stableId>]` runs the same capture, OCR, matcher, word matching and covering check on the focused window (or that client, as `grim -T` takes it) and prints the window, capture mode, image size and scales, inversion, strips and OCR time, then each OCR run holding a word that is, resembles or nearly equals a spoken one, with its words' confidences and the rule that decided it (kept strong, kept weak, sub-span, dropped for the confidence floor, coverage under half, near miss only, or covered by another window or a reserved edge), and last what voxcmd would do: click at a point, overlay with N, not on screen, covered. The matcher writes those reasons itself (`click-match.awk -v explain=1`), so they cannot disagree with a real click. It never clicks, moves the pointer or notifies; the screen text appears only on the terminal and the capture is deleted.
- The screenshot and its text live only in a private directory under `$XDG_RUNTIME_DIR`, deleted when the command ends.

The pipeline is `click-ocr` (capture, gray, invert when the window is dark, tesseract; a window taller than 1000 px is cut into 4 to 6 overlapping strips read in parallel, each owning the lines whose box is centred in its rows) feeding `click-match.awk` (matching and the mapping to global coordinates), both in `~/.local/share/voxcmd/`. Typical time from speech end to click is under a second. The capture is by toplevel (`grim -T`, from the window's `stableId`), so translucent windows are read without the wallpaper behind them; it falls back to the window's screen region when that fails. The mapping takes the x and y scales from the captured image, not the monitor, and grim returns upright images on rotated monitors. A capture whose two scales differ by more than 2% is retaken as a screen region, and fails if that differs too. A word is matched against the spoken words one by one, or by letters joined ("Newtask" for "new task", "Read me" for "readme"); the spoken words replace OCR text only for look-alike equality.

Needs `grim`, `tesseract` and `tesseract-data-eng`, `imagemagick`, `wlrctl` and `wl-kbptr` (all in `packages/`). Tests: `home/voxcmd/tests/run.sh` (a step of `just check`) runs in the test sandbox, where `grim`, `magick`, `tesseract`, `wlrctl` and `hyprctl` are stubs fed by fixtures, and runs voxcmd with `--dry-run` only.

### Click mode

"Click mode" opens a [voice session](#voice-sessions) in which what you say is a click target: "sign in" is "click sign in", "continue" is "click continue". "right click settings" and "double click readme" work as spoken. After each click voxcmd listens again, once the screen has settled. A bare "click" names no target and counts as not understood.

- **Ending it:** say `done`, `I'm done`, `that's all`, or a verb and the mode: stop, exit, quit, end, leave, finish, close or turn off, then "clicking", "click mode" or "clicking mode" ("quit click mode", "leave the click mode", "turn off click mode"; "click mode off" works too, and "okay", "please" or "now" around it is fine); stay silent for about 10 s (`VOXCMD_SESSION_NO_SPEECH_SECS`), a fan or room noise included, since a turn needs [more speech](#voice-sessions) than a command and Whisper's stock guesses at noise ("Thank you.", "The End") are not turns; or give three turns in a row that did nothing (not understood, a target found nowhere, a failed click, or an overlay cancelled). The bare verbs `cancel`, `exit`, `stop`, `quit` and `close`, and `never mind`, are button labels, so in click mode they are clicked like any other target. It also ends after 5 minutes or 40 turns.
- **Needs auto-stop:** silence is the only thing that ends an idle session, so with [auto-stop](#auto-stop) off or unable to listen, "click mode" says "Click mode needs auto-stop" and does not start.
- **Ambiguous targets:** the [numbered overlay](#click-hints) shows and listens as usual, with auto-stop's own silence allowance; after the pick and the click the session carries on.
- **Indicator:** while it is open the Voxtype bar module says "Click mode" beside its glyph and the voxtype OSD's title carries it too, so an open microphone is never invisible. Both read `$XDG_RUNTIME_DIR/voxcmd/session.json` and, while it is there, check every few seconds that `/proc/<owner>` still exists, so a listener killed outright does not leave the indicator up.

### Click hints

`voxcmd-hints [--listen] <label> <choices-json>` is the picker `click.sh` uses for several matches (`pick_command`). Choices are `{id, label, box: [left, top, width, height]}`; it prints the picked id and exits 1 on cancel. The Quickshell bar draws a numbered keycap and an outline over each box (`qs-ipc call clickhints`, see the bar's README), and the other screens stay quiet. Answer by:

- number keys `1`-`9` and `0` (box 10), or a click on a box; `Esc`, `q` or a click anywhere else cancels, and `?` lists the keys;
- voice, as with any [picker](#answering-by-voice): "two", "the second one", a label's words, "cancel". With `--listen` (a spoken command) the reply recording starts just before the numbers appear, and an unclear reply listens once more. The overlay shows Listening or Transcribing, and its 10 s timeout waits while voxtype records.

The overlay writes the number into the pick's FIFO, a voice reply the displayed label; either maps to the choice's id. While it waits, `voxcmd-hints` keeps the same `pending-pick.json` as `voxcmd-pick`, with `kind: "hints"`, `listen_again` and numbered labels. Without the bar, with more than ten choices, or when a choice has no box, it hands the pick to `voxcmd-pick`.
### Calendar

`calendar.sh` works with Google Calendar. It reads the events cache `calendar-sync` keeps at `$XDG_CACHE_HOME/calendar/events.json` (default `~/.cache/calendar/events.json`) and opens pages with `xdg-open`, so in the default browser, or focuses the Firefox tab that already shows one; without the cache it says the calendar isn't set up.

| Say | Does |
| --- | --- |
| "join my meeting", "open my meeting" | Opens the meeting in progress, else the next one starting today: its join link (Google Meet or Microsoft Teams, the cache's `join_url`), or its event page when it has none. With none left it says "No more meetings today" |
| "what's my next meeting", "what's next on my calendar" | Says it in a notification: "Standup at 3:00pm, in 12 minutes", or "Standup tomorrow 9:00am" on a later day |
| "what's on my calendar", "what's on my calendar tomorrow", "show my calendar for friday" | Opens the bar's clock popup on that day (`qs-ipc call calendar open_day <date>`) |
| "new meeting tomorrow at 3 pm for an hour called Design review with alice@example.com" | Opens Google Calendar's new-event form in the browser, prefilled; you add anyone else and save there |
| "new meeting" | Opens the blank form |
| "open my calendar", "go to my calendar" | Opens calendar.google.com |

- Cancelled and all-day events never count as a meeting to join or as the next one.
- "Join my current meeting" opens only a meeting in progress ("No meeting in progress" otherwise) and "join my next meeting" only one that has not started yet today ("No more meetings today" otherwise); neither falls back to the other.
- "Join my meeting" prefers the meeting in progress that has a join link (the latest start when several do); an in-progress meeting without one gives way to a meeting with one starting within five minutes. It does not rank by `event_url`, which every event has.
- A new meeting reads its time and length before "called" ("tomorrow at 3 pm for an hour", "friday at 9 am for 30 minutes", "tomorrow at 9 am 2 hours long"; an hour is the default). A bare hour reads as a working-hours time: 1 to 7 is pm, 8 to 11 am, 12 noon ("friday at 3" is 15:00), unlike timers, which take the sooner of the two. The title is what follows "called", "named" or "titled", taken from the raw transcript so its casing survives; it ends at the first "with", "inviting" or "invite" that is followed by an address, and every address in the transcript becomes a guest. A day with no time ("new meeting friday called Offsite") makes an all-day event. Dates are in the local time zone, which the form gets as `ctz`.
- Not supported: a title before the time ("new meeting called Sync tomorrow at 3"), and guests without an "@" in the transcript (a transcriber that writes "alice at example dot com" adds none).
- Days are "today", "tomorrow" and weekday names; "next friday" is never today.
- "my calendar" and "the calendar" always mean Google Calendar here; `apps.sh` leaves them alone, so an installed Calendar app does not turn "open my calendar" into a picker. "open calendar" still opens the app.
- Joining says which meeting; the day view, a new meeting and the calendar stay [silent](#silent-actions), since the popup or the tab is the feedback.
- A meeting link and "open my calendar" go through `open_page` in `calendar.sh`: when Firefox is the default browser (`xdg-mime query default x-scheme-handler/https` is `firefox.desktop` or `firefox-esr.desktop`) and a window is open, a tab already showing the page is focused (`firefox-tab goto`, as in [Firefox](#firefox)). Any other browser, no Firefox window, or a failed focus opens it with `xdg-open` as everywhere, which can leave a duplicate tab. The new-event form always opens fresh through `open_url`.
- `tests/run-calendar.sh` runs these phrases against a placeholder cache in `tests/sandbox.sh` and checks the URLs and calls.

### Firefox

`firefox.sh` and `firefox-sites.sh` (with the helper `~/.local/share/voxcmd/firefox-tab`) reach the browser itself. Tabs and sites are read, never written: the session store (`sessionstore-backups/recovery.jsonlz4`) for tabs, a copy of `places.sqlite` and its write-ahead log for bookmarks and history, from the profile `installs.ini` names. Windows are matched to the store by their title. Tabs, link hints and the address bar are driven by typing into the focused Firefox window with `wtype`, through Tridactyl's command line (`:tab <title>`, `:voxhints` and `:voxfollow <n>` for hints) or Firefox's own keys, so nothing needs installing in Firefox beyond Tridactyl.

| Say | Does |
| --- | --- |
| "go to weekly notes", "find the weekly notes tab", "go to example.com" | Focuses the window and tab whose title or site matches; several matches ask with numbers. A domain with no tab open is opened in a new tab. "go to firefox" is still the window |
| "open code hub in firefox", "open website code hub", "open example.com" | Opens a bookmark, a visited site or a domain in a new tab; nothing found is searched when Firefox was named. A bare "open X" reaches this only when no app, keybind or other integration has it |
| "open code hub here" | The same, in the focused tab |
| "show links", then "3" or "follow link 3" | Numbered link hints, then the microphone opens again for the number; "follow link 3" without showing them first works too. "hide links", "cancel", "stop", "exit", "quit" or silence takes them down. Needs Tridactyl and its [`voxhints`/`voxfollow` commands](#link-hints-in-firefox) |
| "new tab", "close tab" | Ctrl+T and Ctrl+W in the focused Firefox window |

- Tridactyl as the store add-on is read from `extensions.json`; one loaded temporarily from a folder is recognised when its storage changed since Firefox started (`firefox-tab tridactyl` prints `store`, `temporary` or `none`; `VOXCMD_FIREFOX_TRIDACTYL=on|off` overrides). With `none`, "go to" only focuses the window.
- Hints are numbered for that one run only, in the page's memory; the saved Tridactyl settings are untouched.
- A number with no hint leaves hint mode and follows nothing, never another link.
- The store lags a tab switch by up to 15 seconds, so a window is also found by any of its tabs' titles. Private windows are in no store and are found by the title they show.
- While `firefox.sh` is installed, `apps.sh` stops matching Firefox windows by their title, so a tab is offered once.
- `tests/run.sh` (section "firefox") and the Firefox rows of `tests/phrases.tsv` run on a made-up profile built by `tests/firefox-profile`.

#### Link hints in Firefox

Tridactyl takes typed commands only, and the hint code is too long to type, so `home/tridactyl/.config/tridactyl/tridactylrc` defines two commands and `firefox-tab` types only their names: `:voxhints` shows numbered hints without autoselect, `:voxfollow <n>` shows them and follows hint `n`. Both setups read that rc through Tridactyl's native messenger (`~/.mozilla/native-messaging-hosts/tridactyl.json`, `:nativeinstall`), at Firefox start or on `:source`; the rc is stowed to `~/.config/tridactyl/tridactylrc` with the `tridactyl` package. Without the commands Tridactyl answers "not an editor command" and nothing happens: Firefox cannot be asked whether it loaded them, so `firefox-tab` only refuses when the rc file it finds lacks them (`link hints need the voxfollow command in Tridactyl's tridactylrc`). After changing the rc, `:source` it or restart Firefox.

After "show links" voxcmd opens a [voice session](#voice-sessions) of kind `links` that listens like a [picker's reply](#answering-by-voice): "3", "three", "link 3" and "follow link 3" all follow link 3, which ends the session. Hearing nothing (auto-stop's own deadline), three turns that name no number, "cancel", "never mind", "hide links" or "done" end it and press Escape in the focused Firefox window, through the same focus check as every typed key, so the hints do not stay up. `firefox.sh`'s `session_ended` is what presses it.

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

`voxcmd-pick [--listen] <label> <choices-json> [<expansions-json>]` is the blocking picker voxcmd uses, usable on its own. Choices are strings or `{id, label}` objects; it prints the picked id and exits 1 on cancel. Labels are shown numbered (`1. Acme Labs`); the number never reaches the printed id.

Expansions are `{key: {title, choices}}`, and a choice with `expand: key` opens that list on Tab in the Quickshell picker; its ids come back like any other. The picker writes the key it shows to a view file, so a voice reply answers from the list on screen.

### Answering by voice

Press the Voice Command key while a voxcmd picker is open and speak a reply; the recording stops itself after it, like a command, but on a pause after as little as 0.1 s of speech (`VOXCMD_REPLY_MIN_SPEECH_SECS`), since a reply is often one short word. It can be:

- a choice's label: the whole label, else the choice sharing the most words with the reply, else a substring, else fuzzy; it must single out one choice. Words compare by stem and the reply's other words do not count, so "locked", "lock it" and "lock computer" all pick `Keybinds: Lock (System)`, which needs no "system";
- an ordinal: `two`, `the second one`, `number 3`, `first`, `last`;
- a direction, for choices drawn on screen ([click hints](#click-hints)): `the top one`, `the bottom one`, `the left one`, `the right one` (also `topmost`, `lower`, ...). It goes by the boxes' edges, so a column of items lined up on the left has one leftmost; boxes whose edges are within half a text height tie, and a top or bottom tie goes to the leftmost, a left or right tie to the topmost. The numbers run in reading order, so `first` and `last` are the first and last in that order;
- with a single choice, `yes`, `yeah`, `sure`, `that one` or `do it` to take it, and `no` or `nope` to cancel;
- `cancel`, `never mind` or `none`, which cancel like Esc.

A picker with a single choice, which a [weak match](#word-matching) opens, asked about a command that came by voice (from `voxcmd listen`) listens for the reply without the key: voxcmd passes `--listen`, and `voxcmd-pick` starts the reply recording (`voxcmd listen --start-only`, only while voxtype is idle) just before the picker shows. It stops itself like any reply, and silence cancels it and leaves the picker waiting for a key or the Voice Command key. Answering by key, click or timeout cancels it if it is still recording or transcribing, as the [confirm card](#confirm) does, and leaves alone any recording started after it.

A recording started while a picker waits is always a reply, so `cancel` there closes the picker rather than being discarded as a command.

The reply picks as if the choice had been clicked and closes the picker. A reply that matches nothing or several choices leaves the picker open and sends a notification; press the key again to retry.

While it waits, `voxcmd-pick` keeps `$XDG_RUNTIME_DIR/voxcmd/pending-pick.json` (`{pid, fifo, label, choices, expansions, view}`) and removes it when the pick ends however it ends. A file whose owner is gone is ignored. The reply goes into the picker's result FIFO, so `voxcmd-pick` closes the picker itself afterwards: the Quickshell one over `qs-ipc call picker close`, rofi by ending it.

Hyprland still runs binds while the Quickshell picker or confirm card has the keyboard. rofi asks the compositor to inhibit shortcuts while it is open, and Hyprland honours that unless `binds:disable_keybind_grabbing` is set, so with the rofi fallback the key does nothing until rofi closes; pick with the keyboard or mouse there.

## Confirm

`voxcmd-confirm [--listen] [--verb <verb>] <question>` asks a yes/no question and exits 0 for yes, 1 for no, cancel or no answer. voxcmd uses it before an action that needs confirming, asking the option's label without the integration name ("Close Slack window: Inbox?"), with the label's first word as the verb; it is usable on its own. With the bar running it drops a card from the center island of the focused monitor: `y` or Enter is yes, `n` or Esc is no, the buttons work too, and 10 seconds without an answer cancels. That countdown waits while voxtype records or transcribes, and starts over after. Without the bar it falls back to `rofi -dmenu` with Yes and No, which cancels after 10 seconds.

A command that came by voice (from `voxcmd listen`, not the command line, Voice Help or a picker click) passes `--listen`: a reply recording starts just before the card shows, so the microphone is already live when the question appears, with the same auto-stop as Voice Command, and the card shows Listening while it records. It starts only while voxtype is idle and never stops a recording already under way. Any voice key stops it early, as always. Silence ends it without an answer, so the card waits for a key. Answering the card by key, click or timeout cancels the reply recording if it is still running or transcribing, so the microphone goes off and the next voice key starts a new command. Only the recording `voxcmd-confirm` started is cancelled: its watcher holds it from start until voxtype goes idle, and a dictation or recording started after that is left alone. Without `--listen` the card does not listen, but the Voice Command key still records a reply to it.

The reply is read by its words, so a natural reply works:

1. A no word anywhere makes it a no, even after a yes word, so a mixed reply gives the safe answer: `no`, `nope`, `nah`, `don't`, `do not`, `cancel`, `never mind`, `stop`, `forget it`, `leave it`. "No, don't close it", "nope, keep it" and "yeah, never mind" are all no.
2. Otherwise a reply starting with `yes`, `yeah`, `yep`, `yup`, `sure`, `okay`, `ok`, `confirm`, `do it` or `go ahead` is a yes, whatever follows: "yes close it", "yes please", "yep go ahead". So is one starting with the verb: "close it" or "close slack" for a close.
3. Anything else, including an empty transcript or Whisper's "you" for a short clip, keeps the card open and listens once more; after a second unclear reply it waits for a key.

While it waits, `voxcmd-confirm` keeps the same `pending-pick.json` as the picker, with `kind: "confirm"`, the `verb`, and `listen_again`, the file whose presence allows the one extra listen.

## Voice sessions

A session keeps the microphone re-opening after each spoken turn, so related commands need no repeated verb. [Click mode](#click-mode) and the Firefox [link hints](#link-hints-in-firefox) are the sessions so far; an integration opens one from an action with `session_begin <kind> "$file" "<label>" [reply]` and supplies `session_rewrite`, which prints the phrase to route for what was said (nothing when it names nothing usable). `session_exit_phrases` (optional) is a regex of further phrases that end the session, besides "done", "I'm done" and "that's all", matched whole before `session_rewrite`. `session_miss_actions=(action ...)` lists actions that mean the turn found nothing to act on, and `session_ended` (optional) runs in the background whenever the session ends, to tidy what it left on screen. With `reply`, a turn is listened for like a picker's reply (0.1 s of speech, auto-stop's own pause and deadline) instead of with the session settings below, so one short word is a turn.

- **State:** `$XDG_RUNTIME_DIR/voxcmd/session.json`, `{kind, integration, label, started, owner, owner_start, unclear, turns}`. `owner` is the PID of the listener that hears the next turn and `owner_start` its start time (field 22 of `/proc/<pid>/stat`), so a reused PID is not mistaken for it; each new listen takes it over. A session whose owner has died is stale: it is deleted the first time anything looks, and never keeps the microphone open. Every change holds `flock` on `session.lock` beside it.
- **Routing:** while a session is open, `voxcmd listen` sends the transcript to the session instead of [routing](#how-a-phrase-is-routed) it, unless a picker or card is waiting for a reply, which keeps priority. Exit words end it before anything is routed. Pressing the Voice Command key while a turn is still being handled starts the next turn at once, and the turn's own listener leaves the session to it.
- **Idle end:** a session listen allows `VOXCMD_SESSION_NO_SPEECH_SECS` (10 s) of silence, whatever auto-stop's `no_speech_secs` is; hearing nothing ends the session, with a notification, instead of cancelling silently. `session_begin` refuses to open a session when `voxcmd-autostop --check` fails.
- **Stricter auto-stop:** a session listens to the room between turns, so before a pause ends a turn it wants 0.4 s of speech (`VOXCMD_SESSION_MIN_SPEECH_SECS`) and a 1.5 s pause (`VOXCMD_SESSION_SILENCE_SECS`), whatever auto-stop's `min_speech_secs` and `silence_secs` are. A word shorter than that is still heard, only at the 10 s deadline. A picker or overlay asked during a turn listens as any [reply](#answering-by-voice) does.
- **Noise transcripts:** Whisper turns silence and noise into stock phrases. A turn whose whole transcript, normalized, is empty or one of `you`, `bye`, `the end`, `thank you`, `thank you for watching`, `thanks for watching` or `blank audio` (whisper.cpp's `[BLANK_AUDIO]`) heard nothing: it listens again without counting toward the unusable turns below, though it counts toward the turn and time caps. Outside a session these are routed like any command. The list is `session_noise_transcripts` in `voxcmd`.
- **Never a loop:** three unusable turns in a row end it, a turn that ran nothing (a picker cancelled or timed out) counting as unusable; so do `VOXCMD_SESSION_MAX_TURNS` turns (40) or `VOXCMD_SESSION_MAX_SECS` (300) open, whichever comes first; a listen that cannot start ends it; a listener that dies mid-session ends it. Each says why in a transient notification.
- **Settling:** after a turn voxcmd waits, for at most 2 s, until neither the click overlay (`qs-ipc call clickhints state`) nor a popup (`popup state`) is open or animating, then 0.3 s for the clicked app to draw, before listening again (`VOXCMD_UI_SETTLE_MAX_SECS`, `VOXCMD_APP_SETTLE_SECS`). A bar that does not answer counts as settled.
- `voxcmd end-session` ends it by hand, and [Stop Voice](#stop-voice) ends it along with any picker or recording.

## Stop Voice

`SUPER + SHIFT + COMMA` (Leader, `SHIFT + COMMA`) runs `voxcmd stop`, the key for a voice session or overlay that will not end and a recording you no longer want. It does three things, each only when there is something to do:

- Ends the open [voice session](#voice-sessions), reported as "stopped", which also takes down Firefox's link hints. This comes first, so the session's listener cannot open the microphone again, even when it is mid-turn: its turn is discarded and the session is gone when it looks.
- Cancels the open picker, confirm card or link hints, as Esc does.
- Cancels a voxtype recording under way, or being transcribed, whichever key started it: Voice Command, a reply recording or Speech to Text. Nothing said is routed or typed, and Speech to Text resumes its paused media as it does when any recording ends.

With nothing going on it does nothing and says nothing. `voxcmd end-session` still ends only the session.

## Debug log

`VOXCMD_DEBUG=1`, or creating `$XDG_RUNTIME_DIR/voxcmd/debug.log`, makes voxcmd and `voxcmd-confirm` append a timestamped trace there: each listen and the voxtype state it found, the watcher's state changes, auto-stop's verdict and `voxcmd-autostop`'s own summary of what it heard (see [Auto-stop](#auto-stop)), the transcript and where it went, a confirm's question, reply and answer, a cancelled reply recording, and whether the action ran. Delete the file to turn it off again.
