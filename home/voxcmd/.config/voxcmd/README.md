# voxcmd

Voice commands on top of [voxtype](https://github.com/peteonrails/voxtype). Speak a phrase, voxcmd matches it against the verbs your integrations declare and runs the action. The integrations that ship, and how to write your own as a drop-in file, are under [Integrations](#integrations).

| Key                                | Does                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------ |
| `SUPER + COMMA`, Leader, `COMMA`   | Voice Command: listen, stop [after a pause](#auto-stop), run the command |
| `SUPER + PERIOD`, Leader, `PERIOD` | Speech to Text: dictate until a voice key is pressed again, then type it |
| `SUPER + SHIFT + COMMA`, Leader, `SHIFT + COMMA` | [Stop Voice](#stop-voice): end the session, picker and recording, running nothing |
| `SUPER + CTRL + COMMA`, Leader, `CTRL + COMMA` | [Rapid mode](#rapid-mode): every turn is a command, until you say done |
| `SUPER + CTRL + PERIOD`, Leader, `CTRL + PERIOD` | [Wake word listener](#cortana-wake-listener): switch "Cortana" on or off |
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
voxcmd rapid                      # open rapid mode (the same as saying "rapid mode"); from a terminal or a key
voxcmd end-session                # end the open voice session and every mode in it, if any
voxcmd stop                       # stop all voice activity: session, picker or card, and any recording (see Stop Voice)
voxcmd wake toggle                # switch the "Cortana" listener on or off (on, off, toggle, status)
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
| `max_secs`        | `VOXCMD_AUTOSTOP_MAX_SECS`        | `0`     | stop after this long once there is speech in it, however it goes on, with a verdict of its own (exit 5); `0` is no limit. [Type mode](#type-mode) sets it just under voxtype's `max_duration_secs` |

`voxcmd-autostop --check` exits 0 when auto-stop is on and can listen, else 1 saying why; a [voice session](#voice-sessions) asks it before opening. To tune it, `voxcmd-autostop --verbose` prints each frame's level and the threshold. Run it while voxtype records, since it gives up after 3s otherwise, or on raw 16 kHz mono s16 audio with `--pcm FILE`. With the [debug log](#debug-log) on it appends a summary there: the room and threshold it calibrated, each run of frames it counted as speech (start, length, mean and peak level, the threshold then), speech it set aside as noise, and its verdict with the room, threshold and speech total at the end. The microphone is released when the recording ends however it ends: stopped, cancelled, at voxtype's `max_duration_secs`, or with voxcmd gone.

## How a phrase is routed

1. The transcript is lowercased, punctuation is dropped and whitespace collapsed: `"Set volume to 40%."` becomes `set volume to 40`.
2. Replacement files in `replacements.d/` rewrite whole words, for words the speech model keeps getting wrong.
   "What can I say", "voice help" and "show voice commands" then open [Voice Help](#voice-help) before any integration is tried, and "never mind", "cancel", "forget it" and "nothing" end there, running nothing.
2b. While a bar surface is open (an integration's `surface_open`, today the [overview](#overview)), the phrase goes to that integration's verbs first; if they match nothing, routing goes on.
3. A phrase that starts with an integration's [force prefix](#force-prefixes) skips every other integration and the LLM hook: the rest of the phrase is matched against that integration's verbs alone, whatever its tier, then goes through steps 5, 6 and 8. Nothing matching there is a "no match", with no other integration tried.
4. Each integration's verbs are tried in order against the whole phrase; the first match per integration counts.
5. A verb with a target whose integration lists candidates for that action matches the target against them: fuzzy (`fzf --filter`, an exact label winning outright) or, for an integration with `target_match=words`, [word matching](#word-matching).
6. A target that matches none of the candidates runs the action the integration names for that case in `no_match_actions`, if any. A [word matching](#word-matching) target with no words left after the filler and `match_ignore_words` are dropped names nothing, so it runs no such action and the phrase can fall through to the fallbacks.
7. If nothing so far can run, the [LLM hook](#llm-hook) gets a turn, then the [fallback integrations](#fallback-integrations) go through steps 4 to 6.
8. One option runs (after a [confirm card](#confirm) if the integration sets `confirm=1` or the option's label matches its `confirm_labels`). Several, or a single weak word match, open a picker, the Quickshell one when the bar is running and `rofi -dmenu` otherwise, which can also be [answered by voice](#answering-by-voice); cancelling does nothing. None sends a "no match" notification with a Voice Help button.

9. A phrase that matched nothing, or only weak matches, is retried on the part after its last correction point, then earlier points: after "no", "no wait", "wait", "I mean", "sorry", "actually", "scratch that" or "let me rephrase", after leading filler ("um", "uh", "okay", "so", "hey"), and from the second occurrence of the first word. "Exit, exit overview" is "exit overview", "close two, no wait, close three" is "close three" and "um, okay so open firefox" is "open firefox". The retry is taken only when it is one option that is not a weak match; otherwise step 8 goes on with the phrase as spoken. A phrase that matches as spoken is never retried ("remind me to say sorry" is a reminder), and no other tail is tried, since a leftover "four" can be a command of its own. A [voice session](#voice-sessions) turn is retried the same way (its mode's integration only); [type mode](#type-mode) never is. `$raw_transcript` is the retried part.

A phrase of several commands joined by "and then" is split first and each part routed on its own; see [Sequences](#sequences).

A notification reports what ran, followed by the last line the command printed, if any, or the last lines of the error. Only errors stay in the notification history: a failed action, an action with no command, voxtype not ready or failing to start. Everything else (what ran, answers, "no match", "which one?", "Say: ...") is sent with `--transient`, so the bar shows it and drops it. An action marked [silent](#silent-actions) sends nothing when it succeeds.

## Sequences

"Open firefox and then go to youtube" is two commands in one phrase. voxcmd splits the transcript on "and then", or on ", then" when the transcript has the comma (Whisper usually writes it), and never on a bare "then": "open firefox then ..." is one phrase. Each step is routed as a phrase of its own (steps 1 to 8 above, with its own wake word, force prefix, Voice Help and discard phrases), one after another, each only once the one before has finished. A leading wake word is stripped from the whole phrase first. `$raw_transcript` is the step's own words.

- **Free text takes the rest.** An action that takes dictated text (a timer's "remind me to ...", a calendar event's title) may contain "and then" itself, so an integration lists those actions in `free_text_actions` and the step that starts with one of their verbs takes the whole remainder of the phrase. Put the dictated command last: "open firefox and then remind me to call mom and then email bob" is two steps, the second a reminder with the whole text.
- **Waiting.** Between steps voxcmd waits for what the step started to show: by default no popup opening or closing and no click overlay, then `VOXCMD_APP_SETTLE_SECS` (0.3 s) for the app; an action that starts something slower declares its own condition in `step_waits` (opening an app waits for its window to have focus, a day in the calendar for the clock popup). It polls, never waits on the compositor's events, and does not wait after the last step. A wait that outlasts `VOXCMD_STEP_TIMEOUT_SECS` (15) stops the sequence.
- **Stopping.** The first step that does not run stops the rest: no match (a Voice Help phrase counts as one), a cancelled picker, a declined confirm card, a failed command, a timed-out wait, or a discard phrase (silently). One notification says where, instead of the step's own: an error "voxcmd: stopped at step 2 of 3" with the step, the end of its output and "1 more step not run"; for no match an info one with the Voice Help button quoting the step's words (never a free-text target); for a picker or card "Stopped at step 2 of 3: cancelled" or "...: not confirmed". Steps that ran keep their own notifications. A step whose label is private ([`private_labels`](#silent-actions)) is named without it.
- **Limits.** At most 5 steps; more is refused, and nothing runs. A mode switch ("rapid mode", "type mode") is allowed only as the last step: anywhere else the whole phrase is refused, and nothing runs. Neither is split inside [type mode](#type-mode), whose words are text.
- **Confirm cards and pickers** work as in any phrase, in any step, and listen for a spoken answer when the phrase was spoken.
- **Stop Voice** ends a running sequence: it is checked before each step and on every poll of a wait, and says nothing.
- **Dry run.** `voxcmd --dry-run "..."` prints `sequence: N steps`, then under `step i of N` the usual block, `waits for:` and a note where a free-text action took the rest; a refused phrase prints `result: refused`.

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
# $raw_transcript (the transcript before normalization and replacements, with its punctuation, digits and symbols),
# and $confirmed, 1 when the confirm card asked and was answered yes, else 0.
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

An integration takes part in [sequences](#sequences) with two optional settings:

```bash
# Actions whose target is free text, which may say "and then": a step starting with one of their verbs takes the rest of the phrase.
free_text_actions=(remind)

# What a step waits for before the next one starts, a shell condition polled until it succeeds (VOXCMD_STEP_TIMEOUT_SECS at most).
# It runs in the integration's context with $id, $target and $raw_transcript as the action had them, and $active_before, the address of
# the window that was active before the step. voxcmd provides popup_is_open <name> (no bar counts as open), ui_settled (no popup opening
# or closing and no click overlay), and active_window_address. An action without an entry waits for ui_settled, then VOXCMD_APP_SETTLE_SECS.
declare -A step_waits=(
  [focus]='[ "$(active_window_address)" = "$id" ]'
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

Helpers several integrations share live in `~/.local/share/voxcmd/`, since every file in `integrations.d/` is loaded as an integration; an integration sources one from `$voxcmd_share_dir`, which voxcmd resolves from its own real path. `spoken-time.sh` holds the spoken clock-time parser (`parse_clock`: "3 pm", "three thirty pm", "noon", "9 am tomorrow", "friday at 9"), the duration and day parsers (`parse_duration`, `parse_day`), the formatters for the times it prints (`format_at`, `format_length`) and the bar's clock format (`clock_time_format`), used by `timers.sh`, `answers.sh` and `calendar.sh`. `spoken-position.sh` reads a spoken position (`spoken_position`: "two", "twenty five", "second", "twenty first", "13th"; `spoken_ordinal` only ordinals, which need their own suffix, so "2th" is nothing) for the picker replies, workspaces, windows and monitors, never for counts and amounts, where "second" is a unit of time. `monitor-words.sh` names monitors (`monitor_places`, `monitor_named`) for `monitors.sh` and `overview.sh`; see [Monitors](#monitors).

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
force_prefixes=(keybind "key bind")   # "keybind toggle fullscreen" runs the keybind, never another verb
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

As a fallback it never sees a phrase another integration takes. Starting the phrase with "keybind" or "key bind" ([force prefixes](#force-prefixes)) sends it here first and only: "keybind open terminal" runs the Open Terminal bind even when another integration has a verb for "open terminal". "press" is an ignored word, not a force prefix, so "press open terminal" also lands here (no other integration's verb starts with "press") while "press enter" is a [key press](#keys).

- Binds from every submap are offered, one per description, preferring the global one; a submap bind is labelled with its submap, `Lock (System)`. Submap navigation (`+Name`, `Back`, `Exit <submap>`), one-character descriptions and lid switches are left out; the phrases below take its place.
- "submap X", "X submap", "X mode", "enter X mode", "activate X mode" or "go to the X submap" (any `{activate}` or `{focus}` [intent](#intents), or "open") enter the submap named X, word matched against the submap names which-key shows (`cursor mode` is Cursor, `normal mode` is hyprvim's NORMAL). A name shared by several submaps (Delete and hyprvim's DELETE) opens the picker; a name that is no submap is a "no match". "X mode" also reaches a bind named "X mode" that is not a submap (`command mode`). As a fallback, these lose to any other integration's verb, so "performance mode" still sets the power profile.
- "exit submap", "leave the submap", "deactivate submap" (any `{deactivate}`) or "reset submap" go back to the global map like the Exit binds. The voice key is not bound inside submaps, so these are for submaps that keep global keys, the CLI and Voice Help.
- `excluded_descriptions` hides the voice binds themselves and anything about passwords or secrets; edit the list in the file.
- `confirm_labels` asks before closing, killing, locking, logging out, powering off, rebooting, suspending, deleting or clearing.
- A bind that opens the bar's Power prompt (`qs-ipc call power confirm <action>`, the System submap's Lock, Logout, Reboot and Power Off) runs the action straight away once the confirm card was answered yes, so the voice answer is the only confirmation. Without that yes, the bind opens its prompt as usual.
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
| "move slack to workspace 3", "send firefox to workspace three", "move slack to the third workspace" | moves the window there, leaving focus where it is                  |
| "move firefox to special workspace scratchpad", "send slack to the special workspace notes" | moves the window to that special workspace, leaving focus where it is; "scratch pad" finds the existing scratchpad, and a new name is its words joined with hyphens. "special workspace" must be said |
| "swap this window with firefox", "swap it with slack", "switch places with firefox" | swaps the focused window with the named one; focus stays with the window you were in. Refused for a floating window or one on another workspace |
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

### Keys

`keys.sh` presses bare keys in the focused window, or in a bar popup, picker or overview while one is open (a hands-off popup does not count, since it does not take the keyboard), with `wtype -k`. Every phrase starts with "press" or "hit", except "send it" and "send the message", and a bare "enter" or "send" is deliberately nothing: a misheard Enter can submit a form or run a shell line, and "send firefox to workspace 3" is [Apps](#apps).

| Say                                                                      | Presses                              |
| ------------------------------------------------------------------------ | ------------------------------------ |
| "press enter", "hit enter", "press return", "send it", "send the message" | Return                               |
| "press escape", "hit escape"                                             | Escape                               |
| "press tab", "press shift tab"                                           | Tab, Shift+Tab                       |
| "press up", "press down", "press left", "press right" (also "... arrow") | Up, Down, Left, Right |
| "press page up", "press page down"                                       | Page Up, Page Down                   |
| "press backspace"                                                        | BackSpace                            |
| "press home", "press end"                                                | Home, End                            |
| "press delete", "press space" (also "space bar")                         | Delete, space                        |
| "press y", "hit n", "press the letter y", "press y key", "press why" (Whisper hears "y" as "why") | that letter, a to z, pressed in lowercase |

Any of the "press" phrases takes a count after the key: "press down three times", "hit tab twice", "press enter once", "hit backspace 5 times" (digits or the words one to ten). Letters are the exception and press once: "a" is also an article, so "press a button" is left to the keybinds. Only a to z are letters, never digits, so a digit after a key name is always the count. More than 20 presses is cut to 20, and a count that is none ("press tab banana") presses nothing and says so. The key press is its own feedback, so the actions are [silent](#silent-actions). Nothing is pressed while a voxcmd picker or the click overlay is open, or when neither a window nor a bar popup, picker or overview has focus.

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

`tmux.sh` works on sessions by name, and every phrase says `tmux` and names a session, so "open the session launcher" and "switch to X" stay free for the keybinds and windows. Launcher sessions are [Sessions](#sessions).

| Say                                                                                | Does                                                       |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| "go to the X tmux session", "switch to tmux session X", "open the tmux session X", "attach tmux X" | focus or open the session                                  |
| "new tmux session X", "open a new tmux session called X"                           | a terminal on a new session X (attached if X already runs) |

Switching takes any `{focus}` or `{open}` [intent](#intents) form before the session ("take me to the X tmux session", "launch tmux session X"). Both are [silent](#silent-actions) when they work, since the session's terminal shows it; an unknown session still says so. X is matched against running sessions (`tmux list-sessions`) and the tmuxifier layouts in `~/.tmuxifier/layouts`, a layout by the `session_name` it sets or its file name. A layout goes through the Project picker's script (`hypr/scripts/rofi-tmux.sh <layout>`), which focuses its terminal or loads it in a new one. A running session without a layout focuses the terminal titled with its name, else opens a terminal attached to it. An X that matches nothing says so instead of falling through to the keybinds. Tab on its Voice Help entries lists every running session and layout; picking one switches to it.

### Sessions

`sessions.sh` launches the Hyprland [auto-launcher sessions](../../../hypr/.config/hypr/README.md#app-launcher--sessions) by name, the same as picking one in the Session Launcher (`SUPER + SHIFT + O`), saved sessions included:

| Say                                                                              | Does                                |
| -------------------------------------------------------------------------------- | ----------------------------------- |
| "open the work session", "open work session", "launch the work session", "start the work session" | launches the session called work |

X is matched like other integrations' targets, against the names the launcher offers (a leading emoji does not matter). The names come from Hyprland's Lua: `hyprctl eval` calls `Launcher.write_names`, which writes them to a temporary file under `$XDG_RUNTIME_DIR/voxcmd`, since `eval` prints nothing back; launching calls `Launcher.launch(name)`, which runs the session with the picker's own `run`. A name that matches no session says "no session called X" instead of falling through to the keybinds and opening the picker. Launching is [silent](#silent-actions), since the windows appearing shows it worked. Tab on its Voice Help entry lists every session.

Every phrase ends in "session" after a name, so "open the session launcher" still reaches the keybind, and "open a session", "start a new session" and the like (no name) open the Session Launcher to pick one. A phrase with "tmux" in it belongs to [Tmux](#tmux). "Switch to" and "go to" are not accepted, since those are for windows and agents.

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

### Screenshot

`screenshot.sh` runs the rows of the bar's screenshot menu by voice, through the screenshot tool's own flags (`~/.config/hypr/scripts/screenshot.sh`, the `Print` key), so a capture opens the same selector and lands in the same place. Recording stays in [Recording](#recording):

| Say                                                                  | Does                                                      |
| -------------------------------------------------------------------- | --------------------------------------------------------- |
| "screenshot region", "take a screenshot of the area"                 | opens the region selector (`--region`)                    |
| "take a frozen screenshot of the region"                             | the same on a frozen screen (`--freeze`)                  |
| "screenshot the screen", "screenshot the whole display"              | picks a screen (`--screen`)                               |
| "screenshot a window"                                                | picks a window (`--window`)                               |
| "screenshot this window", "screenshot the focused window"            | the focused window at once (`--focused`)                  |
| "grab text from a region", "ocr the area"                            | copies the text of a region (`--text`)                    |
| "pick a color", "color picker"                                       | copies the colour of a pixel (`--pixel`)                  |
| "scrolling screenshot", "take a scroll capture"                      | scroll capture as an image (`--scroll-image`)             |
| "scroll text", "read text from a scrolling capture"                  | scroll capture read to text (`--scroll-text`)             |

- The actions are [silent](#silent-actions) and detached, since the selector or the capture's own notification is the feedback.
- A bare "screenshot" has no verb here and still reaches the Print bind in Keybinds, which opens the bar's menu.
- The two scroll flags exist only for this: scroll capture runs in the bar's overlay, so without a bar screenshot.sh says "needs the bar" instead of falling back to rofi.

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

- **Ending it:** say `done`, `I'm done`, `that's all`, `cortana done` (see [the wake word](#wake-word)), or a verb and the mode: stop, exit, quit, end, leave, finish, close or turn off, then "clicking", "click mode" or "clicking mode" ("quit click mode", "leave the click mode", "turn off click mode"; "click mode off" works too, and "okay", "please" or "now" around it is fine); stay silent for about 10 s (`VOXCMD_SESSION_NO_SPEECH_SECS`), a fan or room noise included, since a turn needs [more speech](#voice-sessions) than a command and Whisper's stock guesses at noise ("Thank you.", "The End") are not turns; or give three turns in a row that did nothing (not understood, a target found nowhere, a failed click, or an overlay cancelled). The bare verbs `cancel`, `exit`, `stop`, `quit` and `close`, and `never mind`, are button labels, so in click mode they are clicked like any other target (the one mode where a bare exit word is not an exit). It also ends after 5 minutes or 40 turns. Opened inside [rapid mode](#rapid-mode) it returns to it; "rapid mode" and "type mode" are never clicked, they switch. "start typing" is clicked like any other text; "cortana start typing" switches to type mode.
- **Sequences:** "save and then done" clicks "save", then leaves click mode; a turn with "and then" in it is split into steps, so on-screen text that contains "and then" cannot be clicked by saying it whole. The same last-step exit applies in rapid mode.
- **Needs auto-stop:** silence is the only thing that ends an idle session, so with [auto-stop](#auto-stop) off or unable to listen, "click mode" says "Click mode needs auto-stop" and does not start.
- **Ambiguous targets:** the [numbered overlay](#click-hints) shows and listens as usual, with auto-stop's own silence allowance; after the pick and the click the session carries on.
- **Indicator:** while it is open the bar shows the mode (its label, coloured per kind, with the exit hint as a tooltip) and the voxtype OSD's title carries it too, so an open microphone is never invisible. Both read `$XDG_RUNTIME_DIR/voxcmd/session.json` and, while it is there, check every few seconds that `/proc/<owner>` still exists, so a listener killed outright does not leave the indicator up.

### Click hints

`voxcmd-hints [--listen] <label> <choices-json>` is the picker `click.sh` uses for several matches (`pick_command`). Choices are `{id, label, box: [left, top, width, height]}`; it prints the picked id and exits 1 on cancel. The Quickshell bar draws a numbered keycap and an outline over each box (`qs-ipc call clickhints`, see the bar's README), and the other screens stay quiet. Answer by:

- number keys `1`-`9` and `0` (box 10), or a click on a box; `Esc`, `q` or a click anywhere else cancels, and `?` lists the keys;
- voice, as with any [picker](#answering-by-voice): "two", "the second one", a label's words, "cancel". With `--listen` (a spoken command) the reply recording starts just before the numbers appear, and an unclear reply listens once more. The overlay shows Listening or Transcribing, and its 10 s timeout waits while voxtype records.

The overlay writes the number into the pick's FIFO, a voice reply the displayed label; either maps to the choice's id. While it waits, `voxcmd-hints` keeps the same `pending-pick.json` as `voxcmd-pick`, with `kind: "hints"`, `listen_again` and numbered labels. Without the bar, with more than ten choices, or when a choice has no box, it hands the pick to `voxcmd-pick`.
### Monitors

`monitors.sh` focuses a monitor, or moves the active window to one, from anywhere (no overview needed):

| Say                                                                                      | Does                                              |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------- |
| "go to the left monitor", "focus the center screen", "take me to the top right display"   | focuses that monitor (any `{focus}` form)         |
| "go to monitor two", "switch to monitor number three", "go to the second screen", "the 4th display" | focuses that slot                    |
| "go to the laptop screen", "focus the built-in display", "go to laptop", "focus the laptop" | focuses the built-in panel (the noun is optional for the panel alone) |
| "move this window to the right monitor", "move it to monitor two", "move this window to the first monitor", "send the window to the laptop screen", "send window to laptop" | moves the active window there; focus stays where it is, as the overview's own move to a monitor |

- **Words:** `left`, `right`, `middle`/`center`/`centre`, `top`, `bottom` and combinations ("top left"), from the monitors' geometry. Monitors are grouped into rows (top to bottom), then columns within a row, so a laptop below a row of three monitors is `bottom` and the three are `left`, `middle` and `right` (each word only where there is more than one row or column to tell apart). A slot is the number `SUPER + CTRL + n` focuses and the overview uses, said as a number ("monitor two", "monitor 2") or an ordinal ("the second monitor", "the 2nd monitor", "tenth", "10th", "twenty first"); ordinal N is the same slot as "monitor N". An ordinal above the monitor count says there is no such monitor, as "monitor nine" does. A monitor Hyprland's slot lookup does not name has no slot and is never guessed: a slot phrase that could mean it says "can't tell which monitor is slot N", while the position words and "laptop" still work. `laptop`, `built-in` and `internal` name a built-in panel, found by connector name (`eDP-*`, `LVDS-*`, `DSI-*`). A word that fits no monitor or several says so ("more than one top monitor") and does nothing; a name that is no monitor word at all ("go to the system monitor") is left to the other integrations.
- **One rule:** the overview's `horizontal`, `vertical` and `slot` come from `overview/Voice.js`; `monitor-places.jq` (in the share dir) computes the same from `hyprctl monitors -j`, and `monitor-words.sh` resolves the words against either, so the overview's phrases ("move two and four to the left monitor") and these agree. `run-monitors.sh` runs both on the same layouts and fails when they differ. Slots come from Hyprland's own lookup (`lib.workspaces`), read through a file under `$XDG_RUNTIME_DIR/voxcmd/`.
- **Routing:** the noun ("monitor", "screen", "display") must be said for a position or slot, but not for the built-in panel ("go to laptop", "send window to laptop"), and "window" alone or "active window" is the window moved; moving takes only the active window ("this window", "it"); "move firefox to workspace 3" stays with [Apps](#apps) and "move two and four to the left monitor" is the [overview](#overview)'s, which takes its phrases first while it is open.
- Tests: `home/voxcmd/tests/run-monitors.sh` (a step of `run.sh`) on fixture layouts in `tests/fixtures/monitors/` (the owner's four-monitor setup, a lone laptop, side by side, stacked, a grid, five in a row); the sandbox answers the slot lookup from `SANDBOX_MONITOR_SLOTS`. Entry phrases are in `phrases.tsv`.

### Overview

`overview.sh` drives the Quickshell workspace overview (the contract is also in the Quickshell README, "Workspace overview and voice") by voice: it names windows by the numbers the overview draws on them and calls the overview's own actions, so voice and keys share one selection (the overview's marks) and run the same code.

| Say                                                                                  | Does                                                                                       |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `show workspaces`, `open overview`, `show the workspace overview`                    | Opens the overview and a voice session on it (numbers appear on every window)              |
| `show numbers`, `number the windows`                                                 | The same session on an overview you opened by key                                          |
| `two`, `two and four`, `mark one, three and five`                                    | Marks those windows (idempotent; lists split on "and" and commas, digits, words or ordinals: "first and third", "the second window", "close the third one"). "workspace number 7" and "work space 7" are heard as "workspace 7"          |
| `unmark three`, `clear`, `unmark all`                                                | Unmarks, or clears every mark                                                              |
| `move two to workspace three`, `move to workspace 7`, `move them to workspace 7`     | Moves them; with no number said (`them`, `these`, `it`, `the marked/selected windows`, or nothing) the marked ones, or the selected window when none is marked, as `m` does |
| `move two and four to the left monitor`, `send them to the right screen`             | Sends them (or the marks or selected window) to that monitor's visible workspace           |
| `close two`, `close the marked windows`, `close them`, `close the selected`          | Asks "Close 2 windows?" on the [confirm card](#confirm), then closes                       |
| `focus two`, `go to two`                                                             | Focuses the window and closes the overview                                                 |
| `go to workspace three`, `go to the first workspace`, `workspace 3rd`                                           | Focuses the workspace and closes the overview                                              |
| `move workspace three to the right monitor`                                          | Sends the workspace to that monitor                                                        |
| `swap workspaces two and five`, `swap the second and fifth workspaces`, `swap workspace 1 with 2`                            | Swaps the two workspaces' windows                                                          |
| `close overview`, `done`                                                             | Closes the overview and ends the session                                                   |

- **Numbers:** windows are numbered 1.. by monitor slot (the monitor `SUPER + CTRL + n` focuses; Hyprland's order for unslotted ones), then workspace id, then reading order (top to bottom, left to right) inside the workspace, the order `]`/`[` cycle in. The overview computes them and draws them while the voice session is open; voxcmd only reads them, so the two cannot disagree. Workspaces are said as "workspace three" or by ordinal ("the third workspace", which voxcmd rewrites to "workspace 3" before routing, so Keybinds' "go to workspace 3" hears it too) (digit keys in the overview mean the same ids; in the special view the nth special workspace). Monitors are said as in [Monitors](#monitors): by position (`left`, `right`, `middle` or `center`, `top`, `bottom`, "top left" where both apply), by slot ("monitor two") or as the `laptop`; a word that fits no monitor or several says so and does nothing.
- **Routing:** while the overview is open its phrases go to it before any other integration, which is how "close two" and "go to workspace three" never reach Apps and Keybinds. With the overview open and no session, a phrase it understands runs and the session attaches; a phrase it does not (`open firefox`) is routed as usual. In the session every turn is a phrase for the overview alone: what it does not understand is "no match", never another integration's command. "Show workspaces" opens it from anywhere.
- **Selection:** voice marks and the keys' marks are the same list, so `Space` on one window and "four" on another give two marks, and `m`, `x` and the voice verbs act on them alike. A verb with numbers acts on those windows only; without any ("move the marked windows to workspace 5") on the marks. A number the overview does not show reports `no window 9` and acts on nothing.
- **Ending it:** `done`, `close overview` and the other exits close the overview with the session. So does a bare `exit`, `stop`, `cancel` or `quit`, which ends the whole voice session, so nothing modal is left open with nothing listening. Focusing a window or workspace ends it too, since the overview closes. Silence for 20 s ends only the session, and so does closing the overview by key: a listen checks `session_alive` before it opens the microphone again and the turn heard after the close is routed as a normal command.
- **Contract:** the overview writes `$XDG_RUNTIME_DIR/voxcmd/overview.json` whenever what it shows changes, and `{"version":1,"open":false}` when it closes:

  ```json
  {"version": 1, "open": true, "special": false, "marks": ["<address>", "..."],
   "monitors": [{"id": "DP-1", "slot": 1, "horizontal": "left", "vertical": "", "focused": true}],
   "items": [
     {"n": 1, "kind": "workspace", "id": "1", "label": "1", "workspace": "1", "monitor": "DP-1", "marked": false, "windows": 3, "shown": true},
     {"n": 2, "kind": "window", "id": "<address>", "label": "kitty: title", "workspace": "1", "monitor": "DP-1", "marked": true}]}
  ```

  A window's `n` is its voice number and `id` its address; a workspace's `n` is the number said in "workspace three" and `id` its reference (`"3"`, or `"sp:<name>"` for a special one); `slot` is 0 for a monitor without one; `horizontal` and `vertical` are empty while all monitors share that axis. voxcmd asks `qs-ipc call overview state` (`open` or `closed`) as well, since a bar that died leaves the file behind, and acts through `qs-ipc call overview act <verb> "<args>"`, which answers `ok` or `error: <why>`: `mark`, `unmark`, `close` and `focus` take window addresses (none: the marks), `move <workspace> <addresses...>`, `send <monitor> <addresses...>`, `workspace <ref>`, `workspace_to_monitor <id> <monitor>`, `swap_workspaces <ref> <ref>`, `clear` and `close_overview`.
- **For other surfaces:** `surface_open` in an integration (a function that succeeds while its bar surface is up) gives it the phrase before any verb is matched, through that integration's verbs alone, and a phrase it matches nothing in is routed normally. `session_alive` ends a mode whose surface closed. The calendar, weather and Firefox tabs can take part the same way: publish items and take one action entry.
- Needs the bar (`qs-ipc`) and, for a session, [auto-stop](#auto-stop). Tests: `home/voxcmd/tests/run-overview.sh` (a step of `run.sh`) against a fixture `overview.json` and the sandbox's stub bar; entry phrases are in `phrases.tsv`.

### Rapid mode

`SUPER + CTRL + COMMA` (Leader, `CTRL + COMMA`), `voxcmd rapid`, or saying "rapid mode" (also "start rapid mode", "enter rapid fire mode") opens a [voice session](#voice-sessions) where every turn is routed as a normal command, so a run of commands needs no key press between them. Force prefixes, the LLM hook and fallbacks work as usual, a confirm card is answered by voice, and a picker of several options listens for its answer too.

- **Ending it:** `done`, `I'm done`, `that's all`, `done with rapid mode`, or a verb and the mode ("stop rapid mode", "quit rapid fire mode", "rapid mode off"), `cortana done` and the other [wake word](#wake-word) forms; silence for about 10 s (`VOXCMD_SESSION_NO_SPEECH_SECS`); three turns in a row that did nothing; the Stop Voice key; or 5 minutes or 40 turns. A bare `exit`, `stop`, `cancel` or `quit` ends the session and leaves rapid mode (`stop` does not pause the music here; outside a session it still does), and so ends anything opened over it too. In a [sequence](#sequences) it works as the last step.
- **Other modes:** "click mode" and "type mode" open inside it and return to it when they end. Saying "rapid mode" inside click mode comes back to it.
- **Sequences:** a phrase of several steps ("open firefox and then go to youtube") is one turn, and counts as missed only when no step ran. A card declined or a picker cancelled is a missed turn too. See [Sequences](#sequences).
- **Needs auto-stop**, like every session.

### Type mode

"Type mode" (also "typing mode", "dictation mode", "start typing mode", and "start typing" or "begin typing" on their own; inside [click mode](#click-mode) those two are click targets, and "cortana start typing" switches) types what you say into the focused window. It is one voxtype recording, transcribed and typed once when it ends; nothing is typed before then. It uses the same transcription as Speech to Text (the same voxtype model, vocabulary and replacements) and types with `wtype`. A toast says how to finish it as it starts.

- **Ending it**, by the [wake word](#wake-word) and what follows it, which the [Cortana wake listener](#cortana-wake-listener) hears during the recording (it keeps listening through type mode's recording, and only through it):
  - `cortana stop` (also `stop typing`, `stop recording`, `done`, `stop dictation` and the other exits of the mode) types it and leaves type mode, back to rapid or click mode when it was opened from one.
  - `cortana send`, `cortana send it`, `cortana send message` or `cortana press enter` types it, then presses Return.
  - `cortana cancel` or `cortana never mind` types nothing.
  - `cortana stop listening` (or `stop everything`, `end session`) types it and ends the whole session.
  - Any other words after the wake word ("cortana new paragraph") are dictation, typed with the rest.
  The ending at the end of the transcript is cut before typing ("...the plan. Cortana, stop." types "...the plan."); the wake word elsewhere in a sentence is text. The table is `session_endings` in `typing.sh`, one row per ending.
- **Without the wake listener**, the voice key ends the recording and types it, leaving type mode; the start toast says so. With it, the voice key does the same.
- **Stop Voice** types it too, then ends the session.
- Once the recording has ended, a voice key pressed before the text is typed (twice, or just after the quiet end) starts nothing and says it is still typing, so the dictation is never lost to a new recording.
- **Bounds:** voxtype stops a recording at its `max_duration_secs` (300 s), so type mode stops at 295 s (`VOXCMD_TYPE_MAX_SECS`), types what was said and ends with a toast naming the limit it reached; no new recording starts. 10 s of quiet after speech also stop and type it, as "cortana stop" would, and 10 s with no speech at all end the mode, typing nothing (both `VOXCMD_TYPE_IDLE_SECS`). Plain "stop typing", "done" and "click mode" are text; only the wake word makes a command. The recording counts toward neither the session's 40 turns nor its 5 minutes.
- **What is typed:** control characters and newlines in the transcript become spaces, and the text goes to `wtype -- <text>`, so a leading dash or a stray escape does nothing special. A transcript that is only one of Whisper's guesses at noise ("Thank you.", an echo of the wake-word prompt) or only the ending is not typed. Nothing is typed, and a toast without the text says so, while a voxcmd picker, card or click overlay is open or no window has focus; a failed `wtype` gives an error toast with only a character count.
- **Privacy:** the debug log, toasts and `session.json` hold lengths and the ending's name, never the text. A transcript heard in type mode whose session has ended is discarded, never routed as a command.
- A live preview of the text is not possible: voxtype gives no partial audio or text.

### Wake word

The wake word is `cortana`, fixed: the [wake listener](#cortana-wake-listener)'s acoustic model only knows that word, so it is a constant in voxcmd rather than a setting. It starts a command to the mode a session is in. `VOXCMD_WAKE_ALIASES` lists other spellings Whisper produces (`kortana|cortona` unless set; setting it replaces that list, e.g. `kortana|cortona|cortina`); set it in the user manager's environment (`systemctl --user set-environment`). `voxtype-daemon` appends "Voice commands start with Cortana." to the initial prompt (like `prompt.d`'s words) so Whisper spells it one way, and the listener's confirmation passes the same prompt: both build it with `voxtype-prompt` (voxtype package). Restart the daemon after changing `prompt.d`.

- **In a session**, at the start of a turn, `cortana <command>` is a control command and never clicked or routed as content: `done` leaves the current mode, `stop` ends the session, the current mode's own exit ("stop rapid mode") and commands, and entering or leaving another mode ("rapid mode", "type mode", "click mode"). Anything else is routed as a command with the wake word stripped, as outside a session. [Type mode](#type-mode) is one recording, which the wake word ends (`cortana stop`, `cortana cancel`, ...) through the wake listener; any other `cortana ...` there is dictation.
- **Outside a session** the word is only stripped, with a leading "hey": "cortana open firefox" and "hey cortana open firefox" are "open firefox". [The wake listener](#cortana-wake-listener) hears the same word.
- Matching is on the transcript normalized as for any phrase: case and punctuation do not matter ("Cortana, stop typing.").

`voxtype-daemon` runs voxtype with `-q` (errors only), so transcripts stay out of `journalctl --user -u voxtype`; set `VOXCMD_LOG_TRANSCRIPTS=1` in the user manager's environment and restart the daemon to log every transcript at INFO again. Transcripts logged before this change stay in the journal until it rotates.

### Cortana wake listener

Saying "Cortana" starts a voice command, with no key: the same as `SUPER + COMMA`. Wait for the bar's listening cue (below) before saying the command: words said between "Cortana" and the recording starting are lost. It is off by default, because it keeps the microphone open while it listens. The detector's model is trained on the bare word, the same [wake word](#wake-word) a session's control commands start with; "hey cortana" works too.

- **Install:** `python-openwakeword` (AUR) and `onnxruntime-cpu` are in `packages/arch-aur.ini` and `packages/arch.ini`, so the installer has them. The unit ships in the `systemd` package (`voxcmd-wake.service`), stowed with the rest.
- **Models:** the wake model, `cortana.onnx`, is trained for this repo on openWakeWord v0.5.1's features and tracked in voxcmd's share folder (`~/.local/share/voxcmd/cortana.onnx`), which `voxcmd-wake` finds through its own real path. The two feature models every openWakeWord model runs on, `melspectrogram.onnx` and `embedding_model.onnx`, are not packaged: the first `voxcmd wake on` downloads them from the [openWakeWord v0.5.1 release](https://github.com/dscripka/openWakeWord/releases/tag/v0.5.1) into `~/.local/share/voxcmd-wake/models/` (`VOXCMD_WAKE_MODEL_DIR`), a folder outside the repo, and shows a toast for each file. Each file, the tracked one included, is checked against a sha256 pinned in `voxcmd-wake` before every start, and a download also after it arrives: a download that differs is deleted and refused, and a file already there that differs is deleted and fetched again. Earlier versions downloaded the models, `hey_jarvis_v0.1.onnx` among them, into `~/.local/share/voxcmd/wake-models/` (in the repo, since stow folds that folder); that folder is no longer read and can be deleted.
- **Switching it:** `voxcmd wake on|off|toggle|status`, or `SUPER + CTRL + PERIOD` (Leader, `CTRL + PERIOD`) to toggle, with a toast. `on` starts `voxcmd-wake.service` for this login only; nothing enables it, so it is off again after the next login. To keep it on, run `systemctl --user enable voxcmd-wake` (and `disable` to undo; `off` still stops it). Off releases the microphone completely.
- **Bar:** the Voxtype icon in the bar carries a small dot while the detector holds the microphone. It dims while the detector is paused (hover for why: another app recording, media playing, or a voice command running) and goes when it is off. When voxtype starts recording after a confirmed trigger, the dot turns brighter and blinks briefly: speak then. It clears when the recording ends. A trigger that is not confirmed shows nothing.
- **Listening through type mode:** while voxtype records [type mode](#type-mode)'s recording (`session.json`'s current mode has `wake_listens`, with a live owner), the listener keeps listening, ahead of every pause below, so "cortana stop" can end it. A trigger there sends 3 s of audio ending 1.2 s (15 frames) after it, so the words after the wake word are in the clip, and voxcmd acts on them itself: the confirmation records the ending in the session and stops or cancels the recording, under the session lock and only while the recording the trigger was heard in runs. The listener names that recording to the confirmation as the mode's `frame_id` and the owner it read from `session.json` at the trigger, so a confirmation that outlasts its recording never ends the next one. Such a verdict never starts a listen. The cooldown after it is only as long as that tail, and a clip cut while another confirmation runs waits for it, so a stop said just after another "cortana ..." still counts.
- **Paused, microphone released,** while voxtype records (`$XDG_RUNTIME_DIR/voxtype/state`) and while a [voice session](#voice-sessions) is open (`session.json` with a live owner, checked by pid and start time as voxcmd does, since a session's microphone is already its own between turns); it re-opens a second or so after they end. Two more pauses are switches in Settings > Input > Voice, read when the listener starts: **While mic is active** (`VOXCMD_WAKE_PAUSE_FOR_MIC`, default pause) pauses while another app records from a microphone, and **While media plays** (`VOXCMD_WAKE_PAUSE_FOR_MEDIA`, default keep listening) pauses while `playerctl --all-players status` says Playing. With media set to keep listening the listener never runs `playerctl`, and a song or video that says "Cortana" can start a command. Another app records when `pactl -f json list source-outputs` has a capture stream that is not voxcmd's own recording (the listener's and `voxcmd-autostop`'s `pw-record` carry the stream property `voxcmd.tag`, valued `wake` or `autostop`, so another program using `pw-record` still counts), not voxtype's recording, not on a monitor source and not corked; a call muted in its app keeps its stream and counts, and a missing or failing `pactl` means not active. With the switch on, the listener runs `pactl` once a second while it is not otherwise paused, and never with it off. A paused state in `wake.json` carries `reason`, the name of the check that paused (`voxtype_recording`, `session_open`, `media_playing` or `mic_in_use`; the check ahead of them, `dictation`, only ever keeps it listening; absent when the microphone stream failed rather than a check paused), and the file is rewritten only when the state or reason changes; the bar shows a dimmed dot with the reason as its tooltip. So a voice command, dictation or a session turn is never heard twice.
- **What a trigger does:** it needs a score of at least 0.8 held for three frames in a row (80 ms each), which the model reaches near the end of the word. A trigger is then confirmed before anything starts, since the detector alone also fires on everyday speech (74 times in 3.2 hours of ordinary home audio at 0.8): the listener keeps the last 2 s of the audio it has read, plus the 0.16 s (2 frames) after the trigger so a lenient level does not cut the word off, writes them as a 16 kHz mono WAV into an anonymous in-memory file, and runs `voxcmd _wake-confirm /dev/stdin` with it as stdin, off the audio loop so the detector keeps reading. That has `voxtype -q --initial-prompt "<the daemon's prompt>" transcribe` turn the audio into text with `base.en` (about 0.4 s; `VOXCMD_WAKE_CONFIRM_MODEL`, below), while the voxtype daemon runs and matches it against the wake word and its aliases where voxcmd keeps them. It is `base.en` and not the daemon's larger model because with this prompt the larger model heard "Cortana" in 20 of 300 clips that did not say it, and `base.en` in none. Heard, the listener runs `voxcmd listen --start-only`, which never stops a recording already under way; anything else shows nothing. A `voxtype transcribe` that fails or takes longer than 6 s counts as not heard. A trigger is followed by 3 s in which nothing counts, and triggers while a confirmation runs are skipped. A verdict that arrives while the listener is paused (voxtype records, a session opened), after the stream was closed and reopened since the trigger, or more than 4 s after the confirmation started is dropped, so a late "heard" never starts a recording.
- **Tuning:** the default is strict, because every false trigger costs a Whisper transcription (a missed "Cortana" costs one more try). Settings > Input > Voice picks it as Strict (the default, 0.8 and 3 frames), Balanced (0.7, 3) or Relaxed (0.6, 3); of 20 recorded takes, all triggered from 0.5 to 0.75, 19 at 0.8 and 18 at 0.9. A change restarts the unit if it is running. The level is saved to [`voice.env`](#saved-voice-settings) as `VOXCMD_WAKE_SENSITIVITY`, and the levels' numbers are `voxcmd-wake`'s own, one row per wake model. The two variables below override the level's numbers. Or set these in the user manager's environment (`systemctl --user set-environment`), which wins over the file, and restart the unit, or in a drop-in:

  | Variable                    | Default | Meaning                                                   |
  | --------------------------- | ------- | --------------------------------------------------------- |
  | `VOXCMD_WAKE_THRESHOLD`     | `0.8`   | score a frame needs, 0 to 1 (lower hears more, and more false starts) |
  | `VOXCMD_WAKE_FRAMES`        | `3`     | consecutive 80 ms frames at or above the threshold        |
  | `VOXCMD_WAKE_COOLDOWN_SECS` | `3`     | seconds after a trigger in which nothing counts           |
  | `VOXCMD_WAKE_MODEL_DIR`     | `~/.local/share/voxcmd-wake/models` | where the downloaded feature models are kept |
  | `VOXCMD_WAKE_CONFIRM_MODEL` | `base.en` | voxtype model that confirms a trigger; read from `${XDG_DATA_HOME:-~/.local/share}/voxtype/models/ggml-<model>.bin`, and when that file is missing the daemon's model is used instead (logged in the debug log) |

  To see the scores, turn on the [debug log](#debug-log) and read lines from `voxcmd-wake` (a score line for every frame at 0.2 or more, each trigger and its verdict: `confirmed`, `rejected` or why it failed).
- **Privacy:** audio is read into memory 80 ms at a time, and only the last 2 s are kept. A trigger's 2 s go to the confirmation in a memfd, an in-memory file with no path, which is gone once the confirmation ends; they are never written to disk, and `voxtype transcribe` runs locally, so nothing leaves the machine except the one-time model download. What Whisper heard is never logged or shown: the log holds scores, verdicts and times only, and only while the debug log is on.
- **Failures:** if `pw-record` dies it is restarted after 1 s, then 2, 4 and so on up to 30 s. Missing `python-openwakeword`, a missing or changed `cortana.onnx`, or a failed or mismatched download gives an error toast; the unit does not retry a missing package. `systemctl --user status voxcmd-wake` has the rest. The unit runs `voxcmd listen`, which needs `WAYLAND_DISPLAY` (wtype, wlrctl, grim), `HYPRLAND_INSTANCE_SIGNATURE` (hyprctl, `qs-ipc`) and `PATH` in the systemd user manager's environment; `XDG_RUNTIME_DIR` and the session bus are the manager's own. Hyprland's autostart imports them with `dbus-update-activation-environment --systemd`; check with `systemctl --user show-environment | grep -E 'WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE'`. After updating the config, log in again (or run the import by hand) so the manager has the signature, and restart the unit.

### Saved voice settings

Settings > Input > Voice saves its choices to `${XDG_STATE_HOME:-~/.local/state}/voxcmd/voice.env`, a state file outside `~/.config/voxcmd` (which is stow-folded into the public repo). Each reader takes a setting from its environment variable if set, else from this file, else its built-in default, so a variable in the user manager's environment always wins. A line is `KEY=VALUE` with a number (or, for the sensitivity, one of its level names), and a key that is absent means the default. The file is read as data and never sourced: any other line is ignored, and a bad value in it falls back to the default (a bad environment value is still refused by `voxcmd-wake`).

| Key                            | Default      | Read by                       | Meaning                                                              |
| ------------------------------ | ------------ | ----------------------------- | -------------------------------------------------------------------- |
| `VOXCMD_WAKE_SENSITIVITY`      | `strict`     | `voxcmd-wake`                 | `strict`, `balanced` or `relaxed`; `VOXCMD_WAKE_THRESHOLD` and `_FRAMES` in the environment override its numbers (the file never holds them) |
| `VOXCMD_WAKE_PAUSE_FOR_MEDIA`  | `0`          | `voxcmd-wake`                 | 1 pauses the listener while a player plays; 0 keeps it listening     |
| `VOXCMD_WAKE_PAUSE_FOR_MIC`    | `1`          | `voxcmd-wake`                 | 1 pauses it while another app records from a microphone; 0 keeps it listening |
| `VOXCMD_DUCK_MEDIA_VOLUME`     | config.toml  | `voxtype-daemon`              | percent of its volume ducked media keeps while voxtype records (0 to 100); passed as `voxtype --duck-media-volume`, otherwise `duck_media_volume_percent` in voxtype's `config.toml` (30) applies |

The shell side is `voice-env.sh` in voxcmd's share folder (`voice_env_value KEY`), sourced, when the voxcmd package is stowed, by `voxtype-daemon`; `voxcmd-wake` has its own Python reader. `VOXCMD_VOICE_ENV_FILE` points all of them at another file (for tests). Wake sensitivity, the pause switches (exactly 0 or 1) and ducking are read once when their service starts, so Settings runs `systemctl --user try-restart` on the unit after a change; a voxtype restart cuts off a recording in progress.

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

`firefox.sh` and `firefox-sites.sh` (with the helper `~/.local/share/voxcmd/firefox-tab`) reach the browser itself. Tabs and sites are read, never written: the session store (`sessionstore-backups/recovery.jsonlz4`) for tabs, a copy of `places.sqlite` and its write-ahead log for bookmarks and history, from the profile `installs.ini` names. Windows are matched to the store by their title. Tabs and the address bar are driven by typing into the focused Firefox window with `wtype`, through Firefox's own keys, so nothing needs installing in Firefox.

#### Companion extension (optional, instant switching)

With the extension in `extras/voxcmd-firefox/` loaded, tabs are listed live and switched by the tab itself: with no typing, instead of about 1.9 s, unloaded tabs and identically titled ones included. Firefox starts the native host `~/.local/share/voxcmd/firefox-host` for the extension, and it serves `$XDG_RUNTIME_DIR/voxcmd/firefox.sock` (mode 0600): one JSON line request (`{"cmd": "tabs"}`, `{"cmd": "activate", "tab_id": 7, "preface": "<nonce>"}` or `{"cmd": "clear_preface", "window_id": 2}`), one JSON line reply (`{"ok": true, "result": ...}` or `{"ok": false, "error": ...}`). Tab candidates then carry the id `tab:<tab_id> <title>`. The extension has only the `tabs` and `nativeMessaging` permissions and opens nothing.

One-time setup: stow `voxcmd`, run `just firefox-host` (the installer does too), then load the extension (temporarily from `about:debugging`, or signed; see its README). `firefox-tab` uses the socket only when `XDG_RUNTIME_DIR` is set and the socket and its directory belong to you and the directory is private. Without the socket, or when the host cannot be reached or answers the tab list badly, everything above works as before through the session store and the address bar, and `voxcmd debug on` logs why. Once an `activate` has been sent, a failure is reported and the address bar is not tried, since the tab may already have switched. The window is found by the nonce the extension puts in front of its title (not by tab title), and a window that is not found is no failure. Private windows are invisible to the extension and are listed by window title as before.

| Say | Does |
| --- | --- |
| "go to weekly notes", "find the weekly notes tab", "go to example.com" | Focuses the window and tab whose title or site matches; several matches ask with numbers. A domain with no tab open is opened in a new tab. "go to firefox" is still the window |
| "open code hub in firefox", "open website code hub", "open example.com" | Opens a bookmark, a visited site or a domain in a new tab; nothing found is searched when Firefox was named. A bare "open X" reaches this only when no app, keybind or other integration has it |
| "open code hub here" | The same, in the focused tab |
| "new tab", "close tab" | Ctrl+T and Ctrl+W in the focused Firefox window |

- "Go to" focuses the window, then types Ctrl+L, `% <title>` (`%` limits the address bar to open tabs) and Return. Nothing is typed when the session store, read again just before, has no tab with exactly that title, because Return on a miss would search the web in the current tab; the tab the window already shows is not typed for either, as the address bar leaves it out of its results.
- Firefox ranks the open tabs, and the title's words may match anywhere in another tab's title or address, so a longer title that contains this one can come first. The same title in two windows is not told apart: the focused window's tab is preferred when both have the same address, and otherwise Firefox's ranking decides. The first result is not confirmed before Return.
- The store lags a tab switch by up to 15 seconds, so a window is also found by any of its tabs' titles. Private windows are in no store and are found by the title they show.
- While `firefox.sh` is installed, `apps.sh` stops matching Firefox windows by their title, so a tab is offered once.
- `tests/run.sh` (section "firefox") and the Firefox rows of `tests/phrases.tsv` run on a made-up profile built by `tests/firefox-profile`; section "firefox live" runs against `tests/firefox-fake-host`, and `tests/run-firefox-extension.sh` tests the host (`firefox-host-test`) and the extension's background script.

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
- an ordinal: `two`, `the second one`, `number 3`, `first`, `twelfth`, `twenty first`, `3rd`, `last` (a wrong suffix such as `2th` is no ordinal);
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

A session keeps the microphone re-opening after each spoken turn, so related commands need no repeated verb. [Rapid mode](#rapid-mode), [click mode](#click-mode), [type mode](#type-mode) and the [overview](#overview)'s session are the modes so far. A session is a stack of modes: one opened from another's turn (rapid mode's "click mode", click mode's "type mode") goes on top of it, and when it ends the session returns to the mode underneath; saying the entry phrase of a mode already open underneath goes back to it, and of the current mode does nothing. The bottom mode ending, or a cap, Stop Voice or `end-session`, ends the session and every mode in it. An integration opens a mode from an action with `session_begin <kind> "$file" "<label>"` and leaves it with `session_leave <kind> [reason]` (which also leaves the modes opened over it, and fails when the kind is not open), and supplies `session_rewrite`, which prints the phrase to route for what was said (nothing when it names nothing usable); with none, the words are routed as spoken. A turn of several [steps](#sequences) is split first, and `session_rewrite` runs on each. `session_exit_phrases` (optional) is a regex of further phrases that end the mode, besides "done", "I'm done" and "that's all", matched whole before `session_rewrite`. A bare "exit", "stop", "cancel" or "quit" ends the whole session with every mode in it (`session_bare_exits=0` turns that off for a mode where they are content, as in click mode; `session_default_exits=0` does too). `session_miss_actions=(action ...)` lists actions that mean the turn found nothing to act on, and `session_ended` (optional) runs in the background whenever the mode ends, to tidy what it left on screen, and `session_alive` (optional) fails once the mode's screen is gone, which ends the mode before the next listen or turn. More optional settings: `session_exit_hint` (what the bar shows as the way out), `session_allows_switches=1` with `mode_actions=(action ...)` (while this mode is open, a turn that is exactly one of these actions' phrases, from any integration, runs instead of being rewritten: click mode's "rapid mode"), `mode_entry_actions=(action ...)` (actions that open a mode but must not switch modes from inside one, so they stay out of `mode_actions`; a [sequence](#sequences) treats them as mode switches, so they can only be its last step), `session_default_exits=0` (the exit words and phrases apply only after the wake word), `session_handle_turn <words> [ending]` (the mode takes the words itself, as type mode types them), `session_private=1` (no words in logs or toasts), `session_open_ended=1` (its time is not counted against the session's), `session_listen_silence_secs`, `session_listen_max_secs` and `session_listen_no_speech_secs` (its listens' auto-stop), and the one-recording settings type mode uses (see `typing.sh`): `session_one_recording=1` (the mode is one recording, handed to `session_handle_turn` once with its ending's action and then left), `session_wake_listens=1` (the [wake listener](#cortana-wake-listener) listens through it) and `session_endings` (`"<action> <regex>"` rows matched against the words after the wake word: `discard` cancels the recording, `end_session` ends the session after handling it, and any other action is passed to `session_handle_turn`).

- **State:** `$XDG_RUNTIME_DIR/voxcmd/session.json`, the current mode as `{kind, integration, label, exit_hint, unclear, mode_started, last_heard, open_ended, one_recording, wake_listens}`, plus `recording_owner` (the listener of a one-recording mode's recording, which has its transcript to type for as long as it owns the session) and `ending` (`{action, by}`, by `voice`, `key`, `cap`, `pause` or `idle`) once that recording has been ended, with the session's `{started, owner, owner_start, turns}` and `stack`, the modes underneath it, bottom first, each with the mode fields (`[]` with one mode). `owner` is the PID of the listener that hears the next turn and `owner_start` its start time (field 22 of `/proc/<pid>/stat`), so a reused PID is not mistaken for it; each new listen takes it over, and `owner_handover` is set from the moment its recording starts until its listener is the owner. A session whose owner has died is stale: it is deleted the first time anything looks, and never keeps the microphone open. Every change holds `flock` on `session.lock` beside it.
- **Routing:** while a session is open, `voxcmd listen` sends the transcript to the session instead of [routing](#how-a-phrase-is-routed) it, unless a picker or card is waiting for a reply, which keeps priority (but not over type mode, whose dictation is never a reply). Exit words end the mode before anything is routed, then the [wake word](#wake-word), then switches to another mode; a recording heard in one mode and finished in another ("the mode changed, say it again") is never acted on. Pressing the Voice Command key while a turn is still being handled starts the next turn at once, and the turn's own listener leaves the session to it.
- **Idle end:** a session listen allows `VOXCMD_SESSION_NO_SPEECH_SECS` (10 s) of silence, whatever auto-stop's `no_speech_secs` is; hearing nothing ends the mode, with a notification, instead of cancelling silently, and the session goes on in the mode underneath if there is one (type mode's one recording has its own bounds). `session_begin` refuses to open a session when `voxcmd-autostop --check` fails.
- **Stricter auto-stop:** a session listens to the room between turns, so before a pause ends a turn it wants 0.4 s of speech (`VOXCMD_SESSION_MIN_SPEECH_SECS`) and a 1.5 s pause (`VOXCMD_SESSION_SILENCE_SECS`), whatever auto-stop's `min_speech_secs` and `silence_secs` are. A word shorter than that is still heard, only at the 10 s deadline. A picker or overlay asked during a turn listens as any [reply](#answering-by-voice) does.
- **Noise transcripts:** Whisper turns silence and noise into stock phrases. A turn whose whole transcript, normalized, is empty or one of `you`, `bye`, `the end`, `thank you`, `thank you for watching`, `thanks for watching` or `blank audio` (whisper.cpp's `[BLANK_AUDIO]`) heard nothing: it listens again without counting toward the unusable turns below, though it counts toward the turn and time caps. Outside a session these are routed like any command. The list is `session_noise_transcripts` in `voxcmd`.
- **Never a loop:** three unusable turns in a row end it, a turn that ran nothing (a picker cancelled or timed out) counting as unusable; so do `VOXCMD_SESSION_MAX_TURNS` turns (40) or `VOXCMD_SESSION_MAX_SECS` (300) open, whichever comes first; a listen that cannot start ends it; a listener that dies mid-session ends it. Each says why in a transient notification.
- **Settling:** after a turn voxcmd waits, for at most 2 s, until neither the click overlay (`qs-ipc call clickhints state`) nor a popup (`popup state`) is open or animating, then 0.3 s for the clicked app to draw, before listening again (`VOXCMD_UI_SETTLE_MAX_SECS`, `VOXCMD_APP_SETTLE_SECS`). A bar that does not answer counts as settled.
- `voxcmd end-session` ends it by hand, with every mode in it, and [Stop Voice](#stop-voice) ends it along with any picker or recording. A key or terminal command that tries to open a mode while a session is open only says so.

## Stop Voice

`SUPER + SHIFT + COMMA` (Leader, `SHIFT + COMMA`) runs `voxcmd stop`, the key for a voice session or overlay that will not end and a recording you no longer want. It does four things, each only when there is something to do:

- Ends the open [voice session](#voice-sessions) and every mode in it, reported by its usual "ended: stopped" toast. In [type mode](#type-mode) the recording is stopped and typed first, and the session ends once it is typed; nothing else below happens then. This comes first, so the session's listener cannot open the microphone again, even when it is mid-turn: its turn is discarded and the session is gone when it looks. An action that turn is already running still finishes, but nothing it opens (a picker or confirm card) listens for a reply.
- Ends a running [sequence](#sequences) before its next step starts, or while it waits for one, saying nothing.
- Cancels the open picker, confirm card or the numbered overlay, as Esc does.
- Cancels a voxtype recording under way, or being transcribed, whichever key started it: Voice Command, a reply recording or Speech to Text. Nothing said is routed or typed, and Speech to Text resumes its paused media as it does when any recording ends.

With no session, picker or recording open it does nothing and says nothing. `voxcmd end-session` still ends only the session.

## Debug log

`VOXCMD_DEBUG=1`, or creating `$XDG_RUNTIME_DIR/voxcmd/debug.log`, makes voxcmd and `voxcmd-confirm` append a timestamped trace there: each listen and the voxtype state it found, the watcher's state changes, auto-stop's verdict and `voxcmd-autostop`'s own summary of what it heard (see [Auto-stop](#auto-stop)), the transcript and where it went (only its length for a private mode, [type mode](#type-mode)), a confirm's question, reply and answer, a cancelled reply recording, and whether the action ran. Delete the file to turn it off again.
