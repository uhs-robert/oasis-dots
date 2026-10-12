# shellcheck shell=bash disable=SC2034,SC2016
# Quick answers: spoken math through qalc and the time and date; weather questions open the bar's weather popup.
# Format: ~/.config/voxcmd/README.md

name="Answers"
confirm=0

# Spoken lead-ins and tails that carry no meaning, allowed around every question.
answers_lead='((hey|hi|ok|okay|um|umm|uh|er|erm|hmm|so|well|please|quick question) )*((can|could|would) you (please )?)?((tell|show) me )?'
answers_tail='( (please|thanks|thank you))*'
answers_whats='(what is|whats|what s)'
answers_today='( (today|right now|now|currently|outside|out there))*'
# What a calculation has to start with when it is asked with "what's", so "what's up" stays out of qalc.
answers_math_start='(the )?((square|cube) root of |(minus|negative) )?([0-9].*|(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|a hundred|a thousand|half|a half|a third|a quarter|pi)( .*)?)'

verbs=(
  "time       ${answers_lead}(${answers_whats} the( current)? time|the time|what time is it|do you (have|know) the time)${answers_today}${answers_tail}"
  "date       ${answers_lead}((${answers_whats} )?(the|todays|today s)( current)? date|what (day|date|day of the week|month|year) is (it|today)|${answers_whats} today|which day is (it|today))${answers_today}${answers_tail}"
  "weather    ${answers_lead}((is|will|does) it (going to |gonna )?(rain|snow|be (rainy|wet|snowy|stormy))|(do|should) i (need|take|bring) an umbrella|(any|chance of) (rain|snow))( (today|tonight|later|this (morning|afternoon|evening)))*${answers_tail}"
  "weather    ${answers_lead}((${answers_whats}|how is|hows|how s) (the )?(weather|forecast|temperature)( (like|report))?|weather( (report|forecast))?|how (hot|cold|warm) is it)${answers_today}${answers_tail}"
  "calculate  ${answers_lead}(${answers_whats}|how much is|what does) ${answers_math_start}"
  "calculate  ${answers_lead}how many [a-z]+( [a-z]+)? (are )?(in|is|make) (a|an|one|[0-9]).*"
  "calculate  ${answers_lead}(calculate|compute|evaluate|work out|solve|convert) .+"
)

# Math reads $raw_transcript rather than a {target}: normalizing drops "%", "×", "/" and decimal points, so
# "2.5%" would reach qalc as "2 5".
examples=(
  "what time is it"
  "what's the date"
  "what's the weather"
  "will it rain today"
  "what's <number> percent of <number>"
  "convert <amount> <unit> to <unit>"
)

declare -A actions=(
  [time]='answer_time'
  [date]='date "+%A, %B %-d, %Y"'
  [weather]='open_weather_popup'
  [calculate]='answer_calculation "$raw_transcript"'
)
# The popup is the answer; a success toast would cover it.
silent_actions=(weather)

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
