<p align="center">
  <img
    src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/logo.png"
    width="auto" height="128" alt="Oasis logo" />
</p>
<h1 align="center">oasis-dots</h1>
<p align="center">
  <a href="https://github.com/uhs-robert/oasis-dots/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/oasis-dots?colorA=192330&colorB=khaki&style=for-the-badge&cacheSeconds=4300" alt="Stargazers"></a>
  <a href="https://github.com/uhs-robert/oasis-dots/issues"><img src="https://img.shields.io/github/issues/uhs-robert/oasis-dots?colorA=192330&colorB=skyblue&style=for-the-badge&cacheSeconds=4300" alt="Issues"></a>
  <a href="https://github.com/uhs-robert/oasis-dots/graphs/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/oasis-dots?colorA=192330&colorB=8FD1C7&style=for-the-badge&cacheSeconds=4300" alt="Contributors"></a>
  <a href="https://github.com/uhs-robert/oasis-dots/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/oasis-dots?colorA=192330&colorB=C799FF&style=for-the-badge&cacheSeconds=4300" alt="Forks"></a>
  <a href="https://discord.gg/b7y5CGVGTB"><img src="https://img.shields.io/discord/1554625284068741140?label=discord&logo=discord&logoColor=white&colorA=192330&colorB=5865F2&style=for-the-badge&cacheSeconds=4300" alt="Discord"></a>
</p>
<p align="center">Oasis-themed dotfiles for Arch Linux and Hyprland using Quickshell.</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/hero.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/hero.webp" width="100%" alt="Switching styles, the Leader menu, the overview and the Duck Hunt region selector"></a>
</p>

## 🖥️ Overview

An Arch Linux desktop on Hyprland, driven from the keyboard with vim binds and modes.

- [Hyprland](home/hypr/.config/hypr/README.md), configured in Lua, with [HyprVim](https://github.com/uhs-robert/hyprvim) for Vim-modal window management and which-key hints.
- A [Quickshell](home/quickshell/.config/quickshell/README.md) desktop shell: per-monitor bars, popups, notifications, pickers, a workspace overview, a Settings panel and the lock screen.
  - It comes in swappable styles, from a clean modern look to different retro gaming eras.
- [Oasis](https://github.com/uhs-robert/oasis.nvim) color themes across everything.
- A greetd login screen that reuses the lock screen's look, with tuigreet as a fallback.

> [!NOTE]
> Managed with [GNU Stow](https://www.gnu.org/software/stow/); packages live under `home/`.

## 🌴 Why oasis-dots

### Keyboard first, for Vim users

No mouse required. [HyprVim](https://github.com/uhs-robert/hyprvim) gives Hyprland Vim modes, a leader key and which-key hints. Every popup opens on a key and answers to the same keys (`j`/`k`, `h`/`l`, `gg`/`G`, `/`, `[`/`]`, `?`, `q`), and the pickers have INSERT and NORMAL modes. Even the pointer jobs go through the keyboard: a virtual cursor, a screenshot region selector that you steer with `hjkl` across monitors, the workspace overview, and monitor arrangements in Settings. The apps follow suit: Neovim, tmux, Yazi, qutebrowser, Tridactyl and Betterbird with tbkeys.

<p align="center">
  <a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/region-styles.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/region-styles.webp" width="100%" alt="The region selector, steered with hjkl, in twelve styles"></a>
</p>

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/keybinds.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/keybinds.webp" width="100%" alt="Keybinds picker"></a><br><strong>Keybinds picker</strong><br><em>SUPER + / searches and runs the binds of the current mode</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/emoji.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/emoji.webp" width="100%" alt="Emoji picker"></a><br><strong>Emoji picker</strong><br><em>Type to filter, Enter types it into the window you came from</em></td>
  </tr>
</table>

### Retro styles

The Quickshell shell swaps its whole look live, from a clean Oasis or Modern style to NES, SNES, Game Boy, PS1, PS2, FF7, GoldenEye, Metroid, Half-Life and TIE Fighter. Styles bring their own transitions, sounds, picker skins and lock screens, and colors always come from the active Oasis palette, so every style works with every theme.

<p align="center">
  <a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-styles.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-styles.webp" width="100%" alt="The bar in Oasis, Modern, Neovim, Metroid and PS1"></a>
  <a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-styles.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-styles.webp" width="100%" alt="The weather popup in NES, Game Boy, PS1, FF7, Metroid and Half-Life"></a>
</p>

### One theme everywhere

The [Oasis](https://github.com/uhs-robert/oasis.nvim) palettes, all AAA contrast, recolor Hyprland, the shell, the terminals and the apps in one switch.

### Hard to lock yourself out

Every shell piece has a fallback (rofi pickers, hyprlock, tuigreet at login), choices made in Settings are saved as state instead of editing tracked files, and a real installer and uninstaller set it up and take it down.

## ⌨️ First five keys

| Key             | Does                                                                              |
| --------------- | --------------------------------------------------------------------------------- |
| `SUPER + SPACE` | Leader: a which-key menu of everything; `SPACE` then opens Start, `S` Settings    |
| `SUPER + /`     | Search and run the keybinds of the mode you are in                                |
| `SUPER + O`     | Apps picker                                                                       |
| `ALT + TAB`     | Workspace overview, move around with `hjkl`. Press `?` for help.                  |
| `SUPER + V`     | HyprVim NORMAL mode for moving windows and workspaces; `SUPER + ESCAPE` leaves it |

The [Hyprland README](home/hypr/.config/hypr/README.md) and the [Quickshell README](home/quickshell/.config/quickshell/README.md) have the rest.

## 📸 Tour

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-settings-metroid.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-settings-metroid.webp" width="100%" alt="Settings"></a><br><strong>Settings</strong><br><em>Metroid's scan visor over styles, colors, bar, displays, apps, power, sound and lock</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-overview-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-overview-ps1.webp" width="100%" alt="Workspace overview"></a><br><strong>Workspace overview</strong><br><em>Every monitor and workspace behind a PS1 scope, moved with hjkl</em></td>
  </tr>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-volume-ps2.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-volume-ps2.webp" width="100%" alt="Volume"></a><br><strong>Volume</strong><br><em>The PS2 memory-dial mixer for outputs, inputs and apps</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-calendar-gameboy.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-calendar-gameboy.webp" width="100%" alt="Calendar"></a><br><strong>Calendar</strong><br><em>A Game Boy calendar with time zones</em></td>
  </tr>
</table>

## 🔒 Lock screens

Each style can bring its own lock screen, and the login screen reuses it.

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-mgs2-anim.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-mgs2-anim.webp" width="100%" alt="Oasis Gear Solid 2"></a><br><strong>Oasis Gear Solid 2</strong><br><em>Tactical tiling action</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ocarina-anim.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ocarina-anim.webp" width="100%" alt="The Legend of Oasis"></a><br><strong>The Legend of Oasis</strong><br><em>Dusk turns to night and the logo ignites on PRESS START</em></td>
  </tr>
</table>

<details>
<summary>More lock screens</summary>

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ff7.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ff7.webp" width="100%" alt="Final Fantasy VII"></a><br><strong>Final Fantasy VII</strong><br><em>New Game, Continue?</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-crt.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-crt.webp" width="100%" alt="CRT terminal"></a><br><strong>CRT terminal</strong><br><em>A phosphor system lock</em></td>
  </tr>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-tie.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-tie.webp" width="100%" alt="TIE Fighter"></a><br><strong>TIE Fighter</strong><br><em>Targeting computer and clearance code</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ocarina.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ocarina.webp" width="100%" alt="The Legend of Oasis"></a><br><strong>The Legend of Oasis</strong><br><em>The title screen, still</em></td>
  </tr>
</table>

</details>

## 📦 Full Install (Automated)

```bash
./install.sh        # full install (Arch only)
./install.sh -m     # minimal (skip optional components)
./install.sh --server # headless: shell/CLI/dev packages and configs only
./install.sh -y     # auto-confirm all prompts
./uninstall.sh      # remove symlinks
```

Installs system packages, AUR packages, fonts, and dev tools, then stows dotfiles into `~/`. Prompts for optional components (greetd, Steam, Nvidia, dev runtimes).

Flags: `--no-aur`, `--no-cargo`, `--no-system-files`, `--no-services`, `--dev`, `--server`.

`--server` is for headless machines: it installs the `[CORE] [SYSTEM] [CLI] [DEV]` sections of `packages/arch.ini` plus `[SHELL] [CLI]` from `packages/arch-aur.ini`, stows the `[SERVER]` list from `packages/stow.ini`, and skips fonts, Rust, greetd, and the desktop services.

## 🔗 External Repos

Some configs live in their own repositories, listed in `packages/repos.ini`: Oasis themes (`oasis.nvim`), HyprVim, keeptabs, rob-bin, the qutebrowser site styles, and the Neovim config. The installer clones them into `repos/` inside this checkout (gitignored) and the dotfiles reference them from there, so nothing depends on where you keep your code.

```bash
./install.sh           # clone read-only copies into repos/ over HTTPS
./install.sh --dev     # clone into ~/Development over SSH and link repos/ to them, for editing
just repos             # set up repos/ only, without the full install (accepts --dev)
just update-repos      # pull the copies in repos/ (linked dev clones are skipped)
```

topgrade runs `just update-repos` as a custom command, so a normal `topgrade` keeps the repos current. HyprVim's own updater is turned off because its clone tracks `main` and is pulled the same way.

A repo that already exists under `~/Development/<section>/<name>` is always linked rather than cloned again. `~/.local/share/dotfiles/repos` points at `repos/` for shell and Hyprland configs that need a fixed path.

To use your own Neovim config, set `NVIM_CONFIG_REPO` to `owner/name` or a git URL before installing. An existing `~/.config/nvim` is never replaced.

```bash
NVIM_CONFIG_REPO=you/nvim ./install.sh
```

## 🧩 Partial Install (Manual Stow)

If you don't want to install the full dotfiles then you may also manually stow the individual packages that you want. Theme files, HyprVim and the qutebrowser styles are symlinks into `repos/`, so run `just repos` first to set those up (see [External Repos](#external-repos)).

```bash
stow -d home <package>     # deploy a package
stow -d home -D <package>  # remove a package
```

The `git` package reads your `[user]` block from `~/.config/git/identity`, which is gitignored so each machine can use its own address. `./install.sh` prompts for it when missing; to write it by hand:

```bash
printf '[user]\n\tname = NAME\n\temail = EMAIL\n' > ~/.config/git/identity
```

## 📁 Yazi

Plugin management with `ya pkg` and a root Yazi that stays in sync with your keymap. See [home/yazi/.config/yazi/README.md](home/yazi/.config/yazi/README.md).

## 🛠️ Justfile

Common tasks are wrapped in a `justfile` (run with [`just`](https://github.com/casey/just)). With `just`, you can just run:

```bash
just                  # list recipes
just stow <package>   # symlink one package
just unstow <package> # remove one package's symlinks
just install          # run install.sh
just uninstall        # run uninstall.sh
just sync-root-yazi   # regenerate root's Yazi keymap from the user's
just update-repos     # pull the external repos cloned into repos/
```

## ✉️ Betterbird / tbkeys

Vim-style keybindings for Betterbird through the tbkeys add-on, with a Neovim compose bridge. See [home/thunderbird/README.md](home/thunderbird/README.md).

## 📱 Termux

For a standalone mobile SSH setup, see [termux/README.md](termux/README.md). It uses its own installer and Stow packages, independent of the desktop setup.

## 📜 License

[GPL-3.0](LICENSE). Bundled third-party pieces keep their own licenses: the fonts in the Quickshell config (SIL Open Font License, see its `fonts/README.md`), the weather icons (MIT, see `assets/weather/LICENSE`), the Bibata cursor themes (GPL-3.0), and the vendored tmux and Yazi plugins and flavors (see each one's own files).
