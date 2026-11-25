#!/usr/bin/env bash
# Tests migrate_retire_tbkeys on a scratch root and HOME, never on the real system. A fake sudo logs each call and can fail on demand.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/migrate.sh"

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

# Stands in for sudo: logs the call, fails when the target path ends in $FAKE_SUDO_FAIL_ON, else runs the command.
fake_sudo="$scratch/fake-sudo"
cat >"$fake_sudo" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_SUDO_LOG"
[[ -n "${FAKE_SUDO_FAIL_ON:-}" && "${*: -1}" == *"$FAKE_SUDO_FAIL_ON" ]] && exit 1
exec "$@"
FAKE
chmod +x "$fake_sudo"
export FAKE_SUDO_LOG="$scratch/sudo.log"
export BETTERBIRD_SUDO=$fake_sudo

make_root() {
  local r=$1 f
  mkdir -p "$r/etc/pacman.d/hooks" "$r/usr/local/bin" "$r/opt/betterbird/defaults/pref" "$r/usr/local/share/betterbird-autoconfig" "$r/home/.config"
  for f in "${_TBKEYS_ROOT_FILES[@]}"; do : >"$r$f"; done
}
home_for() { printf '%s/home' "$1"; }

case_name='removes every root file and the share dir, keeping what the package owns'
r=$scratch/a
make_root "$r"
: >"$r/opt/betterbird/betterbird-bin"
HOME=$(home_for "$r") migrate_retire_tbkeys "$r" >/dev/null 2>&1
for f in "${_TBKEYS_ROOT_FILES[@]}"; do check test ! -e "$r$f"; done
check test ! -d "$r/usr/local/share/betterbird-autoconfig"
check test -e "$r/opt/betterbird/betterbird-bin"

case_name='the pref goes before the cfg it names'
check test "$(grep -n 'autoconfig.js$' "$FAKE_SUDO_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n 'opt/betterbird/betterbird.cfg$' "$FAKE_SUDO_LOG" | cut -d: -f1)"

case_name='a second run is a silent no-op and never calls sudo'
: >"$FAKE_SUDO_LOG"
output=$(HOME=$(home_for "$r") migrate_retire_tbkeys "$r" 2>&1)
check test -z "$output"
check test ! -s "$FAKE_SUDO_LOG"

case_name='a machine with nothing to remove is a no-op'
mkdir -p "$scratch/empty/home"
output=$(HOME="$scratch/empty/home" migrate_retire_tbkeys "$scratch/empty" 2>&1)
check test -z "$output"

case_name='a failed pref removal leaves the cfg in place, never cfg-only'
r=$scratch/b
make_root "$r"
FAKE_SUDO_FAIL_ON=pref/autoconfig.js HOME=$(home_for "$r") migrate_retire_tbkeys "$r" >/dev/null 2>&1
check test -e "$r/opt/betterbird/defaults/pref/autoconfig.js"
check test -e "$r/opt/betterbird/betterbird.cfg"

case_name='dry run changes nothing'
r=$scratch/c
make_root "$r"
ln -s ../dotfiles/missing "$r/home/.config/tbkeys"
before=$(find "$r" | sort)
MIGRATE_DRY_RUN=1 HOME=$(home_for "$r") migrate_retire_tbkeys "$r" >/dev/null 2>&1
check test "$(find "$r" | sort)" = "$before"

case_name='a dangling ~/.config/tbkeys link is removed'
r=$scratch/d
mkdir -p "$r/home/.config"
ln -s ../dotfiles/missing "$r/home/.config/tbkeys"
HOME=$(home_for "$r") migrate_retire_tbkeys "$r" >/dev/null 2>&1
check test ! -L "$r/home/.config/tbkeys"

case_name='a link that still resolves and a real directory are kept'
r=$scratch/e
mkdir -p "$r/home/.config/real" "$r/home/target"
ln -s ../target "$r/home/.config/tbkeys"
HOME=$(home_for "$r") migrate_retire_tbkeys "$r" >/dev/null 2>&1
check test -L "$r/home/.config/tbkeys"
rm "$r/home/.config/tbkeys"
mv "$r/home/.config/real" "$r/home/.config/tbkeys"
HOME=$(home_for "$r") migrate_retire_tbkeys "$r" >/dev/null 2>&1
check test -d "$r/home/.config/tbkeys"

[[ $failures -eq 0 ]] && echo "migrate-retire-tbkeys: all passed"
exit $((failures > 0))
