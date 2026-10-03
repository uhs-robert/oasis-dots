#!/bin/sh
set -eu

# Resolve manifests relative to the repository, not the caller's directory.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
pkg_dir="$repo_dir/packages"

# Every manifest in packages/ lists OS/language package names, except these two:
# stow.ini names dotfile directories and repos.ini names git repositories, so a
# name shared with a real package there is not a duplicate.
set --
for manifest in "$pkg_dir"/*.ini; do
  case "${manifest##*/}" in
  stow.ini | repos.ini) continue ;;
  esac
  set -- "$@" "$manifest"
done

if [ "$#" -eq 0 ]; then
  echo "No package manifests found in $pkg_dir" >&2
  exit 1
fi

packages=$(
  awk '
    /^[[:space:]]*($|#|\[)/ { next }
    { print $1 }
  ' "$@"
) || {
  echo "Failed to read package manifests" >&2
  exit 1
}

duplicates=$(printf '%s\n' "$packages" | sort | uniq -d)

if [ -n "$duplicates" ]; then
  printf 'Duplicate package declarations:\n%s\n' "$duplicates" >&2
  exit 1
fi

# home/ dirs that are not stow packages: phone and browser imports, personal images, and a package awaiting a manifest.
unstowed="android images org.freedesktop.FileManager1.common tabliss vimium"

stow_entries=$(awk '/^[[:space:]]*($|#|\[)/ { next } { print $1 }' "$pkg_dir/stow.ini" | sort -u)

status=0
for entry in $stow_entries; do
  [ -d "$repo_dir/home/$entry" ] && continue
  echo "stow.ini lists $entry but home/$entry does not exist" >&2
  status=1
done
for dir in $(git -C "$repo_dir" ls-files home | cut -d/ -f2 | sort -u); do
  case " $unstowed " in *" $dir "*) continue ;; esac
  printf '%s\n' "$stow_entries" | grep -qx -- "$dir" && continue
  echo "home/$dir is not listed in stow.ini" >&2
  status=1
done
exit "$status"
