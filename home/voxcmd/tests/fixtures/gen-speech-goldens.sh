#!/usr/bin/env bash
# Writes the golden files the Rust tests compare `voxcmd` against: what the bash helpers print for a corpus of
# phrases. Run it by hand when the corpus changes, never from a check, and commit the outputs; `cargo test` reads them and
# needs no bash. A golden changes only with the owner's sign-off (voxcmd-port.md, Working rules).
#
#   home/voxcmd/tests/fixtures/gen-speech-goldens.sh
#
# Writes next to this script:
#   speech-goldens.tsv   `voxcmd util speech|voice-env` against spoken-time.sh and voice-env.sh
#   text-goldens.tsv     the library functions with no CLI surface yet (normalize, replacements, positions, wake word,
#                        correction tails, monitor words) against the functions in spoken-position.sh, monitor-words.sh
#                        and .local/bin/voxcmd, lifted out of the script by name
#   monitor-places/      the layouts of tests/fixtures/monitors/ as monitor-places.jq reads them for each slot lookup
#
# Row format, tab separated, \ \n \t \r escaped: env, operation, input, exit status, stdout. env is space separated
# KEY=VALUE pairs set for that row (a value starting with @ is a path under this directory); `-` is none. Every row
# runs with TZ=America/New_York and LC_ALL=C, which the tests set too.
set -uo pipefail

fixtures_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH='' cd -- "$fixtures_dir/../.." && pwd)
share_dir=$package_dir/.local/share/voxcmd
phrases_file=$package_dir/tests/phrases.tsv

# Fixed so the output does not depend on the machine: the zone (daylight saving matters to the cases below), the locale
# (English day and month names, 24-hour times) and no inherited VOXCMD_* settings.
export TZ=America/New_York LC_ALL=C HOME=/nonexistent
while IFS= read -r variable; do unset "$variable"; done < <(compgen -e | grep -E '^(VOXCMD_|XDG_STATE_HOME$)' || true)

# Instants (TZ=America/New_York), each exercising a different rollover.
now_wednesday_afternoon=1792006200 # 2026-10-14 15:30 EDT
now_friday_night=1792207200        # 2026-10-16 23:20 EDT: "friday" has just rolled over, "tomorrow" is a Saturday
now_before_spring_gap=1772931600   # 2026-03-07 20:00 EST: tomorrow 02:30 does not exist
now_before_fall_fold=1793491200    # 2026-10-31 20:00 EDT: tomorrow 01:30 happens twice
now_year_end=1798779000            # 2026-12-31 23:50 EST: tomorrow is next year
nows=("$now_wednesday_afternoon" "$now_friday_night" "$now_before_spring_gap" "$now_before_fall_fold" "$now_year_end")

# shellcheck source=/dev/null
source "$share_dir/voice-env.sh"
# shellcheck source=/dev/null
source "$share_dir/monitor-words.sh" # and, through it, spoken-position.sh and spoken-time.sh

# The router functions come out of the script by name, so they are exactly what runs. The script itself cannot be
# sourced: it routes a phrase when it loads.
# shellcheck disable=SC2034 # read by apply_replacements, lifted below
config_dir=$fixtures_dir/speech
lift_function() { awk -v name="$1" '$0 ~ "^" name "\\(\\) \\{" { printing = 1 } printing { print } printing && /^}/ { exit }' "$package_dir/.local/bin/voxcmd"; }
for function_name in normalize apply_replacements name_workspace_ordinals init_wake_regex split_leading_wake \
  split_trailing_wake correction_tails heard_wake_word; do
  source_text=$(lift_function "$function_name")
  [ -n "$source_text" ] || {
    echo "gen-speech-goldens: $function_name not found in voxcmd" >&2
    exit 1
  }
  eval "$source_text"
done
# The bash split_duration the goldens were made from, kept here: timers.toml's copy now asks the Rust splitter, which a
# golden must not be generated from. It needs only parse_duration.
split_duration() {
  local -a words
  read -ra words <<<"$1"
  local count seconds
  for ((count = ${#words[@]}; count > 0; count--)); do
    seconds=$(parse_duration "${words[*]:0:count}") && break
  done
  [ "$count" -gt 0 ] && [ "$seconds" -gt 0 ] || return 1
  echo "$seconds ${words[*]:count}"
}
# The settings those functions read, lifted the same way.
lifted_settings=$(grep -E '^(correction_phrases|leading_filler|wake_word|wake_aliases|wake_regex|wake_rest|wake_before)=' "$package_dir/.local/bin/voxcmd")
# wake_rest and wake_before are set by the lifted split functions and read by the wrappers below.
wake_rest="" wake_before=""
reset_wake_settings() { eval "$lifted_settings"; }

escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//$'\n'/\\n}
  text=${text//$'\t'/\\t}
  text=${text//$'\r'/\\r}
  printf '%s' "$text"
}

# apply_row_env <env>: sets the row's variables in the current (sub)shell.
apply_row_env() {
  local pair value
  [ "$1" != - ] || return 0
  for pair in $1; do
    value=${pair#*=}
    [[ "$value" != @* ]] || value=$fixtures_dir/${value#@}
    export "${pair%%=*}=$value"
  done
}

# row <file> <env> <operation> <input> <command...>: runs the command with the row's env and appends the row.
row() {
  local file=$1 env=$2 operation=$3 input=$4 output status
  shift 4
  output=$( (
    apply_row_env "$env"
    reset_wake_settings
    "$@"
  ) 2>/dev/null)
  status=$?
  printf '%s\t%s\t%s\t%s\t%s\n' "$env" "$operation" "$(escape "$input")" "$status" "$(escape "$output")" >>"$file"
}

speech_file=$fixtures_dir/speech-goldens.tsv.new
text_file=$fixtures_dir/text-goldens.tsv.new
: >"$speech_file"
: >"$text_file"

# ---- time-dependent speech operations -------------------------------------------------------------------------------

time_phrases=(
  "3 pm" "3 p m" "3 30 p m" "3 30" "15 30" "1530" "330" "330 pm" "3pm" "330pm" "3am" "three thirty pm" "three thirty"
  "three pm" "noon" "midday" "midnight" "12 am" "12 pm" "12" "0" "0 30" "24" "13 pm" "0 pm" "1" "2 30" "11 59 pm" "11 59"
  "12 30" "12 30 am" "9 am tomorrow" "tomorrow at 7" "tomorrow at 7 am" "tomorrow morning at 9" "tonight at 8" "tonight"
  "this evening at 6" "6 in the evening" "in the afternoon at 3" "friday at 9 am" "friday at 11 45 pm" "friday at 11 15 pm"
  "friday 9" "next friday at 3 pm" "next friday" "on friday at 5" "on monday" "next wednesday 3 pm" "wednesday at 9 am"
  "wednesday at 11 am" "thursday at 9 am" "saturday at 10" "tomorrow friday at 3" "today at 9 am" "today at 5 pm"
  "today at 3 45 pm" "seven oh five" "seven oh five pm" "seven o clock" "7 oclock" "eight o clock am"
  "quarter past three" "a quarter past" "half past three" "3 60" "25" "99" "3 30 45" "3 pm pm" "9 am next in tokyo"
  "9 am in tokyo" "banana" "noon tomorrow" "midnight tomorrow" "2 30 am tomorrow" "1 30 am tomorrow" "2 30 am today"
  "2 30 tomorrow" "1 30 tomorrow" "sunday at noon" "twenty one hundred" "twenty" "twenty five" "one fifteen"
  "one fifteen pm" "two thirty five" "ten fifty nine pm" "eleven oh one" "half an hour" "a" "an" "half" "a m" "p" "am"
  "7 5" "7 05" "07 05" "007" "0730" "2400" "2359" "2360" "9 30 am next friday" "next friday morning" "friday evening"
  "monday noon" "tuesday midnight" "next tuesday" "next next friday" "on next friday" "at 3" "at" "the 3" "this 3 pm"
  "3 o clock" "three o clock pm" "3 5 minutes" "3 5 s" "3 h" "twelve noon" "12 noon" "12 midnight" "tomorrow" "friday"
  "9 am friday" "9 pm friday" "9 friday" "tomorrow 9" "tomorrow 12" "today 12" "today 12 am" "today 12 pm" "a quarter"
  "" " " "3  pm" " 3 pm"
)
day_phrases=(
  today tomorrow monday tuesday wednesday thursday friday saturday sunday "next monday" "next tuesday" "next wednesday"
  "next thursday" "next friday" "next saturday" "next sunday" "next today" "next tomorrow" "next next friday" next "next "
  "tomorrow friday" "friday at 9" Friday "Next Friday" " friday" "friday " "next  friday" banana "" yesterday "day after tomorrow"
)
for now in "${nows[@]}"; do
  for phrase in "${time_phrases[@]}"; do
    row "$speech_file" "VOXCMD_NOW=$now" parse-time "$phrase" parse_clock "$phrase"
    row "$speech_file" "VOXCMD_NOW=$now" parse-time-today "$phrase" parse_clock "$phrase" today
  done
  for phrase in "${day_phrases[@]}"; do
    row "$speech_file" "VOXCMD_NOW=$now" parse-day "$phrase" parse_day "$phrase"
  done
done

# Whole-day-apart instants around each reference "now", for the formatters.
due_offsets=(0 60 3600 7200 16200 28800 43200 86400 90000 172800 345600 518400 604800 608400 691200 1209600 2592000 31536000 -60 -3600 -86400 -604800)
for now in "$now_wednesday_afternoon" "$now_friday_night" "$now_year_end" "$now_before_fall_fold"; do
  for state in state-12h state-24h state-locale -; do
    state_env=-
    [ "$state" = - ] || state_env=XDG_STATE_HOME=@speech/$state
    for offset in "${due_offsets[@]}"; do
      due=$((now + offset))
      env="VOXCMD_NOW=$now${state_env:+ $state_env}"
      [ "$state_env" != - ] || env=VOXCMD_NOW=$now
      row "$speech_file" "$env" format-due "$due" format_due "$due"
      row "$speech_file" "$env" format-at "$due" format_at "$due"
    done
  done
done
# Clock changes, on both sides of the day line.
for pair in "$now_before_spring_gap 1772951400" "$now_before_spring_gap 1772957400" "$now_before_fall_fold 1793507400" "$now_before_fall_fold 1793511000" "$now_before_fall_fold 1793514600"; do
  read -r now due <<<"$pair"
  row "$speech_file" "VOXCMD_NOW=$now XDG_STATE_HOME=@speech/state-12h" format-due "$due" format_due "$due"
  row "$speech_file" "VOXCMD_NOW=$now XDG_STATE_HOME=@speech/state-24h" format-at "$due" format_at "$due"
done

# ---- amounts, not time-dependent -----------------------------------------------------------------------------------

lengths=(0 1 2 59 60 61 119 120 121 3599 3600 3601 3660 3661 7199 7200 7261 86399 86400 90061 360000 -1 -90 -3661)
for length in "${lengths[@]}"; do
  row "$speech_file" - format-length "$length" format_length "$length"
done

duration_phrases=(
  "5 minutes" "5 min" "5 mins" "5 m" "90 seconds" "90 s" "1 second" "1 hour" "2 hours" "2 hrs" "2 h" "an hour" "a minute"
  "a second" "a hour" "an minute" "a quarter of an hour" "a quarter hour" "a quarter of a minute" "a quarter an hour"
  "half an hour" "half a minute" "half hour" "a half hour" "half" "a quarter" "a quarter of" "half a" "half an" "an hour and a half"
  "an hour and half" "1 hour and a half" "two hours and a half" "two and a half minutes" "two and a half hours"
  "2 and a half minutes" "1 5 hours" "1 5 minutes" "0 5 hours" "1 05 hours" "1 123 hours" "1 1234 hours" "1 hour 30"
  "1 hour 30 minutes" "2 minutes 15" "1 hour 15 30" "1 hour and 30 minutes" "an hour and 30 minutes"
  "1 hour 30 minutes 10 seconds" "3 hours 2 minutes" "twenty five minutes" "twenty minutes" "twenty one minutes"
  "twenty five" "fifteen seconds" "zero seconds" "0 seconds" "one hundred minutes" "ninety seconds" "thirty seconds"
  "forty five seconds" "a day" "5 days" "5" "five" "minutes" "5 minutes and" "and 5 minutes" "5 minutes and 3"
  "5 minutes and 3 seconds" "5 minutes and a half" "5 minutes and a half minute" "5 minutes and a" "banana" ""
  "1 hour a half" "an hour and a half and a half" "half an hour and a half" "10 minutes then" "10 minutes 5"
  "10 seconds 5" "5 5 5 minutes" "twenty five and a half minutes" "2 1 hours" "2 12 hours" "1000 minutes" "99999 hours"
  "1 and a half hours" "1 and a half" "1 hour and a half minutes" "an hour and a half hour" "a and a half hours"
  "three hundred seconds" "thirty five seconds" "thirty zero seconds" "twenty zero minutes" "nineteen minutes" "ten ten minutes"
  "an and a half hours" "half an hour 30" "an hour 30 minutes 15" "1 hour and" "1 hour and a" "1 hour and a half 5"
  "one minute thirty" "one minute thirty seconds" "one hour thirty" "1 minute 30 seconds and a half"
  "  5 minutes" "5 minutes  " "5  minutes"
)
for phrase in "${duration_phrases[@]}"; do
  row "$speech_file" - parse-duration "$phrase" parse_duration "$phrase"
done

# Leading durations with labels, filler, nothing leading, zero, and prefixes that parse short of the longest run.
split_phrases=(
  "5 minutes for the pasta" "five minutes pasta" "twenty five minutes to call the bank" "half an hour for the oven"
  "an hour and a half for the roast" "an hour and a half" "1 hour 30" "1 hour 30 minutes tea" "2 minutes 15 tea"
  "5 minutes and tea" "5 minutes and a half tea" "90 seconds" "0 seconds tea" "zero minutes" "pasta for 5 minutes" "banana"
  "90" "" "  5   minutes   tea  " "a quarter of an hour for the eggs" "10 minutes then 5 minutes" "1 hour and a half minutes"
)
for phrase in "${split_phrases[@]}"; do
  row "$speech_file" - split-duration "$phrase" split_duration "$phrase"
done

# ---- phrases.tsv: every phrase that mentions a number, time, duration, day, position or monitor word -----------------

interesting='[0-9]|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|teen|twenty|thirty|forty|fifty|ninety|first|second|third|th |noon|midnight|am |pm |a m|p m|hour|minute|today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next|left|right|middle|center|centre|top|bottom|laptop|monitor|screen|display|workspace|desktop'
phrases=()
while IFS= read -r phrase; do
  [ -n "$phrase" ] && phrases+=("$phrase")
done < <(awk -F'\t' 'NR > 1 { print $1 }' "$phrases_file" | sort -u)

windows=()
for phrase in "${phrases[@]}"; do
  normalized=$(normalize "$phrase")
  grep -Eq "$interesting" <<<"$normalized " || continue
  read -ra words <<<"$normalized"
  # Every suffix of up to six words: the argument sits at the end of a phrase, after the verb.
  for ((start = 0; start < ${#words[@]}; start++)); do
    ((${#words[@]} - start <= 6)) || continue
    windows+=("${words[*]:start}")
  done
done
while IFS= read -r window; do
  row "$speech_file" "VOXCMD_NOW=$now_wednesday_afternoon" parse-time "$window" parse_clock "$window"
  row "$speech_file" "VOXCMD_NOW=$now_wednesday_afternoon" parse-time-today "$window" parse_clock "$window" today
  row "$speech_file" "VOXCMD_NOW=$now_wednesday_afternoon" parse-day "$window" parse_day "$window"
  row "$speech_file" - parse-duration "$window" parse_duration "$window"
  row "$text_file" - position "$window" spoken_position "$window"
  row "$text_file" - ordinal "$window" spoken_ordinal "$window"
  row "$text_file" - cardinal "$window" spoken_cardinal "$window"
  row "$text_file" - words-known "$window" monitor_words_known "$window"
done < <(printf '%s\n' "${windows[@]}" | sort -u)

# ---- voice.env ----------------------------------------------------------------------------------------------------

for key in VOXCMD_DUCK_MEDIA_VOLUME VOXCMD_WAKE_SENSITIVITY VOXCMD_WAKE_PAUSE_FOR_MEDIA VOXCMD_WAKE_PAUSE_FOR_MIC \
  VOXCMD_FRACTION VOXCMD_TRAILING_DOT VOXCMD_WORD VOXCMD_LATE VOXCMD_SPACED VOXCMD_INDENTED VOXCMD_MISSING; do
  for file in voice-env-main voice-env-late-bad voice-env-absent; do
    row "$speech_file" "VOXCMD_VOICE_ENV_FILE=@speech/$file" voice-env "$key" voice_env_value "$key"
  done
  row "$speech_file" "VOXCMD_VOICE_ENV_FILE=@speech/voice-env-main $key=77" voice-env "$key" voice_env_value "$key"
  row "$speech_file" "VOXCMD_VOICE_ENV_FILE=@speech/voice-env-main $key=500" voice-env "$key" voice_env_value "$key"
done
row "$speech_file" "XDG_STATE_HOME=@speech/state-12h" voice-env VOXCMD_DUCK_MEDIA_VOLUME voice_env_value VOXCMD_DUCK_MEDIA_VOLUME

# ---- positions, normalizing and replacements -----------------------------------------------------------------------

position_phrases=(
  two 7 "twenty five" second twelfth thirtieth "twenty first" "ninety ninth" 2nd 13th 21st 111th 101st 2th 11st 12nd 21th 0th
  "twenty ten" "first second" seconds 0 zero 007 "0 0" "" " " first " second" "second " "twenty  first" "twenty five six" ten eleven
  nineteen twenty "twenty zero" "thirty one" "thirty first" "thirty-first" 1st 3rd 4th 22nd 23rd 12th 11th 13th 1th 100th 1000th
  "forty two" "forty second" "twenty twentieth" "ninety nine" "ninety ninth" "one hundred" 99999999 "five five" "twenty one"
)
for phrase in "${position_phrases[@]}"; do
  for operation in position ordinal cardinal; do
    row "$text_file" - "$operation" "$phrase" "spoken_$operation" "$phrase"
  done
done

raw_transcripts=(
  "Open Firefox." "Open Firefox, please!" "What's the time?" "3:30 p.m." "  spaced   out  " "UPPER lower MiXeD" "it's O'Brien's" "" " " "!!!"
  "tab	separated" "two
lines" "trailing newline
" "newline
 and space" "a - b -- c" "pre-size to 1200 by 800" "Re-size the window" "naive cafe" "caf$(printf '\303\251') time" "100%" "a_b_c"
  "move firefox to the second workspace" "go to the twenty first desktop" "second workspace" "the second workspace" "workspace 2"
  "two workspaces" "the twenty first workspace please" "send it to the first desktop" "second second workspace"
  "volume up" "volume   up" "volume up volume up" "louder" "ok google open firefox" "um" "um um" "cortana's here" "cortanas here"
  "Hey Cortana, open Firefox" "cortana" "kortana open kitty" "open firefox cortana" "no wait open kitty" "exit exit overview"
  "um open firefox" "um uh open firefox" "hmm no open kitty" "open firefox, I mean open kitty" "okay so scratch that open kitty"
  "no" "sorry" "actually" "wait" "open firefox no" "let me rephrase open kitty" "no wait no wait open kitty" "so so open kitty"
  "play play pause" "open open open kitty" "open firefox no wait" "wait no"
)
while IFS= read -r phrase; do raw_transcripts+=("$phrase"); done < <(printf '%s\n' "${phrases[@]}")
# Multi-value results, flattened to one string.
correction_tails_joined() { correction_tails "$1" | paste -sd'|'; }
leading_wake() { split_leading_wake "$1" && printf '%s' "$wake_rest"; }
trailing_wake() { split_trailing_wake "$1" && printf '%s|%s' "$wake_before" "$wake_rest"; }
heard_wake() { heard_wake_word "$1" && printf '%s' "$wake_rest"; }
wake_settings=(- "VOXCMD_WAKE_ALIASES=" "VOXCMD_WAKE_ALIASES=jarvis,okay" "VOXCMD_WAKE_ALIASES=!!!" "VOXCMD_WAKE_ALIASES=hey")

for transcript in "${raw_transcripts[@]}"; do
  normalized=$(normalize "$transcript")
  row "$text_file" - normalize "$transcript" normalize "$transcript"
  row "$text_file" - apply-replacements "$normalized" apply_replacements "$normalized"
  row "$text_file" - workspace-ordinals "$normalized" name_workspace_ordinals "$normalized"
  row "$text_file" - correction-tails "$normalized" correction_tails_joined "$normalized"
  for setting in "${wake_settings[@]}"; do
    row "$text_file" "$setting" leading-wake "$normalized" leading_wake "$normalized"
    row "$text_file" "$setting" trailing-wake "$transcript" trailing_wake "$transcript"
    row "$text_file" "$setting" heard-wake "$transcript" heard_wake "$transcript"
  done
done

# ---- monitor words -------------------------------------------------------------------------------------------------

monitor_words=(
  "left" "right" "center" "centre" "middle" "top" "bottom" "top left" "top right" "bottom left" "bottom right"
  "the left monitor" "the center monitor" "the centre screen" "the middle display" "monitor left" "screen right"
  "laptop" "the laptop" "the laptop monitor" "built in" "builtin" "internal" "the internal monitor" "built in display"
  "monitor two" "two" "2" "the second monitor" "second" "the 2nd display" "monitor number four" "number four" "fourth"
  "4th" "tenth" "10th" "nine" "monitor nine" "one" "first" "the first monitor" "three" "the third monitor" "zero" "monitor zero"
  "system" "system monitor" "left system" "monitor monitor" "screen screen two" "the the left" "left left" "left right"
  "top middle" "number" "number two" "monitor number" "" "the" "the monitor" "monitor" "twenty five" "twenty" "five twenty"
)
layouts=(owner owner_real laptop side_by_side stacked grid five_in_a_row tall_beside)
mkdir -p "$fixtures_dir/monitor-places"
rm -f "$fixtures_dir"/monitor-places/*.json
slot_lookups=('' 'HDMI-A-1 - eDP-1 DP-8 DP-13' 'HDMI-A-1 - eDP-1' 'eDP-1 DP-8 HDMI-A-1 DP-13')
for layout in "${layouts[@]}"; do
  layout_file=$package_dir/tests/fixtures/monitors/$layout.json
  id_order=$(jq -r '[.[] | select(.disabled | not)] | sort_by(.id) | map(.name) | join(" ")' "$layout_file")
  for slots in "${slot_lookups[@]}" "$id_order"; do
    # The file is named by the lookup, spaces as underscores, so a row says which lookup it ran with.
    places_name="$layout.${slots// /_}.json"
    [ "$slots" != "" ] || places_name="$layout.none.json"
    jq -c --arg slots "$slots" -f "$share_dir/monitor-places.jq" "$layout_file" >"$fixtures_dir/monitor-places/$places_name"
    for words in "${monitor_words[@]}"; do
      row "$text_file" "PLACES=@monitor-places/$places_name" monitor-named "$words" monitor_named "$words" "$(cat "$fixtures_dir/monitor-places/$places_name")"
    done
  done
done

# Written whole only at the end, so a failed run leaves the committed files alone.
awk '!seen[$0]++' "$speech_file" >"${speech_file%.new}"
awk '!seen[$0]++' "$text_file" >"${text_file%.new}"
rm -f "$speech_file" "$text_file"
echo "wrote $(wc -l <"${speech_file%.new}") speech rows and $(wc -l <"${text_file%.new}") text rows"
