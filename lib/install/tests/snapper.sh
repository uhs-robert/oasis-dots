#!/usr/bin/env bash
# Tests setup_snapper against a scratch tree, with stub snapper, btrfs, mount and systemctl commands and no sudo.
# shellcheck disable=SC2016  # the stub bodies are single-quoted on purpose: they expand when each stub runs
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/common/packages.sh"
source "$repo_dir/lib/install/snapper.sh"
export PKG_DIR="$repo_dir/packages" SNAPPER_SUDO='' OPT_YES=1 USER=tester

# Each stub logs its argv to $calls, and keeps the state it fakes as files under $state.
stubs="$scratch/bin"
mkdir -p "$stubs"
export PATH="$stubs:$PATH" calls="$scratch/calls" state="$scratch/state"
stub() { printf '#!/usr/bin/env bash\necho "%s $*" >>"$calls"\n%s\n' "$1" "$2" >"$stubs/$1" && chmod +x "$stubs/$1"; }

stub pacman ':'
stub mountpoint '[[ -e $state/mounted ]]'
stub umount '[[ ! -e $state/umount-fails ]] && rm -f "$state/mounted"'
stub mount 'touch "$state/mounted"'
stub findmnt 'case "$*" in *FSTYPE*) cat "$state/fstype" ;; *SOURCE*) echo /dev/fake ;; *FSROOT*) echo /@snapshots ;; esac'
# Like the real one, create-config refuses an existing .snapshots and writes the stock template's values.
stub snapper '
case "$*" in
*create-config*)
  [[ ! -e $state/create-fails && ! -e $SNAPPER_SUBVOLUME/.snapshots ]] || exit 1
  mkdir "$SNAPPER_SUBVOLUME/.snapshots"
  printf "%s\n" "QGROUP=\"\"" "ALLOW_USERS=\"\"" "NUMBER_LIMIT=\"50\"" "TIMELINE_LIMIT_HOURLY=\"10\"" >"$SNAPPER_CONFIG_DIR/root" ;;
*set-config*)
  shift 3
  for setting in "$@"; do
    key=${setting%%=*}
    sed -i "/^$key=/d" "$SNAPPER_CONFIG_DIR/root"
    echo "$key=\"${setting#*=}\"" >>"$SNAPPER_CONFIG_DIR/root"
  done ;;
esac'
stub btrfs '
case "$*" in
"subvolume delete"*) rmdir "$3" ;;
"qgroup show"*) [[ -e $state/quotas ]] ;;
"quota disable"*) rm -f "$state/quotas" ;;
esac'
stub systemctl 'case "$1" in is-enabled) [[ -e $state/timer-$2 ]] ;; enable) for t in "${@:3}"; do touch "$state/timer-$t"; done ;; esac'

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}
called() { grep -qF -- "$1" "$calls"; }
not_called() { ! called "$1"; }

# A fresh / on btrfs, with no snapper config. $1 "mounted" gives .snapshots its own subvolume mount.
fresh_root() {
  rm -rf "$scratch/root" "$scratch/configs" "$state" "$calls"
  mkdir -p "$scratch/root" "$scratch/configs" "$state"
  touch "$calls"
  echo btrfs >"$state/fstype"
  export SNAPPER_SUBVOLUME="$scratch/root" SNAPPER_CONFIG_DIR="$scratch/configs"
  if [[ ${1:-} == mounted ]]; then
    mkdir "$scratch/root/.snapshots"
    touch "$state/mounted"
  fi
}
run_setup() { setup_snapper >/dev/null 2>&1; }
setup_fails() { ! run_setup; }

case_name='not btrfs skips everything'
fresh_root
echo ext4 >"$state/fstype"
check run_setup
check not_called pacman
check not_called snapper

case_name='nested .snapshots: create-config, limits, timers'
fresh_root
check run_setup
check called 'pacman -S --needed --noconfirm snapper snap-pac'
check called "create-config $scratch/root"
check not_called umount
check grep -qx 'ALLOW_USERS="tester"' "$scratch/configs/root"
check grep -qx 'NUMBER_LIMIT="20"' "$scratch/configs/root"
check grep -qx 'TIMELINE_LIMIT_YEARLY="5"' "$scratch/configs/root"
check test -e "$state/timer-snapper-timeline.timer"
check test -e "$state/timer-snapper-cleanup.timer"

case_name='only the differing settings are written'
check not_called 'set-config QGROUP='
check not_called 'TIMELINE_LIMIT_HOURLY=10'

case_name='separate .snapshots mount: lifted for create-config and put back'
fresh_root mounted
check run_setup
check called "umount $scratch/root/.snapshots"
check called "create-config $scratch/root"
check called "btrfs subvolume delete $scratch/root/.snapshots"
check called "mount -o subvol=/@snapshots /dev/fake $scratch/root/.snapshots"
check test -d "$scratch/root/.snapshots"
check test -e "$state/mounted"

case_name='second run changes nothing'
: >"$calls"
check run_setup
check not_called create-config
check not_called set-config
check not_called 'quota disable'
check not_called 'systemctl enable'

case_name='quotas on are turned off'
touch "$state/quotas"
check run_setup
check called "btrfs quota disable $scratch/root"
check test ! -e "$state/quotas"

case_name='failed unmount stops before touching .snapshots'
fresh_root mounted
touch "$state/umount-fails"
check setup_fails
check not_called create-config
check test -d "$scratch/root/.snapshots"

case_name='snapshots left in .snapshots stop it'
fresh_root mounted
rm "$state/mounted"
touch "$scratch/root/.snapshots/1"
touch "$state/mounted"
check setup_fails
check not_called create-config
check test -e "$scratch/root/.snapshots/1"
check test -e "$state/mounted"

case_name='failed create-config puts the mount back'
fresh_root mounted
touch "$state/create-fails"
check setup_fails
check test -d "$scratch/root/.snapshots"
check test -e "$state/mounted"
check not_called 'subvolume delete'
check not_called 'systemctl enable'

((failures == 0)) && echo "snapper: all passed"
((failures == 0))
