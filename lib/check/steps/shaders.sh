#!/bin/sh
# Checks that every tracked Quickshell shader's committed .qsb is what its .frag compiles to; `--write` rebuilds them
# in place (`just shaders`). Rebuilding and comparing bytes needs no stored hash: qsb is deterministic, and it drops
# comments and whitespace while compiling, so editing only those leaves the .qsb unchanged and the check passing.
#
# SHADER_ROOT points the script at another tree (the tests use a scratch one); QSB overrides the compiler.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=${SHADER_ROOT:-$(CDPATH='' cd -- "$script_dir/../../.." && pwd)}

# The one definition of the build. qsb is in Qt's private bin dir, off PATH on Arch. The flags equal `qsb --qt6`.
qsb_default=/usr/lib/qt6/bin/qsb
qsb_flags='--glsl "100es,120,150" --hlsl 50 --msl 12'

write=0
case ${1-} in
--write) write=1 ;;
'') ;;
*)
  echo "usage: shaders.sh [--write]" >&2
  exit 2
  ;;
esac

if [ -n "${QSB-}" ]; then
  qsb=$QSB
elif qsb=$(command -v qsb); then
  :
else
  qsb=$qsb_default
fi

cd "$root" || exit 1
shaders=$(git ls-files -- '*.frag')
failed=0

# The `// Rebuild:` header on each .frag is documentation for whoever opens it; keep it equal to the command run here.
for frag in $shaders; do
  name=${frag##*/}
  expected="// Rebuild: $qsb_default $qsb_flags -o $name.qsb $name"
  [ "$(head -n 1 -- "$frag")" = "$expected" ] || {
    printf 'FAIL %s: first line is not the command shaders.sh runs; it should be\n  %s\n' "$frag" "$expected"
    failed=1
  }
done

if [ ! -x "$qsb" ]; then
  if [ "$write" = 1 ]; then
    echo 'shaders: qsb not found (install qt6-shadertools)' >&2
    exit 1
  fi
  echo 'skip: qsb not installed (qt6-shadertools)'
  exit "$failed"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/shaders.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

n=0
for frag in $shaders; do
  n=$((n + 1))
  name=${frag##*/}
  built=$tmp/$n.qsb
  # Run from the shader's directory, as the header says, so no path leaks into the output.
  if ! out=$(cd "$(dirname -- "$frag")" && eval "\"\$qsb\" $qsb_flags -o \"\$built\" \"\$name\"" 2>&1); then
    printf 'FAIL %s: qsb could not compile it\n%s\n' "$frag" "$out"
    failed=1
    continue
  fi
  if [ "$write" = 1 ]; then
    cmp -s -- "$built" "$frag.qsb" || cp -- "$built" "$frag.qsb"
  elif [ ! -f "$frag.qsb" ]; then
    printf 'FAIL %s: no %s.qsb (run: just shaders)\n' "$frag" "$name"
    failed=1
  elif ! cmp -s -- "$built" "$frag.qsb"; then
    printf 'FAIL %s: %s.qsb is stale (run: just shaders, then commit it)\n' "$frag" "$name"
    failed=1
  fi
done

exit "$failed"
