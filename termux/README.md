# Termux

Standalone mobile SSH environment for Termux.

## Install

In a fresh Termux session:

```sh
pkg update -y && pkg install -y git && git clone https://github.com/uhs-robert/dotfiles.git ~/dotfiles && bash ~/dotfiles/termux/install.sh
```

Already have the repo? Just run `bash ~/dotfiles/termux/install.sh` again.

Follow the prompts. When it's done, run `exec zsh`.

Add your SSH hosts in `~/.ssh/config` (`v ~/.ssh/config`), then copy your key to each server:

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub your-host-alias
```

Connect with `s` to fuzzy-pick a host, or `ssh alias` directly.

## Features

Kept minimal on purpose, no LSP, no autocomplete, no linters, just a fast terminal. But a few nice touches for readability on a phone screen:

- Nerd Font
- Dark theme (Oasis Night)
- `lsd` for readable `ls` output
- Fuzzy shell tab completion via `fzf-tab`
- Fastfetch on startup
- Neovim (LazyVim), Yazi, and LazyGit set up out of the box
- `up` uses topgrade to keep everything updated
