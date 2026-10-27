#!/usr/bin/env bash
# Resolves the reviewer registry: `reviewers.sh list [repo_dir]` prints the merged entries as one JSON array.
#
# Layers, lowest to highest: built-in (reviewers.json beside this script), user file, Settings choices, repo file.
# Layer files are {"reviewers": [entry...]}; the Settings file is {"reviewers": {name: {"local": scope, "gate": mode}}}.
# Entries merge by name, object fields recursively, arrays replaced; "enabled": false drops the entry.
# A string `local` is shorthand for local.scope. The effective scope is local.scope, else local.default, else "off".
# A broken or non-conforming layer is skipped with a warning on stderr (the other layers still resolve); a bad
# built-in file is fatal. Settings choices only adjust existing entries and never add one.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
builtin_file=${REVIEWERS_BUILTIN_FILE:-$here/reviewers.json}
user_file=${REVIEWERS_USER_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/code-reviewers/reviewers.json}
settings_file=${REVIEWERS_SETTINGS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/developer.json}

# Reads one layer file (arg 1 is its kind) and prints {entries: [...], warnings: [...]}; entries are normalized so
# that `local` is always an object and invalid enum values are dropped.
# shellcheck disable=SC2016 # jq variables, not shell ones.
normalize_jq='
def scopes: ["off", "public", "all"];
def gates: ["auto", "always", "never"];
def fix_local:
  if has("local") then
    (if (.local | type) == "string" then .local = {scope: .local}
     elif (.local | type) == "object" then .
     else del(.local) end)
  else . end;
def check_entry($where):
  (if (.local.scope? != null) and ((.local.scope | IN(scopes[])) | not)
   then {w: ($where + ": invalid local scope " + (.local.scope | tojson) + " ignored"), e: del(.local.scope)}
   else {w: null, e: .} end) as $a
  | ($a.e
     | if has("gate") and ((.gate | IN(gates[])) | not)
       then {w: ($where + ": invalid gate " + (.gate | tojson) + " ignored"), e: del(.gate)}
       else {w: null, e: .} end) as $b
  | {w: [$a.w, $b.w] | map(select(. != null)), e: $b.e};
if type != "object" or ((.reviewers // null) == null) then
  {entries: [], warnings: ["no \"reviewers\" key, layer ignored"]}
else
  (if $kind == "settings" then
     if (.reviewers | type) != "object" then null
     else [.reviewers | to_entries[] | select(.value | type == "object") | .value + {name: .key}] end
   else
     if (.reviewers | type) != "array" then null
     else .reviewers end
   end) as $raw
  | if $raw == null then {entries: [], warnings: ["\"reviewers\" has the wrong type, layer ignored"]}
    else
      [$raw[] | if type != "object" or ((.name | type) != "string") or .name == ""
                then {w: ["entry without a string name skipped"], e: null}
                else (fix_local | check_entry("reviewer " + .name)) end] as $r
      | {entries: [$r[].e | select(. != null)], warnings: [$r[].w[]]}
    end
end
'

# shellcheck disable=SC2016
merge_jq='
def finish: del(.enabled)
  | if (.local | type) == "object" then .local.scope = (.local.scope // .local.default // "off") else . end
  | .gate = (.gate // "auto");
reduce $layers[] as $layer ({order: [], by_name: {}};
  reduce $layer.entries[] as $e (.;
    if ($layer.kind == "settings") and (.by_name[$e.name] == null) then .
    else
      (if .by_name[$e.name] == null then .order += [$e.name] else . end)
      | .by_name[$e.name] = ((.by_name[$e.name] // {}) * $e)
    end))
| . as $m | [$m.order[] | $m.by_name[.] | select(.enabled != false) | finish]
'

# Appends one normalized layer to $layers_json; a missing file is silent, an unreadable one warns.
add_layer() {
  local kind=$1 file=$2 out
  [ -e "$file" ] || return 0
  if ! out=$(jq -c --arg kind "$kind" "$normalize_jq" "$file" 2>/dev/null); then
    echo "reviewers.sh: $file is not valid JSON, layer skipped" >&2
    [ "$kind" = builtin ] && exit 1
    return 0
  fi
  while IFS= read -r warning; do
    echo "reviewers.sh: $file: $warning" >&2
  done < <(jq -r '.warnings[]' <<<"$out")
  layers_json=$(jq -c --arg kind "$kind" --argjson layer "$out" '. + [{kind: $kind, entries: $layer.entries}]' <<<"$layers_json")
}

list() {
  local repo_dir=${1:-$PWD} repo_root repo_file
  layers_json='[]'
  [ -e "$builtin_file" ] || {
    echo "reviewers.sh: built-in file $builtin_file is missing" >&2
    exit 1
  }
  add_layer builtin "$builtin_file"
  add_layer user "$user_file"
  add_layer settings "$settings_file"
  if repo_root=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
    repo_file=$repo_root/.claude/reviewers.json
    add_layer repo "$repo_file"
  fi
  jq -n --argjson layers "$layers_json" "$merge_jq"
}

case "${1:-}" in
list) list "${2:-}" ;;
*)
  echo "usage: reviewers.sh list [repo_dir]" >&2
  exit 64
  ;;
esac
