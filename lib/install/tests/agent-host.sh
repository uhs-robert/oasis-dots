#!/usr/bin/env bash
# Tests the agent-host profile: the package manifest it adds, setup_agent_host and the seed script, against a scratch HOME
# with stub loginctl, systemctl, pacman, sudo and ssh commands. Nothing here touches the real systemd, linger or ~/.config.
# shellcheck disable=SC2016  # the stub bodies are single-quoted on purpose: they expand when each stub runs
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

export DOTFILES_DIR="$repo_dir"
source "$repo_dir/lib/install/load.sh"

export HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/home/.config" USER=tester GITHUB_DIR="$scratch/dev"
mkdir -p "$HOME"

stubs="$scratch/bin"
mkdir -p "$stubs"
export PATH="$stubs:$PATH" calls="$scratch/calls"
stub() { printf '#!/usr/bin/env bash\necho "%s $*" >>"$calls"\n%s\n' "$1" "$2" >"$stubs/$1" && chmod +x "$stubs/$1"; }
stub loginctl ':'
stub systemctl ':'
stub sudo ''
stub pacman ''
# do_stow would link into the scratch HOME from the real checkout; the case that needs it checks only that it is called.
do_stow() { echo "do_stow $*" >>"$calls"; }

failures=0
case_name=''
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}
called() { grep -qF -- "$1" "$calls"; }

# The packages install_packages passes to pacman, with the platform and the manifest reads of this machine faked.
installed_packages() {
  : >"$calls"
  DISTRO=arch
  install_with_retry() { shift && echo "$*" >"$scratch/installed"; }
  check_quickshell_version() { :; }
  install_packages >/dev/null
  cat "$scratch/installed"
}

case_name='--server alone does not read agent-host.ini'
server_only=$(OPT_SERVER=1 OPT_AGENT_HOST=0 installed_packages)
check test "${server_only#* }" != ''
for name in labwc hyprland quickshell grim wtype firefox; do
  check test "${server_only/ $name / }" = "${server_only}"
done

case_name='--agent-host adds the manifest on top of the server packages'
agent=$(OPT_SERVER=1 OPT_AGENT_HOST=1 installed_packages)
for name in labwc hyprland quickshell grim wtype firefox; do
  check grep -qw -- "$name" <<<"$agent"
done
check grep -qw -- rsync <<<"$agent"

case_name='the manifest holds only the names the plan lists'
check test "$(read_pkgs agent-host.ini | sort | tr '\n' ' ')" = 'firefox grim hyprland labwc quickshell wtype '

mkdir -p "$XDG_CONFIG_HOME/systemd/user"
touch "$XDG_CONFIG_HOME/systemd/user/plans-serve.service"
dropin="$XDG_CONFIG_HOME/systemd/user/plans-serve.service.d/agent-host.conf"
roots="$XDG_CONFIG_HOME/plans/roots"

case_name='setup installs the drop-in, the roots file, linger and the unit'
: >"$calls"
setup_agent_host >/dev/null 2>&1
check test "$?" -eq 0
check grep -qx 'WantedBy=default.target' "$dropin"
check test "$(grep -c PartOf "$dropin")" = 0
check test "$(cat "$roots")" = "$scratch/dev"$'\n'"$repo_dir"
check called 'loginctl enable-linger tester'
check called 'systemctl --user daemon-reload'
check called 'systemctl --user enable --now plans-serve.service'
check test ! -e "$XDG_CONFIG_HOME/systemd/user/default.target.wants"

case_name='it enables no unit but plans-serve'
check test "$(grep -c 'systemctl --user enable' "$calls")" = 1
check test "$(grep -c 'systemctl --user enable' "$calls")" = "$(grep -c 'enable --now plans-serve.service' "$calls")"
check test "$(grep -c graphical "$calls")" = 0

case_name='a rerun changes nothing and keeps an edited roots file'
echo "$scratch/mine" >"$roots"
sum_dropin=$(cksum <"$dropin")
: >"$calls"
setup_agent_host >/dev/null 2>&1
check test "$(cksum <"$dropin")" = "$sum_dropin"
check test "$(cat "$roots")" = "$scratch/mine"
check test "$(grep -c daemon-reload "$calls")" = 0

case_name='a missing stowed unit is stowed first'
rm "$XDG_CONFIG_HOME/systemd/user/plans-serve.service"
: >"$calls"
(setup_agent_host >/dev/null 2>&1)
check called 'do_stow plans'

case_name='a stow that leaves no unit stops setup with a message'
: >"$calls"
out=$(setup_agent_host 2>&1)
check test "$?" -ne 0
check test "${out#*Could not stow plans}" != "$out"
check test "$(grep -c 'systemctl --user enable' "$calls")" = 0

# The seed runs rsync for real. The ssh stub drops the options and host, then runs the remote command here in a
# scratch home, so the destination is local. It records its arguments to pin RemoteCommand=none.
remote="$scratch/remote"
mkdir -p "$remote"
export remote
stub ssh 'while [[ $1 == -o ]]; do shift 2; done
shift
cd "$remote" && exec sh -c "$*"'

src="$HOME"
# The paths are the ones .claude/skills/shadow/shadow.sh reads: state JSON and hypr/theme, the checkout's audio, user fonts.
export AGENT_HOST_CHECKOUT="$src/dotfiles"
audio_dir=dotfiles/home/quickshell/.config/quickshell/features/lock/skins/ff7/audio
mkdir -p "$remote/dotfiles/.git" "$src/.local/state/quickshell" "$src/.local/state/hypr" "$src/$audio_dir" "$src/.local/share/fonts/MapleMono" \
  "$src/.config/quickshell/features/lock/skins/ff7/audio"
echo '{}' >"$src/.local/state/quickshell/bars.json"
echo '{"unit":"x"}' >"$src/.local/state/quickshell/weather.local.json"
echo 'not json' >"$src/.local/state/quickshell/cache.txt"
echo '{}' >"$src/.local/state/hypr/apps.json"
echo desert >"$src/.local/state/hypr/theme"
echo wav >"$src/$audio_dir/buzzer.wav"
echo wav >"$src/.config/quickshell/features/lock/skins/ff7/audio/stray.wav"
echo font >"$src/.local/share/fonts/MapleMono/a.ttf"

case_name='the seed copies the state, theme, audio and fonts, and never weather.local.json'
: >"$calls"
"$repo_dir/lib/install/agent-host-seed" nightshift >/dev/null 2>&1
check test "$?" -eq 0
check test -e "$remote/.local/state/quickshell/bars.json"
check test -e "$remote/.local/state/hypr/apps.json"
check test -e "$remote/.local/state/hypr/theme"
check test -e "$remote/$audio_dir/buzzer.wav"
check test ! -e "$remote/.config"
check test -e "$remote/.local/share/fonts/MapleMono/a.ttf"
check test ! -e "$remote/.local/state/quickshell/weather.local.json"
check test ! -e "$remote/.local/state/quickshell/cache.txt"
check test -z "$(find "$remote" -name 'weather.local.json')"

case_name='the seed connects with RemoteCommand=none and RequestTTY=no every time'
check test "$(grep -c '^ssh ' "$calls")" -ge 4
check test "$(grep '^ssh ' "$calls" | grep -vc 'RemoteCommand=none -o RequestTTY=no')" = 0

case_name='no checkout on the host skips the audio and creates no tree'
rm -rf "$remote" && mkdir -p "$remote"
out=$("$repo_dir/lib/install/agent-host-seed" nightshift 2>&1)
check test "$?" -eq 0
check test "${out#*skip the FF7 audio}" != "$out"
check test ! -e "$remote/dotfiles"
check test -e "$remote/.local/state/hypr/apps.json"
mkdir -p "$remote/dotfiles/.git"
"$repo_dir/lib/install/agent-host-seed" nightshift >/dev/null 2>&1
check test -e "$remote/$audio_dir/buzzer.wav"

case_name='a rerun never overwrites what the host has since changed'
echo kept >"$remote/.local/state/hypr/apps.json"
"$repo_dir/lib/install/agent-host-seed" nightshift >/dev/null 2>&1
check test "$(cat "$remote/.local/state/hypr/apps.json")" = kept

case_name='a missing source directory is skipped, not an error'
rm -rf "$src/.local/share/fonts" "$remote/.local/share"
"$repo_dir/lib/install/agent-host-seed" nightshift >/dev/null 2>&1
check test "$?" -eq 0
check test ! -e "$remote/.local/share/fonts"

case_name='the seed needs a host'
check test "$("$repo_dir/lib/install/agent-host-seed" 2>&1 >/dev/null | grep -c usage)" = 1

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "agent-host: ok"
