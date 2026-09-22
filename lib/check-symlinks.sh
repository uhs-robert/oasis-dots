#!/bin/sh
# Fails when a tracked symlink dangles or points outside the repo.
# Paths resolve lexically, so a link through repos/ is judged by its own path, not the clone's.
# Links into a repos/ clone that is not set up yet are skipped: those arrive at install time.
set -u

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
cd "$repo_dir" || exit 1

git ls-files -s | sed -n 's/^120000 [^	]*	//p' | {
  status=0
  report() {
    printf '%s: %s\n' "$1" "$2" >&2
    status=1
  }

  while IFS= read -r link; do
    target=$(readlink "$link") || continue

    case "$target" in
    /*)
      resolved=$target
      # Absolute links (systemd units, wallpapers) are machine-specific by nature; only flag misses.
      [ -e "$resolved" ] || report 'broken symlink' "$link -> $target"
      continue
      ;;
    esac
    resolved=$(realpath -m -s -- "$(dirname -- "$link")/$target")

    case "$resolved" in
    "$repo_dir"/repos/* | "$repo_dir"/termux/repos/*)
      clone=$(printf '%s\n' "$resolved/" | sed 's|^\(.*/repos/[^/]*\)/.*|\1|')
      [ -e "$clone" ] || continue
      ;;
    "$repo_dir"/*) ;;
    *)
      report 'symlink leaves the repo' "$link -> $target"
      continue
      ;;
    esac

    [ -e "$resolved" ] || report 'broken symlink' "$link -> $target"
  done

  exit $status
}
