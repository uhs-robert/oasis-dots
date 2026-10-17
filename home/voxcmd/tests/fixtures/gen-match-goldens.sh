#!/usr/bin/env bash
# Writes the golden files the Rust matcher is compared against: what the bash voxcmd's verb matching, force prefixes
# and near-miss.awk make of a corpus of phrases, over the integrations in this checkout. Run it by hand when the corpus
# or an integration's verbs change, never from a check, and commit the outputs; `cargo test` reads them and needs no
# bash. A golden changes only with the owner's sign-off (voxcmd-port.md, Working rules).
#
#   home/voxcmd/tests/fixtures/gen-match-goldens.sh
#
# Writes next to this script:
#   legacy-dump.jsonl   `voxcmd _legacy-dump` of .config/voxcmd/integrations.d, which the Rust test loads as its config
#   match-goldens.tsv   one line per corpus phrase, tab separated: phrase, force, matches, near misses
#                         force    `<stem> <rest>` of forcing_integration, or `-`
#                         matches  per integration, the first verb match_loaded_verbs takes, as
#                                  `<stem>:<verb index>:<action>`, plus `=<target>` when the verb has a placeholder;
#                                  joined by `; `
#                         near     per verb that near-miss.awk prints, `<stem>:<verb index>:<action>`, `=<target>` when
#                                  it has one, then `~<words left over>`; joined by `; `
# Phrases are normalized ([a-z0-9 ]), so no field needs escaping. match/intents.local adds intent forms, so the
# intents.local merge is tested too.
#
# The corpus: every phrase and "and then" step of tests/phrases.tsv and tests/bench-phrases.tsv, each integration's
# examples with their <placeholders> filled, the quoted phrases of the README, all normalized as a step is, plus each
# phrase of two to eight words with one word dropped, two neighbours swapped or one word said twice, and each of up to
# eight words with "please", "thanks" or "now" after it.
set -uo pipefail
shopt -s extglob # the <placeholder> fill below

fixtures_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH='' cd -- "$fixtures_dir/../.." && pwd)
share_dir=$package_dir/.local/share/voxcmd
voxcmd_bin=$package_dir/.local/bin/voxcmd
integrations_config=$package_dir/.config/voxcmd

# Fixed so the output does not depend on the machine: bytewise globs and no inherited voxcmd or XDG settings, which
# integrations expand into their settings when sourced.
export LC_ALL=C HOME=/nonexistent
while IFS= read -r variable; do unset "$variable"; done < <(compgen -e | grep -E '^(VOXCMD_|XDG_)' || true)

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# ---- the integrations, as the Rust loader reads them ----------------------------------------------------------------

# Run from the config dir with a relative VOXCMD_CONFIG_DIR, so the dump's file paths hold no home directory.
(cd "$integrations_config" && VOXCMD_CONFIG_DIR=. "$voxcmd_bin" _legacy-dump) >"$work_dir/legacy-dump.jsonl" || {
  echo "gen-match-goldens: _legacy-dump failed" >&2
  exit 1
}

# ---- the bash functions, lifted out of the script by name (it cannot be sourced: it routes a phrase when it loads) --

lift() { awk -v start="$1" -v end="$2" '$0 ~ start { printing = 1 } printing { print } printing && $0 ~ end { exit }' "$voxcmd_bin"; }
# shellcheck source=/dev/null
source "$share_dir/spoken-position.sh" # spoken_ordinal, for name_workspace_ordinals
voxcmd_share_dir=$share_dir            # read by the integrations as they load
# shellcheck disable=SC2034 # read by load_local_intents, lifted below
config_dir=$fixtures_dir/match         # load_local_intents reads intents.local here
lifted=$(lift '^declare -A intents=[(]' '^[)]')
for function_name in normalize apply_replacements name_workspace_ordinals load_local_intents expand_intents \
  compile_pattern load_integration init_wake_regex split_leading_wake; do
  source_text=$(lift "^${function_name}[(][)] [{]" '^}')
  [ -n "$source_text" ] || {
    echo "gen-match-goldens: $function_name not found in voxcmd" >&2
    exit 1
  }
  lifted+=$'\n'$source_text
done
lifted+=$'\n'$(grep -E '^(wake_word|wake_aliases|wake_regex|wake_rest)=' "$voxcmd_bin")
wake_rest="" # set by the lifted split_leading_wake
eval "$lifted"
load_local_intents
export -f normalize # for the corpus's perturbation step below
export voxcmd_share_dir

# A step as route_step sees it: normalized, replaced, without a leading wake word.
step_text() {
  local text
  text=$(apply_replacements "$(normalize "$1")")
  if split_leading_wake "$text"; then text="$wake_rest"; fi
  printf '%s\n' "$text"
}

# Per integration file, in glob order: V rows (stem, verb index, action, compiled regex, capture group), F rows
# (stem, normalized force prefix) and the near-miss.awk input (stem:index:action, intents-expanded pattern).
for file in "$integrations_config"/integrations.d/*.sh; do
  (
    load_integration "$file" >/dev/null
    stem=$(basename "$file" .sh)
    index=0
    # shellcheck disable=SC2154 # set by load_integration
    for entry in "${integration_verbs[@]}"; do
      read -r action pattern <<<"$entry"
      compiled=$(compile_pattern "$pattern")
      printf 'V\t%s\t%s\t%s\t%s\t%s\n' "$stem" "$index" "$action" "${compiled%$'\t'*}" "${compiled##*$'\t'}"
      expand_intents "$pattern"
      printf 'N\t%s:%s:%s\t%s\n' "$stem" "$index" "$action" "$expanded_pattern"
      index=$((index + 1))
    done
    # shellcheck disable=SC2154 # set by load_integration
    for prefix in "${integration_force_prefixes[@]}"; do printf 'F\t%s\t%s\n' "$stem" "$(normalize "$prefix")"; done
  )
done >"$work_dir/tables"
grep '^N' "$work_dir/tables" | cut -f2- >"$work_dir/near-input"

# ---- the corpus -----------------------------------------------------------------------------------------------------

{
  for file in "$package_dir/tests/phrases.tsv" "$package_dir/tests/bench-phrases.tsv"; do
    awk -F'\t' 'NR > 1 { print $1 }' "$file"
    # Each step of a sequence, split roughly as split_phrase does: any step is a phrase to match anyway.
    awk -F'\t' 'NR > 1 { print $1 }' "$file" | sed -E 's/(,? and then|, then) /\n/Ig'
  done
  jq -r '.examples[]' "$work_dir/legacy-dump.jsonl" | while IFS= read -r example; do
    for filler in firefox "twenty five" 3 "the slack window"; do printf '%s\n' "${example//<+([^>])>/$filler}"; done
  done
  grep -o '"[a-z0-9 ,'"'"']\{3,60\}"' "$integrations_config/README.md" | tr -d '"'
} >"$work_dir/raw"
while IFS= read -r phrase; do step_text "$phrase"; done <"$work_dir/raw" | grep -v '[<>]' | awk 'NF' | sort -u >"$work_dir/base"
awk '{
  print
  n = split($0, w, " ")
  if (n > 8) next
  # Words after a target: whether an optional group or the target takes them is where greedy and lazy captures differ.
  print $0 " please"
  print $0 " thanks"
  print $0 " now"
  if (n < 2) next
  for (i = 1; i <= n; i++) {
    dropped = ""; doubled = ""
    for (j = 1; j <= n; j++) {
      if (j != i) dropped = dropped (dropped == "" ? "" : " ") w[j]
      doubled = doubled (doubled == "" ? "" : " ") w[j] (j == i ? " " w[j] : "")
    }
    print dropped
    print doubled
    if (i < n) {
      swapped = ""
      for (j = 1; j <= n; j++) swapped = swapped (swapped == "" ? "" : " ") (j == i ? w[i + 1] : j == i + 1 ? w[i] : w[j])
      print swapped
    }
  }
}' "$work_dir/base" | awk 'NF' | sort -u >"$work_dir/corpus"

# ---- the rows -------------------------------------------------------------------------------------------------------

# rows_for <phrase file>: the line of each phrase in it, in the file's order.
rows_for() {
  local phrase stem index action regex group matched_stem prefix forced matches near
  local -a verb_rows=() force_rows=()
  mapfile -t verb_rows < <(grep '^V' "$work_dir/tables")
  mapfile -t force_rows < <(grep '^F' "$work_dir/tables")
  while IFS= read -r phrase; do
    forced=-
    for row in "${force_rows[@]}"; do
      IFS=$'\t' read -r _ stem prefix <<<"$row"
      if [ -n "$prefix" ] && [[ "$phrase" == "$prefix "?* ]]; then
        forced="$stem ${phrase#"$prefix "}"
        break
      fi
    done
    matched_stem="" matches=""
    for row in "${verb_rows[@]}"; do
      IFS=$'\t' read -r _ stem index action regex group <<<"$row"
      [ "$stem" != "$matched_stem" ] || continue
      if [[ "$phrase" =~ $regex ]]; then
        matches+="${matches:+; }$stem:$index:$action"
        [ "$group" = 0 ] || matches+="=${BASH_REMATCH[$group]}"
        matched_stem=$stem
      fi
    done
    near=$(NEAR_MISS_PHRASE="$phrase" awk -f "$share_dir/near-miss.awk" "$work_dir/near-input" |
      awk -F'\t' '{ printf "%s%s%s~%s", (NR > 1 ? "; " : ""), $1, ($3 == "true" ? "=" $2 : ""), $4 }')
    printf '%s\t%s\t%s\t%s\n' "$phrase" "$forced" "$matches" "$near"
  done <"$1"
}

split -n "l/$(nproc)" -d "$work_dir/corpus" "$work_dir/chunk."
for chunk in "$work_dir"/chunk.*; do rows_for "$chunk" >"$chunk.rows" & done
wait

cat "$work_dir"/chunk.*.rows >"$fixtures_dir/match-goldens.tsv"
cp "$work_dir/legacy-dump.jsonl" "$fixtures_dir/legacy-dump.jsonl"
echo "wrote $(wc -l <"$fixtures_dir/match-goldens.tsv") phrases"
