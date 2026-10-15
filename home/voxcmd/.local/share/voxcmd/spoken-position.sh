# shellcheck shell=bash
# Spoken positions: the number a phrase names where a number picks an item ("two", "twenty five", "second", "twenty first",
# "13th"). Sourced by voxcmd and by the integrations that name workspaces, windows and monitors. Counts and amounts
# (durations, volume) keep reading number_words only, because "second" there is a unit of time.

spoken_position_share_dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source-path=SCRIPTDIR source=spoken-time.sh
source "$spoken_position_share_dir/spoken-time.sh"

# Global (-g) for the same reason as number_words.
declare -gA ordinal_number_words=(
  [first]=1 [second]=2 [third]=3 [fourth]=4 [fifth]=5 [sixth]=6 [seventh]=7 [eighth]=8 [ninth]=9 [tenth]=10
  [eleventh]=11 [twelfth]=12 [thirteenth]=13 [fourteenth]=14 [fifteenth]=15 [sixteenth]=16 [seventeenth]=17
  [eighteenth]=18 [nineteenth]=19 [twentieth]=20 [thirtieth]=30 [fortieth]=40 [fiftieth]=50 [sixtieth]=60
  [seventieth]=70 [eightieth]=80 [ninetieth]=90
)

# Prints the number a single word or a "tens ones" pair names when it is an ordinal ("second", "2nd", "twenty first"), or fails. A
# digit ordinal needs its own suffix: "2th" and "11st" are not ordinals.
spoken_ordinal() {
  local first second suffix number
  read -r first second <<<"$1"
  [ -n "$first" ] || return 1
  if [ -n "${second:-}" ]; then
    [[ "$1" == "$first $second" ]] || return 1
    [[ "${number_words[$first]-}" =~ ^[2-9]0$ && "${ordinal_number_words[$second]-}" =~ ^[1-9]$ ]] || return 1
    echo $((${number_words[$first]} + ${ordinal_number_words[$second]}))
  elif [ -n "${ordinal_number_words[$first]+set}" ]; then
    echo "${ordinal_number_words[$first]}"
  elif [[ "$first" =~ ^([0-9]+)(st|nd|rd|th)$ ]]; then
    number=$((10#${BASH_REMATCH[1]}))
    suffix="${BASH_REMATCH[2]}"
    [ "$number" -ge 1 ] || return 1
    case "$((number % 100 >= 11 && number % 100 <= 13 ? 0 : number % 10))" in
    1) [ "$suffix" = st ] ;;
    2) [ "$suffix" = nd ] ;;
    3) [ "$suffix" = rd ] ;;
    *) [ "$suffix" = th ] ;;
    esac || return 1
    echo "$number"
  else
    return 1
  fi
}

# Prints the number digits, a number word or a "tens ones" pair names ("7", "seven", "twenty five"), or fails.
spoken_cardinal() {
  local first second
  read -r first second <<<"$1"
  [ -n "$first" ] || return 1
  if [ -n "${second:-}" ]; then
    [[ "$1" == "$first $second" && "${number_words[$first]-}" =~ ^[2-9]0$ && "${number_words[$second]-}" =~ ^[1-9]$ ]] || return 1
    echo $((${number_words[$first]} + ${number_words[$second]}))
  elif [[ "$first" =~ ^[0-9]+$ ]]; then
    echo "$((10#$first))"
  elif [ -n "${number_words[$first]+set}" ]; then
    echo "${number_words[$first]}"
  else
    return 1
  fi
}

# Prints the position a phrase names, as a number or as an ordinal, or fails. Whether it exists is the caller's to check.
spoken_position() {
  spoken_cardinal "$1" || spoken_ordinal "$1"
}
