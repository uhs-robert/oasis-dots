#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

platform_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }
command -v pkg >/dev/null && [[ -n "${PREFIX:-}" && -x "$PREFIX/bin/termux-reload-settings" ]] ||
    fail 'Run this installer inside Termux (not a proot distribution).'
[[ ${XDG_CONFIG_HOME:-$HOME/.config} == "$HOME/.config" ]] ||
    fail 'This Stow profile requires XDG_CONFIG_HOME to be unset or ~/.config.'

pkg update -y
mapfile -t packages < "$platform_dir/packages.txt"
pkg install -y "${packages[@]}"
# No packaged autosuggestions in the main repository at time of writing.
if apt-cache show zsh-autosuggestions >/dev/null 2>&1; then
    pkg install -y zsh-autosuggestions
fi

stow_packages=(zsh ssh neovim yazi lazygit topgrade termux)
stow_args=(--dir="$platform_dir" --target="$HOME" --no-folding)
# Check the whole deployment before linking any package. Never use --adopt.
stow "${stow_args[@]}" --simulate "${stow_packages[@]}" ||
    fail 'Stow conflict: back up and move the reported files, then rerun.'
stow "${stow_args[@]}" "${stow_packages[@]}"
bash "$HOME/.local/bin/termux-update-font"

clone_plugin() {
    local name=$1 url=$2 destination="$HOME/.local/share/zsh/plugins/$1"
    if exists "$destination"; then
        [[ -d "$destination/.git" ]] || fail "$destination exists but is not a Git checkout."
        [[ $(git -C "$destination" remote get-url origin) == "$url" ]] ||
            fail "$destination has a different origin; leaving it untouched."
    else
        mkdir -p -- "$(dirname -- "$destination")"
        git clone --depth 1 -- "$url" "$destination"
    fi
}
clone_plugin fzf-tab https://github.com/Aloxaf/fzf-tab.git
if [[ ! -f "$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    clone_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git
fi

# Mutable manifests stay local instead of writing through a Stow symlink.
manifest="$HOME/.config/yazi/package.toml"
if ! exists "$manifest"; then
    cp -- "$platform_dir/yazi/.config/yazi/package.toml" "$manifest"
fi
ya pkg install
nvim --headless '+Lazy! sync' +qa

mkdir -p -- "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! exists "$HOME/.ssh/config"; then
    (umask 077; cp -- "$HOME/.ssh/config.example" "$HOME/.ssh/config")
fi

# Detect public keys and private keys with nonstandard names too.
shopt -s nullglob dotglob
public_keys=("$HOME"/.ssh/*.pub)
private_keys=()
for candidate in "$HOME"/.ssh/*; do
    if [[ -f "$candidate" ]] && grep -qE '^-----BEGIN .*PRIVATE KEY-----' "$candidate"; then
        private_keys+=("$candidate")
    fi
done
if (( ${#public_keys[@]} == 0 && ${#private_keys[@]} == 0 )); then
    exists "$HOME/.ssh/id_ed25519" && fail '~/.ssh/id_ed25519 exists; refusing to replace it.'
    # Interactive passphrase prompt; do not silently create an unencrypted key.
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519"
    public_keys=("$HOME/.ssh/id_ed25519.pub")
fi

chsh -s zsh
termux-reload-settings
printf '\nSSH public key(s) — add the appropriate key to your server:\n'
if (( ${#public_keys[@]} )); then
    for key in "${public_keys[@]}"; do
        printf '\n%s\n' "$key"
        cat -- "$key"
    done
else
    for key in "${private_keys[@]}"; do
        printf '\nPublic key for %s (may ask for its passphrase):\n' "$key"
        ssh-keygen -y -f "$key"
    done
fi
printf '\nReady. Edit ~/.ssh/config, then run: exec zsh\n'
