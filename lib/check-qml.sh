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
    {
      n = split($0, statement, ";")
      for (i = 1; i <= n; i++) {
        if (!match(statement[i], /^[[:space:]]*import[[:space:]]+"[^"]+"/)) continue
        target = substr(statement[i], RSTART, RLENGTH)
        sub(/^[^"]*"/, "", target)
        sub(/"$/, "", target)
        if (target ~ /\.m?js$/) continue
        alias = "-"
        if (match(statement[i], /"[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
          alias = substr(statement[i], RSTART, RLENGTH)
          sub(/.*[[:space:]]/, "", alias)
        }
        dir = FILENAME
        sub(/\/[^\/]*$/, "", dir)
        print alias " " dir "/" target
      }
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

# Prints "<line> <name>" for the first use of a type in $types, or member access on a singleton in $singletons.
# shellcheck disable=SC2016
first_use_awk='
  function strip(line, out, i, c, quote) {
    out = ""
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (in_block) {
        if (c == "*" && substr(line, i + 1, 1) == "/") { in_block = 0; i++ }
        continue
      }
      if (quote != "") {
        if (c == "\\") i++
        else if (c == quote) { quote = ""; out = out c }
        continue
      }
      if (c == "/" && substr(line, i + 1, 1) == "/") break
      if (c == "/" && substr(line, i + 1, 1) == "*") { in_block = 1; i++; continue }
      if (c == "\"" || c == "\047" || c == "`") quote = c
      out = out c
    }
    return out
  }
  BEGIN {
    instance = "(^|[^.A-Za-z0-9_])(" types ")[[:space:]]*\\{"
    declared = "(^|[^A-Za-z0-9_])property[[:space:]]+(list[[:space:]]*<[[:space:]]*)?(" types ")([^A-Za-z0-9_]|$)"
    member = singletons == "" ? "" : "(^|[^.A-Za-z0-9_])(" singletons ")[[:space:]]*\\."
  }
  {
    text = strip($0)
    if (match(text, instance) || match(text, declared) || member != "" && match(text, member)) {
      name = substr(text, RSTART, RLENGTH)
      sub(/^[^A-Za-z_]+/, "", name)
      sub(/^property[[:space:]]+(list[[:space:]]*<[[:space:]]*)?/, "", name)
      sub(/[^A-Za-z0-9_].*$/, "", name)
      print FNR " " name
      exit
    }
  }
'

# Reports the first use in file $1 of a type from the unregistered folder $2.
report_unregistered_use() {
  types=$(find "$2" -maxdepth 1 -name '[A-Z]*.qml' -printf '%f\n' | sed 's/\.qml$//' | paste -sd '|' -)
  [ -n "$types" ] || return 0
  singletons=$(grep -l '^pragma Singleton' "$2"/[A-Z]*.qml | sed 's|.*/||; s/\.qml$//' | paste -sd '|' -)
  hit=$(awk -v types="$types" -v singletons="$singletons" "$first_use_awk" "$1")
  [ -n "$hit" ] || return 0
  printf '%s:%s: %s will not resolve at runtime: nothing reached from shell.qml imports %s/, so Quickshell will not register its types; import %s/ from a file Quickshell reaches from shell.qml (for example the one that loads %s) (#531)\n' \
    "${1#"$3"/}" "${hit%% *}" "${hit#* }" "${2#"$3"/}" "${2#"$3"/}" "$(basename "$1")"
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

# Quickshell 0.3.2 gives each module one-line opaque stubs (no members) for types another module defines, and qmllint
# resolves a name to whichever stub it meets first, so every member of QuickshellScreenInfo, ObjectModel or Anchors reads
# as missing. A copy of the installed module without those stubs keeps the real types; it only wins under --bare, which
# drops the default import paths so the copy can be listed ahead of the system one.
qs_module=''
qt_qml_dir=''
for import_dir in $("$(dirname -- "$qmllint_bin")/qtpaths6" --query QT_INSTALL_QML 2>/dev/null) /usr/lib/qt6/qml; do
  if [ -d "$import_dir/Quickshell" ]; then
    qs_module=$stage/qml
    qt_qml_dir=$import_dir
    mkdir -p "$qs_module"
    cp -r "$import_dir/Quickshell" "$qs_module/"
    find "$qs_module" -name '*.qmltypes' >"$stage/qmltypes"
    # Names of multi-line, non-opaque Components: a one-line stub is dropped only when one of these defines it, since
    # some types (QList<NMSettings*> and the like) are declared nowhere but in their stub.
    # shellcheck disable=SC2016
    xargs -r -d '\n' awk '
      /^    Component \{$/ { in_component = 1; opaque = 0; name = ""; next }
      in_component && /^        isTypeOpaque: true/ { opaque = 1 }
      in_component && /^        name: "/ { name = $0; sub(/^[^"]*"/, "", name); sub(/".*$/, "", name) }
      in_component && /^    \}$/ { if (!opaque && name != "") print name; in_component = 0 }
    ' <"$stage/qmltypes" | sort -u >"$stage/qmltypes.concrete"
    while IFS= read -r types_file; do
      # shellcheck disable=SC2016
      awk -v concrete="$stage/qmltypes.concrete" '
        BEGIN { while ((getline line <concrete) > 0) defined[line] = 1 }
        /^[[:space:]]*Component \{ isTypeOpaque: true;.*\}[[:space:]]*$/ {
          name = $0; sub(/.*name: "/, "", name); sub(/".*$/, "", name)
          if (name in defined) next
        }
        { print }
      ' "$types_file" >"$types_file.tmp" && mv "$types_file.tmp" "$types_file"
    done <"$stage/qmltypes"
    break
  fi
done

status=0
for tree in shell greeter; do
  list_reached_dirs "$stage/$tree" "$stage/$tree.reached"
  write_qmldirs "$stage/$tree.reached"
done

# Members read through parent, Loader.item and the like are typed QObject/QQuickItem, so a miss there is unknowable.
# Qt 6.12 moved a suggestion's replacement text from .replacement into documentEdits (both are read) and writes Loader.item and itemAt() receivers without quotes.
# The gaps list types Quickshell's qmltypes leave unexported or wrongly mark uncreatable; all exist at runtime. Edges and
# PopupAdjustment flags have no type of their own (0.3.2 declares them only as opaque stubs), so an int assigned to one
# reads as incompatible.
# shellcheck disable=SC2016
filter='
  def qualifies: [.replacement // empty, (.documentEdits // [])[].replacement] | any(test("\\.$|^pragma ComponentBehavior"));
  def untyped_miss: .message | test("not found on type \"(QObject|QQuickItem|QJSPrimitiveValue)\"|::item with type (QObject|QQuickItem)$|returning QQuickItem$");
  def gap: .message | test("^Type PanelWindow is not creatable|^Type margins is used|^Type \"BluetoothAdapter\" of property|^No type found for property \"(edges|gravity|adjustment)\"|^Cannot assign binding of type int to (Edges|PopupAdjustment)::Flags$");
  .files[] | .filename as $file | .warnings[] | select(
    (.id | IN("syntax", "import", "read-only-property", "required", "non-list-property",
      "duplicated-name", "duplicate-property-binding", "duplicate-inline-component", "duplicate-enum-entries",
      "alias-cycle", "inheritance-cycle", "unresolved-alias", "missing-enum-entry", "var-used-before-declaration"))
    or (.id | IN("incompatible-type", "uncreatable-type", "unresolved-type", "missing-type")) and (gap | not)
    or .id == "missing-property" and (untyped_miss | not)
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
  (
    cd "$stage/$tree" || exit 1
    # Qt 6.12 imports only the qmldirs named with -i (one flag each, absolute like the linted files so the two paths compare equal), not the one beside the linted file.
    set -- "$qmllint_bin" --ignore-settings --json -
    [ -n "$qs_module" ] && set -- "$@" --bare -I "$qs_module" -I "$qt_qml_dir"
    find "$PWD" -name qmldir >"$stage/$tree.qmldirs"
    while IFS= read -r qmldir; do set -- "$@" -i "$qmldir"; done <"$stage/$tree.qmldirs"
    find "$PWD" -maxdepth "$depth" \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' \) -exec "$@" {} +
  ) >"$report" 2>/dev/null
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
