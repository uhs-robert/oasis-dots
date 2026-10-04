#!/bin/sh
# Lints the Quickshell config and the greeter with Qt 6 qmllint, failing only on findings that are real errors.
# Stages qmldirs only for the folders Quickshell registers (reached by imports from shell.qml) and flags uses of unregistered types.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
cd "$repo_dir" || exit 1

qs_dir=home/quickshell/.config/quickshell
greeter_dir=system/etc/greetd/quickshell

# /usr/bin/qmllint on Arch is the Qt 5 one, which cannot read Qt 6 QML.
qmllint_bin=''
for candidate in /usr/lib/qt6/bin/qmllint qmllint6 qmllint; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" --version 2>/dev/null | grep -q '^qmllint 6\.'; then
    qmllint_bin=$candidate
    break
  fi
done

if [ -z "$qmllint_bin" ]; then
  echo 'skip: qmllint (Qt 6, qt6-declarative) not installed'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo 'skip: qmllint check needs jq'
  exit 0
fi

stage=$(mktemp -d) || exit 1
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' INT TERM
stage=$(realpath -- "$stage")

copy_sources() {
  mkdir -p "$2"
  git ls-files -co --exclude-standard -- "$1" | while IFS= read -r file; do
    case $file in
    *.qml | *.js | *.mjs) [ -f "$file" ] && printf '%s\n' "${file#"$1"/}" ;;
    esac
  done | (cd "$1" && tar -cf - -T -) | tar -xf - -C "$2"
}

# Prints "<alias> <importing dir>/<path>" for each folder import in the files named on stdin; alias is "-" when absent.
# shellcheck disable=SC2016
folder_imports() {
  xargs -r -d '\n' awk '
    match($0, /^[[:space:]]*import[[:space:]]+"[^"]+"/) {
      target = substr($0, RSTART, RLENGTH)
      sub(/^[^"]*"/, "", target)
      sub(/"$/, "", target)
      if (target ~ /\.m?js$/) next
      alias = "-"
      if (match($0, /"[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
        alias = substr($0, RSTART, RLENGTH)
        sub(/.*[[:space:]]/, "", alias)
      }
      dir = FILENAME
      sub(/\/[^\/]*$/, "", dir)
      print alias " " dir "/" target
    }
  '
}

# Walks import edges like Quickshell's scanner: shell.qml, then every capitalised .qml file of each reached folder.
list_reached_dirs() {
  printf '%s\n' "$1" | tee "$2" >"$2.frontier"
  while [ -s "$2.frontier" ]; do
    while IFS= read -r dir; do
      [ "$dir" = "$1" ] && printf '%s\n' "$dir/shell.qml"
      find "$dir" -maxdepth 1 -name '[A-Z]*.qml'
    done <"$2.frontier" | folder_imports | cut -d ' ' -f 2- | xargs -r -d '\n' realpath -mq -- | sort -u |
      while IFS= read -r dir; do
        [ -d "$dir" ] && ! grep -qxF -- "$dir" "$2" && printf '%s\n' "$dir"
      done >"$2.next"
    cat "$2.next" >>"$2"
    mv "$2.next" "$2.frontier"
  done
  rm -f "$2.frontier"
}

# Writes a qmldir per reached directory as Quickshell does: every capitalised .qml file is a type.
write_qmldirs() {
  while IFS= read -r dir; do
    [ -e "$dir/qmldir" ] && continue
    for file in "$dir"/[A-Z]*.qml; do
      [ -f "$file" ] || continue
      name=$(basename "$file" .qml)
      if grep -q '^pragma Singleton' "$file"; then
        printf 'singleton %s 1.0 %s.qml\n' "$name" "$name"
      else
        printf '%s 1.0 %s.qml\n' "$name" "$name"
      fi
    done >"$dir/qmldir"
    [ -s "$dir/qmldir" ] || rm -f "$dir/qmldir"
  done <"$1"
}

# Prints the first line of file $1 that instantiates a type of the unregistered folder $2.
report_unregistered_use() {
  names=$(find "$2" -maxdepth 1 -name '[A-Z]*.qml' -printf '%f\n' | sed 's/\.qml$//' | paste -sd '|' -)
  [ -n "$names" ] || return 0
  hit=$(grep -nE "(^|[^.[:alnum:]_])($names)[[:space:]]*\\{" "$1" | grep -vE '^[0-9]+:[[:space:]]*//' | head -n 1)
  [ -n "$hit" ] || return 0
  type=$(printf '%s\n' "${hit#*:}" | grep -oE "($names)[[:space:]]*\\{" | head -n 1 | sed 's/[[:space:]]*{$//')
  printf '%s:%s: %s is not a type at runtime: nothing reached from shell.qml imports %s/, so Quickshell will not register its types; import it from the file that loads %s (#531)\n' \
    "${1#"$3"/}" "${hit%%:*}" "$type" "${2#"$3"/}" "$(basename "$1")"
}

# Flags files outside the registered folders that use their siblings, or an unregistered folder imported without "as".
check_unregistered() {
  find "$1" -name '*.qml' -printf '%h\n' | sort -u | grep -vxF -f "$2" | while IFS= read -r dir; do
    for file in "$dir"/*.qml; do
      report_unregistered_use "$file" "$dir" "$1"
      printf '%s\n' "$file" | folder_imports | sed -n 's/^- //p' | xargs -r -d '\n' realpath -mq -- |
        while IFS= read -r target; do
          if [ ! -d "$target" ] || grep -qxF -- "$target" "$2"; then continue; fi
          report_unregistered_use "$file" "$target" "$1"
        done
    done
  done
}

copy_sources "$qs_dir" "$stage/shell"
copy_sources "$greeter_dir" "$stage/greeter"
copy_sources "$qs_dir/lock/skins" "$stage/greeter/lock/skins"
cp "$qs_dir/lock/Tints.js" "$stage/greeter/lock/"
mkdir -p "$stage/greeter/theme"
cp "$qs_dir/theme/Theme.qml" "$qs_dir/theme/Style.qml" "$qs_dir/theme/StyleSchema.js" "$qs_dir/theme/Paths.qml" "$qs_dir/theme/Watch.js" "$stage/greeter/theme/"
cp -r "$qs_dir/theme/styles" "$stage/greeter/theme/"

status=0
for tree in shell greeter; do
  list_reached_dirs "$stage/$tree" "$stage/$tree.reached"
  write_qmldirs "$stage/$tree.reached"
done

# Members read through parent, Loader.item and the like are typed QObject/QQuickItem, so a miss there is unknowable.
# The gaps list types Quickshell's qmltypes leave unexported or wrongly mark uncreatable; all exist at runtime.
# shellcheck disable=SC2016
filter='
  def qualifies: (.replacement // "") | test("\\.$|^pragma ComponentBehavior");
  def gap: .message | test("^Type PanelWindow is not creatable|^Type margins is used|^Type \"BluetoothAdapter\" of property|^No type found for property \"(edges|gravity|adjustment)\"");
  .files[] | .filename as $file | .warnings[] | select(
    (.id | IN("syntax", "import", "incompatible-type", "read-only-property", "required", "non-list-property",
      "duplicated-name", "duplicate-property-binding", "duplicate-inline-component", "duplicate-enum-entries",
      "alias-cycle", "inheritance-cycle", "unresolved-alias", "missing-enum-entry", "var-used-before-declaration"))
    or (.id | IN("uncreatable-type", "unresolved-type", "missing-type")) and (gap | not)
    or .id == "missing-property" and (.message | test("not found on type \"(QObject|QQuickItem|QJSPrimitiveValue)\"") | not)
    or .id == "unqualified" and .message == "Unqualified access" and ([(.suggestions // [])[] | select(qualifies)] | length) == 0
  ) | ([(.suggestions // [])[].message | select(startswith("Did you mean"))] | map(" " + .) | first // "") as $hint
  | "\($file):\(.line):\(.column): \(.message)\($hint) [\(.id)]"
'

for tree in shell greeter; do
  case $tree in
  shell) prefix=$qs_dir depth=99 ;;
  greeter) prefix=$greeter_dir depth=1 ;;
  esac
  unregistered=$(check_unregistered "$stage/$tree" "$stage/$tree.reached")
  if [ -n "$unregistered" ]; then
    printf '%s\n' "$unregistered" | sed "s|^|$prefix/|" >&2
    status=1
  fi
  report="$stage/$tree.json"
  wanted=$(cd "$stage/$tree" && find . -maxdepth "$depth" \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' \) | wc -l)
  (cd "$stage/$tree" && find . -maxdepth "$depth" \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' \) -exec "$qmllint_bin" --ignore-settings --json - {} +) >"$report" 2>/dev/null
  linted=$(jq -s '[.[].files[]] | length' "$report" 2>/dev/null) || linted=0
  if [ "$linted" -ne "$wanted" ]; then
    echo "qmllint: linted $linted of $wanted files in $prefix" >&2
    status=1
    continue
  fi
  findings=$(jq -r "$filter" "$report")
  if [ -n "$findings" ]; then
    printf '%s\n' "$findings" | sed -e "s|^\./|$prefix/|" -e "s|$stage/$tree|$prefix|g" >&2
    status=1
  fi
done

exit "$status"
