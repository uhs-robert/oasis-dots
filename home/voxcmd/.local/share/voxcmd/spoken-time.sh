# shellcheck shell=bash
# Spoken clock times, durations and days, and the bar's clock format, shared by integrations that source it from "$voxcmd_share_dir".
# Integrations sit in integrations.d/, where every file is loaded as one, so this lives beside voxcmd instead.
#
# Transcripts arrive normalized: lowercase, no punctuation, so "1.5 hours" is "1 5 hours" and "3:30 p.m." is
# "3 30 p m". Amounts are kept in thousandths so halves and quarters stay integer arithmetic.

# Global (-g): voxcmd sources integrations inside a function and runs the action after it returns, so a plain
# declare -A would be gone by then and every number word would read as unknown.
declare -gA number_words=(
  [zero]=0 [one]=1 [two]=2 [three]=3 [four]=4 [five]=5 [six]=6 [seven]=7 [eight]=8 [nine]=9 [ten]=10
  [eleven]=11 [twelve]=12 [thirteen]=13 [fourteen]=14 [fifteen]=15 [sixteen]=16 [seventeen]=17 [eighteen]=18
  [nineteen]=19 [twenty]=20 [thirty]=30 [forty]=40 [fifty]=50 [sixty]=60 [seventy]=70 [eighty]=80 [ninety]=90
)

unit_seconds() {
  case "$1" in
  s | sec | secs | second | seconds) echo 1 ;;
  m | min | mins | minute | minutes) echo 60 ;;
  h | hr | hrs | hour | hours) echo 3600 ;;
  *) return 1 ;;
  esac
}

# Reads an amount at parse_words[parse_at] into amount_milli and advances parse_at: digits, "1 5" (1.5), number
# words ("twenty five"), "a"/"an", "half (a|an)", "a quarter (of) (an)", and a trailing "and a half".
read_amount() {
  local word="${parse_words[parse_at]-}" next="${parse_words[parse_at + 1]-}"
  amount_milli=""
  if [[ "$word" =~ ^[0-9]+$ ]]; then
    amount_milli=$((10#$word * 1000))
    parse_at=$((parse_at + 1))
    if [[ "$next" =~ ^[0-9]{1,3}$ ]] && unit_seconds "${parse_words[parse_at + 1]-}" >/dev/null; then
      local fraction="${next}000"
      amount_milli=$((amount_milli + 10#${fraction:0:3}))
      parse_at=$((parse_at + 1))
    fi
  elif [ "$word" = half ]; then
    amount_milli=500
    parse_at=$((parse_at + 1))
    [[ "${parse_words[parse_at]-}" =~ ^(a|an)$ ]] && parse_at=$((parse_at + 1))
  elif [[ "$word" =~ ^(a|an)$ ]] && [ "$next" = quarter ]; then
    amount_milli=250
    parse_at=$((parse_at + 2))
    [ "${parse_words[parse_at]-}" = of ] && parse_at=$((parse_at + 1))
    [[ "${parse_words[parse_at]-}" =~ ^(a|an)$ ]] && parse_at=$((parse_at + 1))
  elif [[ "$word" =~ ^(a|an)$ ]] && [ "$next" = half ]; then
    amount_milli=500
    parse_at=$((parse_at + 2))
  elif [[ "$word" =~ ^(a|an)$ ]]; then
    amount_milli=1000
    parse_at=$((parse_at + 1))
  else
    # One number word, or a tens word and a ones word ("twenty five"); "three thirty" stays two numbers.
    local value word_value
    [ -n "$word" ] && value="${number_words[$word]-}" && [ -n "$value" ] || return 1
    parse_at=$((parse_at + 1))
    word_value=""
    [ -z "$next" ] || word_value="${number_words[$next]-}"
    if [ "$value" -ge 20 ] && [ -n "$word_value" ] && [ "$word_value" -ge 1 ] && [ "$word_value" -le 9 ]; then
      value=$((value + word_value))
      parse_at=$((parse_at + 1))
    fi
    amount_milli=$((value * 1000))
  fi
  if [ "${parse_words[parse_at]-}" = and ] && [ "${parse_words[parse_at + 1]-}" = a ] &&
    [ "${parse_words[parse_at + 2]-}" = half ] && unit_seconds "${parse_words[parse_at + 3]-}" >/dev/null; then
    amount_milli=$((amount_milli + 500))
    parse_at=$((parse_at + 3))
  fi
}

# Prints the seconds a whole phrase names: "5 minutes", "90 seconds", "an hour and a half", "1 hour 30",
# "two and a half minutes", "half an hour", "1 5 hours". Fails on anything left over.
parse_duration() {
  local -a parse_words
  read -ra parse_words <<<"$1"
  local parse_at=0 amount_milli total_milli=0 last_unit="" unit
  [ "${#parse_words[@]}" -gt 0 ] || return 1
  while [ "$parse_at" -lt "${#parse_words[@]}" ]; do
    if [ "${parse_words[parse_at]}" = and ] && [ -n "$last_unit" ]; then
      parse_at=$((parse_at + 1))
      # "an hour and a half": half of the unit just named
      if [ "${parse_words[parse_at]-}" = a ] && [ "${parse_words[parse_at + 1]-}" = half ] && [ -z "${parse_words[parse_at + 2]-}" ]; then
        total_milli=$((total_milli + last_unit * 500))
        parse_at=$((parse_at + 2))
        continue
      fi
    fi
    read_amount || return 1
    if unit=$(unit_seconds "${parse_words[parse_at]-}"); then
      parse_at=$((parse_at + 1))
    elif [ -n "$last_unit" ] && [ "$last_unit" -gt 1 ] && [ -z "${parse_words[parse_at]-}" ]; then
      # A bare number after a unit counts in the next one down: "1 hour 30", "2 minutes 15".
      unit=$((last_unit / 60))
    else
      return 1
    fi
    total_milli=$((total_milli + amount_milli * unit))
    last_unit="$unit"
  done
  echo $(((total_milli + 500) / 1000))
}

# Prints the epoch a clock time names: "3 pm", "3 30 p m", "15 30", "three thirty pm", "noon", "9 am tomorrow",
# "tomorrow at 7", "friday at 9 am", read in $TZ (the local zone when unset). By default it is the next time the
# clock reads that: today, or tomorrow once the time has passed. A weekday name ("friday", "next friday") is that
# day's next occurrence, a week out when it is today and the time has passed. With "today" as the second argument
# a time already past today stays today, for converting a time rather than scheduling one. With no am or pm,
# whichever of the two comes next.
parse_clock() {
  local -a parse_words=() clock_words=()
  local word day="" weekday="" weekday_prefix="" meridiem="" anchor="${2:-next}" word_at
  read -ra parse_words <<<"$1"
  for word_at in "${!parse_words[@]}"; do
    word="${parse_words[word_at]}"
    case "$word" in
    at | o | oh | oclock | clock | the | this) ;;
    # Only before a weekday, so "9 am next in tokyo" keeps reading as it did.
    on | next)
      is_weekday "${parse_words[word_at + 1]-}" || clock_words+=("$word")
      [ "$word" != next ] || ! is_weekday "${parse_words[word_at + 1]-}" || weekday_prefix=next
      ;;
    today) day=today ;;
    tomorrow) day=tomorrow ;;
    monday | tuesday | wednesday | thursday | friday | saturday | sunday) weekday="$word" ;;
    tonight) meridiem=pm ;;
    am | pm) meridiem="$word" ;;
    a | p) meridiem="${word}m" ;;
    m) ;;
    noon | midday) clock_words+=(12) meridiem=pm ;;
    midnight) clock_words+=(12) meridiem=am ;;
    morning) meridiem=am ;;
    afternoon | evening) meridiem=pm ;;
    *[0-9]am | *[0-9]pm)
      clock_words+=("${word%??}")
      meridiem="${word: -2}"
      ;;
    *) clock_words+=("$word") ;;
    esac
  done
  # Hour, then minutes, each digits or number words ("three thirty", "seven oh five").
  parse_words=("${clock_words[@]}")
  local parse_at=0 amount_milli hour minute=0
  [ "${#parse_words[@]}" -gt 0 ] || return 1
  if [[ "${parse_words[0]}" =~ ^[0-9]{3,4}$ ]]; then
    hour=$((10#${parse_words[0]} / 100))
    minute=$((10#${parse_words[0]} % 100))
    parse_at=1
  else
    read_amount && [ $((amount_milli % 1000)) = 0 ] || return 1
    hour=$((amount_milli / 1000))
    if [ "$parse_at" -lt "${#parse_words[@]}" ]; then
      read_amount && [ $((amount_milli % 1000)) = 0 ] || return 1
      minute=$((amount_milli / 1000))
    fi
  fi
  [ "$parse_at" = "${#parse_words[@]}" ] || return 1
  [ "$hour" -le 23 ] && [ "$minute" -le 59 ] || return 1
  case "$meridiem" in
  am | pm)
    [ "$hour" -ge 1 ] && [ "$hour" -le 12 ] || return 1
    hour=$((hour % 12))
    [ "$meridiem" = am ] || hour=$((hour + 12))
    ;;
  esac
  local now base candidate first="" hours=("$hour") bases=(today tomorrow)
  now=$(date +%s)
  if [ -n "$weekday" ]; then
    [ -z "$day" ] || return 1
    base=$(date -d "${weekday_prefix:+$weekday_prefix }$weekday" +%F)
    bases=("$base" "$(date -d "$base +7 days" +%F)")
  else
    [ "$anchor" = next ] || [ -n "$day" ] || day=today
  fi
  # No am or pm on a 1 to 12 hour: the sooner of the morning and evening time.
  [ -n "$meridiem" ] || [ "$hour" -lt 1 ] || [ "$hour" -gt 12 ] || hours=("$((hour % 12))" "$((hour % 12 + 12))")
  for base in "${bases[@]}"; do
    [ -z "$day" ] || [ "$day" = "$base" ] || continue
    for hour in "${hours[@]}"; do
      candidate=$(date -d "$base $hour:$minute" +%s) || return 1
      first="${first:-$candidate}"
      if [ "$candidate" -gt "$now" ] || [ "$day" = tomorrow ]; then
        echo "$candidate"
        return
      fi
    done
  done
  [ "$anchor" = today ] && [ -n "$first" ] && echo "$first"
}

# The strftime time of the bar's Settings > Clock format, the way its TimeFormat reads it: "locale" is 12-hour when
# the locale's time format has an AM/PM field. 12-hour reads "3:47pm".
clock_time_format() {
  local time_format
  time_format=$(jq -r '.time_format // empty' "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/clock.json" 2>/dev/null)
  if [ "$time_format" = 12h ] || { [ "$time_format" != 24h ] && [[ "$(locale t_fmt 2>/dev/null)" == *%[pPrI]* ]]; }; then
    echo '%-I:%M%P'
  else
    echo '%H:%M'
  fi
}

is_weekday() {
  case "$1" in
  monday | tuesday | wednesday | thursday | friday | saturday | sunday) ;;
  *) return 1 ;;
  esac
}

# Prints the date ("2026-10-13") a day word names: "today", "tomorrow", "friday", "next friday". A bare weekday
# may be today; "next friday" never is. Fails on anything else.
parse_day() {
  local weekday="${1#next }"
  case "$1" in
  today | tomorrow) date -d "$1" +%F ;;
  *) is_weekday "$weekday" && date -d "$1" +%F ;;
  esac
}

format_length() {
  local seconds="$1" parts=() hours minutes
  hours=$((seconds / 3600)) minutes=$((seconds % 3600 / 60)) seconds=$((seconds % 60))
  [ "$hours" = 0 ] || parts+=("$hours hour$([ "$hours" = 1 ] || echo s)")
  [ "$minutes" = 0 ] || parts+=("$minutes minute$([ "$minutes" = 1 ] || echo s)")
  [ "$seconds" = 0 ] || parts+=("$seconds second$([ "$seconds" = 1 ] || echo s)")
  echo "${parts[*]}"
}

# "3:47pm", "tomorrow 9:00am", "Thu 9:00am" within the week, else "Oct 20 9:00am", in the bar's Settings > Clock
# time format.
format_due() {
  local due="$1" format day=""
  format=$(clock_time_format)
  local due_day today
  due_day=$(date -d "@$due" +%F) today=$(date +%F)
  if [ "$due_day" = "$today" ]; then
    day=""
  elif [ "$due_day" = "$(date -d "$today +1 day" +%F)" ]; then
    day="tomorrow "
  elif [[ "$due_day" < "$(date -d "$today +7 days" +%F)" ]]; then
    day="$(date -d "@$due" +%a) "
  else
    day="$(date -d "@$due" '+%b %-d') "
  fi
  echo "$day$(date -d "@$due" "+$format")"
}

# "at 3:47pm" today, "tomorrow 9:00am" otherwise: a day reads wrong after "at".
format_at() {
  local when
  when=$(format_due "$1")
  [[ "$when" == [0-9]* ]] && when="at $when"
  echo "$when"
}
