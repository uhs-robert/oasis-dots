#!/bin/sh
# Lints the Quickshell config and the greeter with Qt 6 qmllint, failing only on findings that are real errors.
# Lints a staged copy with the qmldir files Quickshell generates at runtime, so singletons resolve.
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

copy_sources() {
  mkdir -p "$2"
  git ls-files -co --exclude-standard -- "$1" | while IFS= read -r file; do
    case $file in
    *.qml | *.js | *.mjs) [ -f "$file" ] && printf '%s\n' "${file#"$1"/}" ;;
    esac
  done | (cd "$1" && tar -cf - -T -) | tar -xf - -C "$2"
}

# Writes a qmldir per directory as Quickshell does: every capitalised .qml file is a type.
write_qmldirs() {
  find "$1" -type d | while IFS= read -r dir; do
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
  done
}

copy_sources "$qs_dir" "$stage/shell"
copy_sources "$greeter_dir" "$stage/greeter"
copy_sources "$qs_dir/lock/skins" "$stage/greeter/lock/skins"
cp "$qs_dir/lock/Tints.js" "$stage/greeter/lock/"
mkdir -p "$stage/greeter/theme"
cp "$qs_dir/theme/Theme.qml" "$qs_dir/theme/Style.qml" "$qs_dir/theme/Watch.js" "$stage/greeter/theme/"
write_qmldirs "$stage/shell"
write_qmldirs "$stage/greeter"

# Members read through parent, Loader.item and the like are typed QObject/QQuickItem, so a miss there is unknowable.
# shellcheck disable=SC2016
filter='
  .files[] | .filename as $file | .warnings[] | select(
    (.id | IN("syntax", "import", "duplicated-name", "duplicate-property-binding", "alias-cycle", "read-only-property"))
    or (.id == "missing-property"
      and (.message | test("not found on type \"(QObject|QQuickItem|QJSPrimitiveValue)\"") | not))
    or (.id == "unqualified" and .message == "Unqualified access" and ((.suggestions // []) | length) == 0)
  ) | "\($file):\(.line):\(.column): \(.message) [\(.id)]"
'

status=0
for tree in shell greeter; do
  case $tree in
  shell) prefix=$qs_dir depth=99 ;;
  greeter) prefix=$greeter_dir depth=1 ;;
  esac
  report="$stage/$tree.json"
  wanted=$(cd "$stage/$tree" && find . -maxdepth "$depth" -name '*.qml' | wc -l)
  (cd "$stage/$tree" && find . -maxdepth "$depth" -name '*.qml' -exec "$qmllint_bin" --ignore-settings --json - {} +) >"$report" 2>/dev/null
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
