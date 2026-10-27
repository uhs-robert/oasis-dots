#!/usr/bin/env bash
# Resolves the reviewer registry: `reviewers.sh list [repo_dir]` prints the merged entries as one JSON array.
#
# Layers, lowest to highest: built-in (reviewers.json beside this script), user file, Settings choices, repo file.
# Layer files are {"reviewers": [entry...]}; the Settings file is {"reviewers": {name: {"local": scope, "gate": mode}}}.
# Entries merge by name, object fields recursively, arrays replaced; "enabled": false drops the entry.
# A string `local` is shorthand for local.scope. The effective scope is local.scope, else local.default, else "off".
# A broken or non-conforming layer, or entry field, is skipped with a warning on stderr (the other layers still
# resolve); any warning on the built-in file is fatal, since it is ours. An entry without a local config resolves to
# local.scope "off". Settings choices may set only local and gate, and only on existing entries.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
builtin_file=${REVIEWERS_BUILTIN_FILE:-$here/reviewers.json}
user_file=${REVIEWERS_USER_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/code-reviewers/reviewers.json}
settings_file=${REVIEWERS_SETTINGS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/developer.json}

# Reads one layer file (arg 1 is its kind) and prints {entries: [...], warnings: [...]}; entries are normalized so
# that `local` is an object whenever the layer gave one, and an invalid scope or default becomes "off" (the safe side).
# shellcheck disable=SC2016 # jq variables, not shell ones.
normalize_jq='
def scopes: ["off", "public", "all"];
def gates: ["auto", "always", "never"];
def settings_fields: ["local", "gate"];
def fix_local:
  if has("local") then
    (if (.local | type) == "string" then .local = {scope: .local}
     elif (.local | type) == "object" then .
     else del(.local) end)
  else . end;
def problems($where):
  [ (select(has("local") and ((.local | type) != "string" and (.local | type) != "object"))
     | $where + ": local is neither a string nor an object, ignored"),
    (select((.local | type) == "string" and ((.local | IN(scopes[])) | not))
     | $where + ": invalid local scope " + (.local | tojson) + ", using off"),
    (select((.local | type) == "object" and (.local.scope? != null) and ((.local.scope | IN(scopes[])) | not))
     | $where + ": invalid local scope " + (.local.scope | tojson) + ", using off"),
    (select((.local | type) == "object" and (.local.default? != null) and ((.local.default | IN(scopes[])) | not))
     | $where + ": invalid local default " + (.local.default | tojson) + ", using off"),
    (select(has("gate") and ((.gate | IN(gates[])) | not))
     | $where + ": invalid gate " + (.gate | tojson) + " ignored"),
    (select(has("enabled") and ((.enabled | type) != "boolean"))
     | $where + ": enabled must be true or false, ignored") ];
def sanitize:
  (if (.local | type) == "object" and (.local.scope? != null) and ((.local.scope | IN(scopes[])) | not)
   then .local.scope = "off" else . end)
  | (if (.local | type) == "object" and (.local.default? != null) and ((.local.default | IN(scopes[])) | not)
     then .local.default = "off" else . end)
  | (if has("gate") and ((.gate | IN(gates[])) | not) then del(.gate) else . end)
  | (if has("enabled") and ((.enabled | type) != "boolean") then del(.enabled) else . end);
if type != "object" or ((.reviewers // null) == null) then
  {entries: [], warnings: ["no \"reviewers\" key, layer ignored"]}
elif $kind == "settings" and (.reviewers | type) != "object" then
  {entries: [], warnings: ["\"reviewers\" has the wrong type, layer ignored"]}
elif $kind != "settings" and (.reviewers | type) != "array" then
  {entries: [], warnings: ["\"reviewers\" has the wrong type, layer ignored"]}
else
  (if $kind == "settings" then
     [.reviewers | to_entries[] | . as $kv
      | if ($kv.value | type) != "object" then {w: ["reviewer " + $kv.key + ": value is not an object, skipped"], e: null}
        else {w: [$kv.value | keys[] | select(IN(settings_fields[]) | not)
                  | "reviewer " + $kv.key + ": Settings may only set local and gate, ignored " + .],
              e: (($kv.value | with_entries(select(.key | IN(settings_fields[])))) + {name: $kv.key})} end]
   else
     [.reviewers[] | {w: [], e: .}]
   end) as $pre
  | [$pre[] | if .e == null then .
              elif (.e | type) != "object" or ((.e.name | type) != "string") or .e.name == ""
              then {w: (.w + ["entry without a string name skipped"]), e: null}
              else .e as $e | {w: (.w + ($e | fix_local | problems("reviewer " + $e.name))), e: ($e | fix_local | sanitize)} end] as $r
  | {entries: [$r[].e | select(. != null)], warnings: [$r[].w[]]}
end
'

# shellcheck disable=SC2016
merge_jq='
def finish: del(.enabled)
  | .local = ((if (.local | type) == "object" then .local else {} end) | .scope = (.scope // .default // "off"))
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
  local warnings
  warnings=$(jq -r '.warnings[]' <<<"$out")
  while IFS= read -r warning; do
    [ -n "$warning" ] && echo "reviewers.sh: $file: $warning" >&2
  done <<<"$warnings"
  if [ "$kind" = builtin ] && [ -n "$warnings" ]; then
    exit 1
  fi
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
