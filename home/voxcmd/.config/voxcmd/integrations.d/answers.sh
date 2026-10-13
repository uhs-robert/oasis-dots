# shellcheck shell=bash disable=SC2034,SC2016
# Quick answers: spoken math through qalc, the time and date here and in other time zones; weather questions open
# the bar's weather popup.
# Format: ~/.config/voxcmd/README.md

name="Answers"
confirm=0

# voxcmd sets voxcmd_share_dir before loading integrations.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-time.sh disable=SC2154
source "$voxcmd_share_dir/spoken-time.sh"

# Spoken lead-ins and tails that carry no meaning, allowed around every question.
answers_lead='((hey|hi|ok|okay|um|umm|uh|er|erm|hmm|so|well|please|quick question) )*((can|could|would) you (please )?)?((tell|show) me )?'
answers_tail='( (please|thanks|thank you))*'
answers_whats='(what is|whats|what s)'
answers_today='( (today|right now|now|currently|outside|out there))*'
# What a calculation has to start with when it is asked with "what's", so "what's up" stays out of qalc.
# A clock time the way a conversion says it, kept strict so math keeps its numbers: an hour with am, pm or o'clock
# ("1 pm", "three thirty pm", "1pm"), noon or midnight, or hours and minutes in digits ("15 30"), with a day around it.
answers_clock_hour='([0-9]{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)'
answers_clock="(noon|midday|midnight|${answers_clock_hour}( (oh |o )?[a-z]+( [a-z]+)?| [0-9]{2})?( ?(am|pm)| a m| p m| oclock| o clock)|[0-9]{1,2} [0-5][0-9])"
answers_when="((today|tomorrow|tonight) (at )?)?${answers_clock}( (today|tomorrow|tonight|this (morning|afternoon|evening)))?"
answers_zone_words='[a-z]+( [a-z]+){0,3}'
answers_math_start='(the )?((square|cube) root of |(minus|negative) )?([0-9].*|(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|a hundred|a thousand|half|a half|a third|a quarter|pi)( .*)?)'

verbs=(
  "time          ${answers_lead}(${answers_whats} the( current)? time|the time|what time is it|do you (have|know) the time)${answers_today}${answers_tail}"
  "date          ${answers_lead}((${answers_whats} )?(the|todays|today s)( current)? date|what (day|date|day of the week|month|year) is (it|today)|${answers_whats} today|which day is (it|today))${answers_today}${answers_tail}"
  "weather       ${answers_lead}((is|will|does) it (going to |gonna )?(rain|snow|be (rainy|wet|snowy|stormy))|(do|should) i (need|take|bring) an umbrella|(any|chance of) (rain|snow))( (today|tonight|later|this (morning|afternoon|evening)))*${answers_tail}"
  "weather       ${answers_lead}((${answers_whats}|how is|hows|how s) (the )?(weather|forecast|temperature)( (like|report))?|weather( (report|forecast))?|how (hot|cold|warm) is it)${answers_today}${answers_tail}"
  "zone_now      ${answers_lead}(what time is it|${answers_whats} the( current)? time|(the )?time)( right)?( now)? (in|over in) {target}${answers_tail}"
  "zone_offset   ${answers_lead}how (far|many hours) (ahead|behind)( of (us|me|here))? is {target}${answers_tail}"
  "zone_offset   ${answers_lead}(${answers_whats} )?the time difference (with|to|for|from|between (us|me|here) and) {target}${answers_tail}"
  # Before calculate: "what is 1 pm ..." and "convert 3 30 pm ..." read as math too.
  "zone_convert  ${answers_lead}(${answers_whats}|what time is|convert) ${answers_when}( ${answers_zone_words})? (in|to) ${answers_zone_words}${answers_tail}"
  "calculate     ${answers_lead}(${answers_whats}|how much is|what does) ${answers_math_start}"
  "calculate     ${answers_lead}how many [a-z]+( [a-z]+)? (are )?(in|is|make) (a|an|one|[0-9]).*"
  "calculate     ${answers_lead}(calculate|compute|evaluate|work out|solve|convert) .+"
)

# Math reads $raw_transcript rather than a {target}: normalizing drops "%", "×", "/" and decimal points, so
# "2.5%" would reach qalc as "2 5".
examples=(
  "what time is it"
  "what's the date"
  "what time is it in <city>"
  "what is <time> <zone> in <zone>"
  "how far ahead is <city>"
  "what's the weather"
  "will it rain today"
  "what's <number> percent of <number>"
  "convert <amount> <unit> to <unit>"
)

declare -A actions=(
  [time]='answer_time'
  [date]='date "+%A, %B %-d, %Y"'
  [weather]='open_weather_popup'
  [zone_now]='answer_zone_now "$target"'
  [zone_offset]='answer_zone_offset "$target"'
  [zone_convert]='answer_zone_conversion "$raw_transcript"'
  [calculate]='answer_calculation "$raw_transcript"'
)
# The popup is the answer; a success toast would cover it.
silent_actions=(weather)
# A sequence's next step waits for the popup to be drawn.
declare -A step_waits=(
  [weather]='popup_is_open weather'
)

# Follows the bar's Settings > Clock time format, where "locale" means the locale's own 12 or 24 hour choice.
answers_time_format() {
  local clock_file="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/clock.json" choice
  choice=$(jq -r '.time_format // "locale"' "$clock_file" 2>/dev/null) || choice="locale"
  if [ "$choice" = locale ]; then
    [[ "$(locale t_fmt 2>/dev/null)" == *%[pPr]* ]] && choice="12h" || choice="24h"
  fi
  [ "$choice" = 12h ] && echo '%-I:%M %p' || echo '%H:%M'
}

answer_time() {
  date "+$(answers_time_format)"
}

# ---- Time zones ------------------------------------------------------------------------------------------------
# Every time is computed by GNU date under TZ, so daylight saving comes from tzdata. A zone is passed around as
# "zone<TAB>label": the label is how an answer names it, "here" for the local zone, "in Tokyo" for a city and the
# bare name for a regional zone ("Eastern").

# Spoken zone names that are no zoneinfo city: "zone|label". An unqualified "Central" is US Central.
# Global (-g) for the same reason as spoken-time.sh's number words.
declare -gA answers_zone_aliases=(
  [pacific]='America/Los_Angeles|Pacific' [pt]='America/Los_Angeles|Pacific'
  [pst]='America/Los_Angeles|Pacific' [pdt]='America/Los_Angeles|Pacific'
  [mountain]='America/Denver|Mountain' [mt]='America/Denver|Mountain'
  [mst]='America/Denver|Mountain' [mdt]='America/Denver|Mountain'
  [arizona]='America/Phoenix|Arizona'
  [central]='America/Chicago|Central' [ct]='America/Chicago|Central'
  [cst]='America/Chicago|Central' [cdt]='America/Chicago|Central'
  [eastern]='America/New_York|Eastern' [et]='America/New_York|Eastern'
  [est]='America/New_York|Eastern' [edt]='America/New_York|Eastern'
  [alaska]='America/Anchorage|Alaska' [akst]='America/Anchorage|Alaska' [akdt]='America/Anchorage|Alaska'
  [hawaii]='Pacific/Honolulu|Hawaii' [hst]='Pacific/Honolulu|Hawaii'
  [utc]='UTC|UTC' [zulu]='UTC|UTC' [universal]='UTC|UTC' [gmt]='UTC|GMT' [greenwich]='UTC|GMT'
  [uk]='Europe/London|UK' [british]='Europe/London|UK' [bst]='Europe/London|UK'
  [cet]='Europe/Paris|CET' [cest]='Europe/Paris|CET' [central european]='Europe/Paris|CET'
  [eet]='Europe/Athens|EET' [eest]='Europe/Athens|EET' [eastern european]='Europe/Athens|EET'
  [wet]='Europe/Lisbon|WET' [western european]='Europe/Lisbon|WET'
  [india]='Asia/Kolkata|India' [indian]='Asia/Kolkata|India' [ist]='Asia/Kolkata|India'
  [japan]='Asia/Tokyo|Japan' [jst]='Asia/Tokyo|Japan'
  [china]='Asia/Shanghai|China'
  [aest]='Australia/Sydney|Australian Eastern' [aedt]='Australia/Sydney|Australian Eastern'
  [australian eastern]='Australia/Sydney|Australian Eastern'
)

answers_local_zone() {
  local zone
  zone=$(timedatectl show -p Timezone --value 2>/dev/null) || zone=""
  [ -n "$zone" ] || zone=$(readlink -f /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p')
  # An empty TZ is UTC to glibc, so an unknown local zone reads the file itself.
  echo "${zone:-:/etc/localtime}"
}

# "new york" finds America/New_York: the region folders first, then the old names (Japan, Egypt), never the posix/
# and right/ copies. Normalizing drops hyphens from speech, so a space matches either "_" or "-" ("port au prince"
# finds America/Port-au-Prince).
answers_zoneinfo_city() {
  local file_name="${1// /[_-]}" root=/usr/share/zoneinfo path
  path=$(find "$root"/{Africa,America,Antarctica,Arctic,Asia,Atlantic,Australia,Europe,Indian,Pacific} \
    -iname "$file_name" \( -type f -o -type l \) 2>/dev/null | sort | head -n 1)
  [ -n "$path" ] || path=$(find "$root" -mindepth 1 \( -name posix -o -name right \) -prune -o \
    -iname "$file_name" \( -type f -o -type l \) -print 2>/dev/null | sort | head -n 1)
  [ -n "$path" ] && echo "${path#"$root"/}"
}

# The clock popup's extra zones (Timezones.qml), matched by city or by the whole name ("america denver").
answers_configured_zone() {
  local spoken="$1" zone city
  while IFS= read -r zone; do
    city="${zone##*/}"
    city="${city//_/ }"
    if [ "${city,,}" = "$spoken" ] || [ "$(tr '/_' '  ' <<<"${zone,,}")" = "$spoken" ]; then
      echo "$zone"
      return
    fi
  done < <(jq -r '.[]? | strings' "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/timezones.json" 2>/dev/null)
  return 1
}

# The spoken name without the words around it, as an answer quotes it: "the pacific time" is "pacific".
answers_zone_name() {
  sed -E 's/^(the|in|at) //; s/( (please|thanks|thank you|right now|now|today))+$//
    s/ ((standard|daylight|daylight saving|summer) )?time$//' <<<"$1" |
    sed -E '/^([a-z] )+[a-z]$/ s/ //g'
}

# Prints "zone<TAB>label" for a spoken zone; fails for a name that is no zone.
answers_resolve_zone() {
  local spoken alias zone city
  spoken=$(answers_zone_name "$1")
  case "$spoken" in
  "" | local | my | "my local" | here | home | me | us) printf '%s\there\n' "$(answers_local_zone)" && return ;;
  esac
  alias="${answers_zone_aliases[$spoken]-}"
  if [ -n "$alias" ]; then
    printf '%s\t%s\n' "${alias%%|*}" "${alias#*|}"
    return
  fi
  zone=$(answers_configured_zone "$spoken") || zone=$(answers_zoneinfo_city "$spoken") || return 1
  city="${zone##*/}"
  printf '%s\tin %s\n' "$zone" "${city//_/ }"
}

answers_unknown_zone() {
  local name
  name=$(answers_zone_name "$1" | sed -E 's/\b(.)/\u\1/g')
  echo "No time zone called ${name:-that}"
  return 1
}

# The UTC offset of a zone at an epoch, in minutes.
answers_offset_minutes() {
  local offset
  offset=$(TZ="$1" date -d "@$2" +%z)
  echo $((${offset:0:1}1 * (10#${offset:1:2} * 60 + 10#${offset:3:2})))
}

# How many minutes zone $1 is ahead of zone $2 at an epoch, negative when behind.
answers_minutes_ahead() {
  echo $(($(answers_offset_minutes "$1" "$3") - $(answers_offset_minutes "$2" "$3")))
}

# "3 hours behind", "5 hours 30 minutes ahead", "the same time", for a difference in minutes.
answers_describe_offset() {
  local minutes="${1#-}" direction=ahead parts=()
  [ "$1" -ge 0 ] || direction=behind
  [ "$minutes" != 0 ] || {
    echo "the same time"
    return
  }
  [ $((minutes / 60)) = 0 ] || parts+=("$((minutes / 60)) hour$([ $((minutes / 60)) = 1 ] || echo s)")
  [ $((minutes % 60)) = 0 ] || parts+=("$((minutes % 60)) minutes")
  echo "${parts[*]} $direction"
}

# "today", "tomorrow", "yesterday" or the weekday an epoch falls on in a zone, against the date here: answers
# speak from the local date, so 12pm Tuesday in Tokyo is "tomorrow" while it is still Monday here.
answers_zone_day() {
  local zone="$1" epoch="$2" reference="$3" day today
  day=$(TZ="$zone" date -d "@$epoch" +%F)
  today=$(TZ="$reference" date +%F)
  case $((($(date -u -d "$day" +%s) - $(date -u -d "$today" +%s)) / 86400)) in
  0) echo today ;;
  1) echo tomorrow ;;
  -1) echo yesterday ;;
  *) TZ="$zone" date -d "@$epoch" +%A ;;
  esac
}

# "9:00am tomorrow in Tokyo", "8:00pm here", "1:00pm Eastern today": the day only when $4 names one.
answers_zone_moment() {
  local zone="$1" label="$2" epoch="$3" day="${4-}" time
  time=$(TZ="$zone" date -d "@$epoch" "+$(clock_time_format)")
  if [ "$label" = here ] || [[ "$label" == in\ * ]]; then
    echo "$time${day:+ $day} $label"
  else
    echo "$time $label${day:+ $day}"
  fi
}

# wl-copy keeps serving the clipboard in the background; with voxcmd's pipe left open the action would never end.
answers_copy_and_say() {
  wl-copy -- "$1" >/dev/null 2>&1 </dev/null || true
  echo "$1"
}

# "4:12am tomorrow in Tokyo (13 hours ahead)".
answer_zone_now() {
  local resolved zone label here now day
  resolved=$(answers_resolve_zone "$1") || {
    answers_unknown_zone "$1"
    return
  }
  IFS=$'\t' read -r zone label <<<"$resolved"
  here=$(answers_local_zone) now=$(date +%s)
  day=$(answers_zone_day "$zone" "$now" "$here")
  [ "$day" != today ] || day=""
  answers_copy_and_say "$(answers_zone_moment "$zone" "$label" "$now" "$day") ($(answers_describe_offset "$(answers_minutes_ahead "$zone" "$here" "$now")"))"
}

# "Tokyo is 13 hours ahead, 4:12am tomorrow there".
answer_zone_offset() {
  local resolved zone label here now day name offset
  resolved=$(answers_resolve_zone "$1") || {
    answers_unknown_zone "$1"
    return
  }
  IFS=$'\t' read -r zone label <<<"$resolved"
  here=$(answers_local_zone) now=$(date +%s)
  day=$(answers_zone_day "$zone" "$now" "$here")
  [ "$day" != today ] || day=""
  name="${label#in }"
  [ "$name" != here ] || name="Local time"
  offset=$(answers_describe_offset "$(answers_minutes_ahead "$zone" "$here" "$now")")
  [ "$offset" != "the same time" ] || offset="on the same time"
  answers_copy_and_say "$name is $offset, $(TZ="$zone" date -d "@$now" "+$(clock_time_format)")${day:+ $day} there"
}

# "what is 1 pm eastern in pacific", "convert 3 30 pm pacific to london time", "what time is 9 am tomorrow in tokyo".
# The pattern only routes; the phrase is parsed again here from the normalized transcript, since a verb can capture
# one target and this needs three parts. "what time is <time> in <zone>" asks about a time there, so with no zone
# of its own the time is read in that zone and answered here; the other forms read it here and answer there.
answer_zone_conversion() {
  local text asked from_words to_words
  text=$(apply_replacements "$(normalize "$1")")
  text=$(sed -E -e "s/^${answers_lead}//" -e 's/( (please|thanks|thank you))*$//' <<<"$text")
  [[ "$text" =~ ^(whats|what s|what is|what time is|convert)\ (.+)\ (in|to)\ (.+)$ ]] || {
    echo "no time in \"$1\""
    return 1
  }
  asked="${BASH_REMATCH[1]}" from_words="${BASH_REMATCH[2]}" to_words="${BASH_REMATCH[4]}"
  # The longest run of leading words that reads as a clock time; what follows names the zone it is in.
  local -a words
  read -ra words <<<"$from_words"
  local count clock_phrase="" source_words=""
  for ((count = ${#words[@]}; count > 0; count--)); do
    parse_clock "${words[*]:0:count}" today >/dev/null && {
      clock_phrase="${words[*]:0:count}" source_words="${words[*]:count}"
      break
    }
  done
  if [ -z "$clock_phrase" ]; then
    echo "no time in \"$1\""
    return 1
  fi
  local source target
  if [ -z "$source_words" ] && [ "$asked" = "what time is" ]; then
    source=$(answers_resolve_zone "$to_words") || {
      answers_unknown_zone "$to_words"
      return
    }
    target=$(answers_resolve_zone "")
  else
    source=$(answers_resolve_zone "$source_words") || {
      answers_unknown_zone "$source_words"
      return
    }
    target=$(answers_resolve_zone "$to_words") || {
      answers_unknown_zone "$to_words"
      return
    }
  fi
  local source_zone source_label target_zone target_label epoch source_day target_day
  IFS=$'\t' read -r source_zone source_label <<<"$source"
  IFS=$'\t' read -r target_zone target_label <<<"$target"
  # "tomorrow" is the local tomorrow even for a time in Tokyo, which may already be on it: parse_clock reads the
  # date and time here, and that wall time is then read again in the source zone.
  local here local_epoch
  here=$(answers_local_zone)
  if ! local_epoch=$(TZ="$here" parse_clock "$clock_phrase" today) ||
    ! epoch=$(TZ="$source_zone" date -d "$(TZ="$here" date -d "@$local_epoch" '+%F %H:%M')" +%s); then
    echo "no time in \"$1\""
    return 1
  fi
  source_day=$(answers_zone_day "$source_zone" "$epoch" "$here")
  target_day=$(answers_zone_day "$target_zone" "$epoch" "$here")
  if [ "$source_day" = today ] && [ "$target_day" = today ]; then
    source_day="" target_day=""
  fi
  answers_copy_and_say "$(answers_zone_moment "$source_zone" "$source_label" "$epoch" "$source_day") is $(answers_zone_moment \
    "$target_zone" "$target_label" "$epoch" "$target_day") ($(answers_describe_offset \
    "$(answers_minutes_ahead "$target_zone" "$source_zone" "$epoch")"))"
}

# The same call as the Leader and Bar submaps' Weather bind (`Popups.open("weather")` in the Hyprland config).
open_weather_popup() {
  local qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"
  if [ ! -x "$qs_ipc" ]; then
    echo "no Quickshell bar: $qs_ipc is missing"
    return 1
  fi
  "$qs_ipc" call popup open weather
}

# Spoken words that qalc misreads as units ("times", "percent of", "squared"), rewritten into its syntax.
# Each rule is "ERE<TAB>replacement", applied in order to text padded with spaces. A rule repeats until it no longer
# matches, so its replacement must never match its own pattern (" mod " for " (mod|modulo) " would loop forever).
answers_math_rules=(
  $' (to the power of|raised to the power of|raised to the|raised to|to the) ([0-9.]+)(st|nd|rd|th)?( power)? \t ^ \\2 '
  $' to the power of \t ^ '
  $' squared \t ^2 '
  $' cubed \t ^3 '
  $' (the )?square root of \t sqrt '
  $' (the )?cube root of \t cbrt '
  $' percent of \t /100 * '
  $' percent \t % '
  $' (multiplied by|times) \t * '
  $' ([0-9.]+) x ([0-9.]+) \t \\1 * \\2 '
  $' (divided by|over) \t / '
  $' plus \t + '
  $' (minus|negative) \t - '
  $' (modulo|modulus) \t mod '
  $' factorial \t ! '
  $' (a )?half of \t 0.5 * '
  $' (a|1) third of \t 1/3 * '
  $' (a|1) quarter of \t 0.25 * '
  $' ([0-9./]+) of \t \\1 * '
  $' (twice|double) \t 2 * '
  $' triple \t 3 * '
  $' degrees (fahrenheit|f) \t fahrenheit '
  $' degrees (celsius|centigrade|c) \t celsius '
  $' ([0-9.]+) f \t \\1 fahrenheit '
  $' ([0-9.]+) c \t \\1 celsius '
  $' (into|in) \t to '
  $' (a|an) \t 1 '
)

# Turns runs of number words into digits: "two hundred and thirty point five" is 230.5, "a thousand" 1000.
answers_number_words() {
  awk '
    BEGIN {
      split("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen", w)
      for (i = 1; i <= 20; i++) small[w[i]] = i - 1
      split("twenty thirty forty fifty sixty seventy eighty ninety", t)
      for (i = 1; i <= 8; i++) tens[t[i]] = (i + 1) * 10
      scale["thousand"] = 1000; scale["million"] = 1000000; scale["billion"] = 1000000000
    }
    function is_number_word(word) { return word in small || word in tens || word == "hundred" || word in scale }
    function flush() {
      if (in_number) out = out " " (total + current) (decimals != "" ? "." decimals : "")
      in_number = 0; total = 0; current = 0; decimals = ""; after_point = 0
    }
    {
      out = ""
      for (i = 1; i <= NF; i++) {
        word = $i; next_word = $(i + 1)
        if (after_point && word in small && small[word] < 10) { decimals = decimals small[word]; continue }
        if (after_point) flush()
        if (word == "a" && (next_word == "hundred" || next_word in scale)) { in_number = 1; current = 1; continue }
        if (word in small || word in tens) { in_number = 1; current += (word in small ? small[word] : tens[word]); continue }
        if (word == "hundred" && in_number) { current = (current ? current : 1) * 100; continue }
        if (word in scale && in_number) { total += (current ? current : 1) * scale[word]; current = 0; continue }
        if (word == "and" && in_number && is_number_word(next_word)) continue
        if (word == "point" && in_number && next_word in small) { after_point = 1; continue }
        flush()
        out = out " " word
      }
      flush()
      print substr(out, 2)
    }'
}

# Prints the qalc expression for a spoken question, or nothing when there is no expression left.
answers_spoken_math() {
  # The rules hold "/" and "|", so sed gets a delimiter no rule can contain.
  local text="${1,,}" rule delimiter=$'\001'
  text="${text//[\'’]/}"
  text=$(sed -E -e ':comma' -e 's/([0-9]),([0-9])/\1\2/g' -e 't comma' \
    -e 's/([a-z])-([a-z])/\1 \2/g; s/%/ percent /g; s/[×✕∗]/ times /g; s/÷/ divided by /g; s/[−–]/-/g' \
    -e 's/\.([^0-9]|$)/ \1/g; s#[^a-z0-9.+*/^()$€£-]# #g; s/ +/ /g' <<<"$text")
  # The raw transcript has not been through replacements.d, which routing used ("fort = four"); voxcmd's own
  # apply_replacements runs them here, whole words only, so punctuation and decimals survive.
  text=$(apply_replacements "$text" | answers_number_words)
  text=$(sed -E 's/([0-9]) point ([0-9])/\1.\2/g' <<<"$text")
  # "how many feet are in a mile" asks for "a mile to feet".
  text="${text/ are in / in }"
  if [[ "$text" =~ how\ many\ ([a-z]+( [a-z]+)?)\ (are\ )?(in|is|make)\ (.+)$ ]]; then
    text="${BASH_REMATCH[5]} to ${BASH_REMATCH[1]}"
  fi
  text=" $text "
  for rule in "${answers_math_rules[@]}"; do
    text=$(sed -E ":again; s${delimiter}${rule%%$'\t'*}${delimiter}${rule#*$'\t'}${delimiter}; t again" <<<"$text")
  done
  text=$(sed -E \
    -e "s/^ *${answers_lead}//" \
    -e 's/^((what is|whats|what s|how much is|what does|calculate|compute|evaluate|work out|solve|convert) )?//' \
    -e 's/( (equal|equals|make|come to|please|thanks|thank you))* *$//' <<<"$text")
  printf '%s' "$text"
}

# Unit conversions ("to") go to qalc as they are. Anything else is plain arithmetic, so qalc runs with units off and
# fails on a leftover word instead of reading it as a unit, the way "hello world" would otherwise become B²·h²·L³.
answer_calculation() {
  local expression answer
  expression=$(answers_spoken_math "$1")
  if [ -z "$expression" ]; then
    echo "nothing to calculate"
    return 1
  fi
  if [[ " $expression " == *" to "* ]]; then
    answer=$(qalc -t "$expression" </dev/null 2>&1) || answer=""
    # Imperial targets come back mixed ("3 mi + 188 yd + ..."); dividing by the target unit gives one number.
    if [[ "$answer" == *" + "* ]]; then
      local target_unit="${expression##* to }"
      answer=$(qalc -t "(${expression% to *}) / (1 $target_unit)" </dev/null 2>&1) && answer="$answer $target_unit" || answer=""
    fi
  else
    answer=$(qalc -t -s "units 0" "$expression" </dev/null 2>&1) || answer=""
  fi
  answer=$(tail -n 1 <<<"$answer")
  if [ -z "$answer" ]; then
    echo "qalc could not read: $expression"
    return 1
  fi
  # wl-copy keeps serving the clipboard in the background; with voxcmd's pipe left open the action would never end.
  wl-copy -- "${answer//−/-}" >/dev/null 2>&1 </dev/null || true
  echo "$(answers_readable_expression "$expression") = $answer"
}

# "15 /100 * 230" back to "15% of 230", "2 ^ 10" to "2^10", for the notification.
answers_readable_expression() {
  sed -E 's/ ?\^ ?/^/g; s/ ([!%])/\1/g; s/ ?\/ ?100 \*/% of/g; s/^- /-/' <<<"$1"
}
