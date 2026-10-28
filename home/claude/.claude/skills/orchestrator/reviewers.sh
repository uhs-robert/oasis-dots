#!/usr/bin/env bash
# Resolves the reviewer registry: `reviewers.sh list [repo_dir]` prints the merged entries as one JSON array.
#
# Layers, lowest to highest: built-in (reviewers.json beside this script), then the repo file <repo root>/.claude/reviewers.json.
# Both are {"reviewers": [entry...]}. Entries merge by name, object fields recursively, arrays replaced; "enabled": false
# drops the entry. A string `local` is shorthand for local.scope. The effective scope is local.scope, else local.default,
# else "off". A broken or non-conforming repo file, or entry field, is skipped with a warning on stderr (the built-in
# still resolves); any warning on the built-in file is fatal, since it is ours.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
builtin_file=${REVIEWERS_BUILTIN_FILE:-$here/reviewers.json}
repo_file_override=${REVIEWERS_REPO_FILE:-}

# Reads one layer file (arg 1 is its kind, builtin or repo) and prints {entries: [...], warnings: [...]}; entries are normalized so
# that `local` is an object whenever the layer gave one, and an invalid scope or default becomes "off" (the safe side).
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
  (if has("github") and .github == null then del(.github) else . end)
  | (if (.local | type) == "object" and (.local.scope? != null) and ((.local.scope | IN(scopes[])) | not)
   then .local.scope = "off" else . end)
  | (if (.local | type) == "object" and (.local.default? != null) and ((.local.default | IN(scopes[])) | not)
     then .local.default = "off" else . end)
  | (if has("gate") and ((.gate | IN(gates[])) | not) then del(.gate) else . end)
  | (if has("enabled") and ((.enabled | type) != "boolean") then del(.enabled) else . end);
if type != "object" or ((.reviewers // null) == null) then
  {entries: [], warnings: ["no \"reviewers\" key, layer ignored"]}
elif (.reviewers | type) != "array" then
  {entries: [], warnings: ["\"reviewers\" has the wrong type, layer ignored"]}
else
  [.reviewers[] | {w: [], e: .}] as $pre
  | [$pre[] | if .e == null then .
              elif (.e | type) != "object" or ((.e.name | type) != "string") or .e.name == ""
              then {w: (.w + ["entry without a string name skipped"]), e: null}
              else .e as $e | {w: (.w + ($e | problems("reviewer " + $e.name))), e: ($e | fix_local | sanitize)} end] as $r
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
    (if .by_name[$e.name] == null then .order += [$e.name] else . end)
    | .by_name[$e.name] = ((.by_name[$e.name] // {}) * $e)))
| . as $m | [$m.order[] | $m.by_name[.] | select(.enabled != false) | finish]
'

# Appends one normalized layer to $layers_json; a missing file is silent, an unreadable one warns.
add_layer() {
  local kind=$1 file=$2 out
  [ -e "$file" ] || return 0
  # Exactly one JSON value: an empty file prints nothing and two values print twice, either breaks the merge below.
  if ! jq -e -s 'length == 1' "$file" >/dev/null 2>&1 || ! out=$(jq -c --arg kind "$kind" "$normalize_jq" "$file" 2>/dev/null); then
    echo "reviewers.sh: $file is not a single valid JSON value, layer skipped" >&2
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
  local repo_dir=${1:-$PWD} repo_root
  layers_json='[]'
  [ -e "$builtin_file" ] || {
    echo "reviewers.sh: built-in file $builtin_file is missing" >&2
    exit 1
  }
  add_layer builtin "$builtin_file"
  if repo_root=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
    add_layer repo "$repo_root/.claude/reviewers.json"
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
