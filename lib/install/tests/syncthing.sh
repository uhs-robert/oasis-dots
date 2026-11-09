#!/usr/bin/env bash
# Tests setup_syncthing and the folder and peer steps against a scratch HOME, with stub tailscale, syncthing, systemctl,
# pacman and sudo commands. Nothing here installs or starts anything.
# shellcheck disable=SC2016  # the stub bodies are single-quoted on purpose: they expand when each stub runs
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

export DOTFILES_DIR="$repo_dir"
source "$repo_dir/lib/install/load.sh"

export HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/home/.config" SYNCTHING_HOME="$scratch/syncthing"
unset OPT_YES
mkdir -p "$HOME"

stubs="$scratch/bin"
mkdir -p "$stubs"
export PATH="$stubs:$PATH" calls="$scratch/calls"
stub() { printf '#!/usr/bin/env bash\necho "%s $*" >>"$calls"\n%s\n' "$1" "$2" >"$stubs/$1" && chmod +x "$stubs/$1"; }

stub tailscale '[[ -e $scratch/tailscale-down ]] || echo 100.64.0.7'
export scratch
stub sudo '"$@"'
stub pacman ':'
# A generated config holds this machine as the first device.
stub syncthing 'cat >"$SYNCTHING_HOME/config.xml" <<XML
<configuration version="51"><device id="SELF-ID" name="laptop"><address>dynamic</address></device><gui enabled="true"><address>127.0.0.1:8384</address></gui><options><listenAddress>default</listenAddress><globalAnnounceEnabled>true</globalAnnounceEnabled><localAnnounceEnabled>true</localAnnounceEnabled><relaysEnabled>true</relaysEnabled><natEnabled>true</natEnabled></options></configuration>
XML'
stub systemctl 'case "$1 $2" in "--user is-active") exit 1 ;; esac'

failures=0
case_name=''
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}
config="$SYNCTHING_HOME/config.xml"
has() { grep -qF -- "$1" "$2"; }
lacks() { ! grep -qF -- "$1" "$2"; }
called() { grep -qF -- "$1" "$calls"; }

# Two repos for the folder step, found through the roots file the way `plans` finds them.
mkdir -p "$scratch/dev/alpha/.git" "$scratch/dev/beta/.git" "$XDG_CONFIG_HOME/plans"
echo "$scratch/dev" >"$XDG_CONFIG_HOME/plans/roots"

case_name='no tailscale address writes nothing'
touch "$scratch/tailscale-down"
: >"$calls"
setup_syncthing <<<y >/dev/null 2>&1
check test ! -e "$config"
check test ! -e "$XDG_CONFIG_HOME/systemd"
check test -z "$(grep -vE "^tailscale " "$calls")"
rm "$scratch/tailscale-down"

case_name='under --yes it is skipped'
OPT_YES=1 setup_syncthing >/dev/null 2>&1
check test ! -e "$config"

case_name='setup writes a tailscale-only config'
setup_syncthing <<<y >/dev/null 2>&1
check has '<listenAddress>tcp://100.64.0.7:22000</listenAddress>' "$config"
check lacks '<listenAddress>default' "$config"
check has '<globalAnnounceEnabled>false' "$config"
check has '<localAnnounceEnabled>false' "$config"
check has '<relaysEnabled>false' "$config"
check has '<natEnabled>false' "$config"
check has '<address>127.0.0.1:8384</address>' "$config"
check called 'systemctl --user enable syncthing.service'
dropin="$XDG_CONFIG_HOME/systemd/user/syncthing.service.d/tailscale-retry.conf"
check has 'Restart=always' "$dropin"
check has 'RestartSec=10' "$dropin"

case_name='a second setup changes nothing'
sum_config=$(cksum <"$config")
sum_dropin=$(cksum <"$dropin")
: >"$calls"
setup_syncthing <<<y >/dev/null 2>&1
check test "$(cksum <"$config")" = "$sum_config"
check test "$(cksum <"$dropin")" = "$sum_dropin"
check test "$(grep -c daemon-reload "$calls")" = 0

case_name='peer is reached at its tailscale address'
syncthing_add_peer PEER-ID-1234567 100.64.0.9 >/dev/null
check has 'tcp://100.64.0.9:22000' "$config"
check lacks 'tcp://100.64.0.9:22000</address><address' "$config"

case_name='folders: two per repo with the ignore files'
syncthing_add_folders >/dev/null 2>&1
for repo in alpha beta; do
  check has "id=\"$repo-plans\"" "$config"
  check has "id=\"$repo-logs\"" "$config"
  check has "path=\"$scratch/dev/$repo/.plans\"" "$config"
  check has '.*.tmp' "$scratch/dev/$repo/.plans/.stignore"
  check test "$(wc -l <"$scratch/dev/$repo/.plans/.stignore")" = 1
  for line in '.*.tmp' '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webm' '*.mp4' '*.mov'; do
    check grep -qxF -- "$line" "$scratch/dev/$repo/.logs/.stignore"
  done
  check test "$(wc -l <"$scratch/dev/$repo/.logs/.stignore")" = 8
  check lacks 'sync-conflict' "$scratch/dev/$repo/.logs/.stignore"
done
check has 'type="simple"' "$config"
check has 'key="keep" val="5"' "$config"
check test "$(grep -o 'type="simple"' "$config" | wc -l)" = 4
check has 'id="PEER-ID-1234567"' "$config"

case_name='a second folder run changes nothing'
sum_config=$(cksum <"$config")
sum_ignore=$(cksum <"$scratch/dev/alpha/.logs/.stignore")
syncthing_add_folders >/dev/null 2>&1
check test "$(cksum <"$config")" = "$sum_config"
check test "$(cksum <"$scratch/dev/alpha/.logs/.stignore")" = "$sum_ignore"

case_name='the config names no non-tailscale address'
# Every tcp address is the tailscale one or the peer's; the only other addresses are the GUI and the self "dynamic".
bad=$(grep -oE 'tcp://[^<]+' "$config" | grep -vE '^tcp://100\.64\.0\.[0-9]+:22000$' || true)
check test -z "$bad"
check lacks 'relays.syncthing.net' "$config"
check lacks 'announce.syncthing.net' "$config"

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "syncthing: ok"
