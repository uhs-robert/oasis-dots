#!/usr/bin/env bash
# Tests pacman_conf_tweaked and apply_pacman_conf_tweaks against scratch copies of pacman.conf, with no sudo and no real /etc.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/pacman.sh"
export PACMAN_TWEAKS_SUDO=''

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

# Everything outside [options], to prove no other section changes.
outside_options() { awk '/^[[:space:]]*\[/ { in_options = ($0 ~ /^\[options\]/) } !in_options' "$1"; }
options_lines() { awk '/^[[:space:]]*\[/ { in_options = ($0 ~ /^\[options\]/); next } in_options && NF' "$1"; }
count() { grep -cxE "$2" "$1"; }

stock_conf() {
  cat <<'CONF'
# /etc/pacman.conf
[options]
HoldPkg     = pacman glibc
Architecture = auto

# Misc options
#UseSyslog
#Color
#NoProgressBar
CheckSpace
#VerbosePkgLists
#ParallelDownloads = 5
#DownloadUser = alpm

[core]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
CONF
}

case_name='stock conf gains every setting'
stock_conf >"$scratch/stock"
cp "$scratch/stock" "$scratch/stock.orig"
apply_pacman_conf_tweaks "$scratch/stock" >/dev/null 2>&1
check test "$(count "$scratch/stock" 'Color')" = 1
check test "$(count "$scratch/stock" 'ILoveCandy')" = 1
check test "$(count "$scratch/stock" 'VerbosePkgLists')" = 1
check test "$(count "$scratch/stock" 'ParallelDownloads = 10')" = 1
check test "$(count "$scratch/stock" '#?ParallelDownloads.*')" = 1
check test "$(outside_options "$scratch/stock")" = "$(outside_options "$scratch/stock.orig")"

case_name='second run changes nothing'
cp "$scratch/stock" "$scratch/stock.once"
output=$(apply_pacman_conf_tweaks "$scratch/stock" 2>&1)
check cmp -s "$scratch/stock" "$scratch/stock.once"
check grep -q 'already tweaked' <<<"$output"

case_name='an already tweaked conf is untouched'
cp "$scratch/stock.once" "$scratch/tweaked"
before=$(stat -c %i-%Y "$scratch/tweaked")
apply_pacman_conf_tweaks "$scratch/tweaked" >/dev/null 2>&1
check test "$(stat -c %i-%Y "$scratch/tweaked")" = "$before"

case_name='a higher ParallelDownloads is kept'
sed 's/^#ParallelDownloads = 5/ParallelDownloads = 20/' "$scratch/stock.orig" >"$scratch/high"
apply_pacman_conf_tweaks "$scratch/high" >/dev/null 2>&1
check test "$(count "$scratch/high" 'ParallelDownloads = 20')" = 1
check test "$(count "$scratch/high" 'ParallelDownloads.*')" = 1
check test "$(count "$scratch/high" 'Color')" = 1

case_name='a lower ParallelDownloads is raised'
sed 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' "$scratch/stock.orig" >"$scratch/low"
apply_pacman_conf_tweaks "$scratch/low" >/dev/null 2>&1
check test "$(count "$scratch/low" 'ParallelDownloads = 10')" = 1
check test "$(count "$scratch/low" 'ParallelDownloads.*')" = 1

case_name='settings in other sections are not edited or counted'
cat >"$scratch/other" <<'CONF'
[options]
CheckSpace

[custom]
#Color
ParallelDownloads = 1
CONF
apply_pacman_conf_tweaks "$scratch/other" >/dev/null 2>&1
check test "$(outside_options "$scratch/other")" = "$(printf '[custom]\n#Color\nParallelDownloads = 1')"
check test "$(options_lines "$scratch/other" | tr '\n' ' ')" = 'CheckSpace Color ILoveCandy VerbosePkgLists ParallelDownloads = 10 '

case_name='the shipped makepkg drop-in disables only debug'
dropin=$repo_dir/system/etc/makepkg.conf.d/oasis.conf
dropin_result=$(bash -c 'OPTIONS=(strip docs "!libtool" debug lto); source "$1"; echo "$MAKEFLAGS|${OPTIONS[*]}"' _ "$dropin")
check test "$dropin_result" = "-j$(nproc)|strip docs !libtool !debug lto"
dropin_again=$(bash -c 'OPTIONS=(strip "!debug"); source "$1"; echo "${OPTIONS[*]}"' _ "$dropin")
check test "$dropin_again" = 'strip !debug'

((failures == 0)) && echo "pacman-tweaks: all passed"
exit $((failures > 0))
