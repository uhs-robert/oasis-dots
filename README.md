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
  <a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/hero-v2.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/hero-v2.webp" width="100%" alt="Switching styles, the Leader menu, the overview and a region selection with zoom"></a>
</p>

## 🖥️ Overview

An Arch Linux desktop on Hyprland, driven from the keyboard with vim binds and modes; no need for a mouse.

- [Hyprland](home/hypr/.config/hypr/README.md), configured in Lua, with [HyprVim](https://github.com/uhs-robert/hyprvim) for Vim-modal window management and which-key hints.
- A [Quickshell](home/quickshell/.config/quickshell/README.md) desktop shell: per-monitor bars, popups, notifications, pickers, a workspace overview, a Settings panel and the lock screen.
  - It comes in swappable styles, from a clean modern look to multiple different retro gaming eras.
- [Oasis](https://github.com/uhs-robert/oasis.nvim) color themes across everything.
- A greetd login screen that reuses the lock screen's look, with tuigreet as a fallback.

> [!NOTE]
> Managed with [GNU Stow](https://www.gnu.org/software/stow/); packages live under `home/`.

**Requirements:** Arch Linux and a Hyprland build with the Lua config API (the `hl` global) and the `start-hyprland` launcher. The current `hyprland` package from the Arch repos, which the installer pulls in, provides both. The Quickshell config is tested with Quickshell 0.3.1; the installer warns when `qs` is older.

## 🎹 Keyboard First, for Vim Users

> Manage your GUI, TUI, and everything in-between with just a keyboard and vim modes/motions.

Oasis brings Vim to Hyprland with [HyprVim](https://github.com/uhs-robert/hyprvim) and takes it even further beyond with virtual cursors, mouse emulation, and full keyboard navigation. Every menu, picker, and setting is accessed and controlled by vim modes/binds.

### Screenshot, Video Recorder, Color Picker

Even the screenshot/video recorder/color picker can be steered with nothing but your keyboard.

<p align="center">
  <a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/region-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/region-ps1.webp" width="100%" alt="The PS1 region selector, steered with hjkl, with its zoom scope"></a>
  <br><em><strong>Screenshot region selector:</strong> move, anchor and resize with <code>hjkl</code>, zoom with <code>i</code>/<code>o</code></em>
</p>

### Which-key and keybind search/run

Learn the keybinds like you do in NeoVim with which-key upon submap entry. Search/run any keybind with `SUPER + /`:

<table>
  <tr>
    <td align="center" width="34%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/whichkey-leader.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/whichkey-leader.webp" width="100%" alt="Which-key"></a><br><strong>Which-key</strong><br><em>Submaps list their keys (PSX style)</em></td>
    <td align="center" width="66%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/picker-keybinds.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/picker-keybinds.webp" width="100%" alt="Keybind executor"></a><br><strong>Keybind Search/Run</strong><br><em><code>SUPER + /</code> fuzzy-searches binds in the mode you are in and runs the one you pick</em></td>
  </tr>
</table>

### HyprVim Command Mode

And control Hyprland via `:`, like Vim's **Command Mode**:

<table>
  <tr>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/prompt-menu.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/prompt-menu.webp" width="100%" alt="HyprVim command prompt with fuzzy menu"></a><br/><p align="center">HyprVim Command Mode with fuzzy completion</p></td>
  </tr>
  <tr>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/prompt-args.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/prompt-args.webp" width="100%" alt="HyprVim command prompt with argument hints"></a><br/><p align="center">Includes flag hints to teach arguments as you use</p></td>
  </tr>
</table>

### And Even More

- **Mouse from the keyboard:** `SUPER + C` enters the Cursor submap: `hjkl` moves the pointer (`SHIFT` for fast, `CTRL` for single pixels), `SPACE` clicks, `e`/`y` scroll, and `f` or `t` drop [wl-kbptr](https://github.com/moverest/wl-kbptr) hint labels on screen to click anything in a couple of keystrokes.
- **Screen sharing:** the share picker opens the workspace overview with only shareable windows, so you pick a window, a whole monitor (`s`) or a region (`r`) by keyboard.
- **Scrolling capture:** grab a page longer than the screen and OCR it to text in one pass.
- **Displays:** arrange monitors in Settings with `hjkl`, with a countdown that reverts anything you don't confirm.

## 🎨 Styles

> Pick from over 15 different styles including `Oasis`, `Modern`, `NeoVim`, and more.

Powered by the [Oasis](https://github.com/uhs-robert/oasis.nvim) colorscheme palettes from NeoVim, also includes over 15 different styles to choose from in combination.

Styles transform the appearance of the bar, popups, menus, pickers, fonts, sounds, transitions, and the lock screen too. Every sound can be swapped for your own: see [Custom sounds and music](docs/sounds.md).

Pick a style in `Settings > Style` (`SUPER + SPACE` then `S`) and it swaps live.

> [!NOTE]
> **Styles include:** Oasis, Modern, Neovim, Terminal, CRT, NES, Game Boy, SNES, PSX, FF7, GoldenEye, PS2, TIE Fighter, Half-Life, Metroid and Reticle.

### 🍫 Bar Style Examples

Just a few example bars:

<table>
  <tr>
    <td width="15%" align="center"><strong>Oasis</strong><br><em>Default</em></td>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-oasis.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-oasis.webp" width="100%" alt="Oasis bar"></a></td>
  </tr>
  <tr>
    <td width="15%" align="center"><strong>Modern</strong><br><em>Rounded</em></td>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-modern.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-modern.webp" width="100%" alt="Modern bar"></a></td>
  </tr>
  <tr>
    <td width="15%" align="center"><strong>Neovim</strong><br><em>Lualine-style</em></td>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-neovim.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-neovim.webp" width="100%" alt="Neovim bar"></a></td>
  </tr>
  <tr>
    <td width="15%" align="center"><strong>Metroid</strong><br><em>Combat visor</em></td>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-metroid.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-metroid.webp" width="100%" alt="Metroid bar"></a></td>
  </tr>
  <tr>
    <td width="15%" align="center"><strong>PSX</strong><br><em>Retro PSX</em></td>
    <td><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/bar-ps1.webp" width="100%" alt="PSX bar"></a></td>
  </tr>
</table>

### 🌦️ Weather Module Examples

Just a few example weather modules:

<table>
  <tr>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-nes.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-nes.webp" width="100%" alt="NES weather"></a><br><strong>NES</strong><br><em>Dragon Quest bars</em></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-ff7.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-ff7.webp" width="100%" alt="FF7 weather"></a><br><strong>FF7</strong><br><em>Materia orbs</em></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-halflife.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-halflife.webp" width="100%" alt="Half-Life weather"></a><br><strong>Half-Life</strong><br><em>HEV suit readout</em></td>
  </tr>
</table>

<details>
<summary>🌤️ The weather popup in every other style</summary>

<table>
  <tr>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-oasis.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-oasis.webp" width="100%" alt="Oasis"></a><br><strong>Oasis</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-modern.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-modern.webp" width="100%" alt="Modern"></a><br><strong>Modern</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-neovim.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-neovim.webp" width="100%" alt="Neovim"></a><br><strong>Neovim</strong></td>
  </tr>
  <tr>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-terminal.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-terminal.webp" width="100%" alt="Terminal"></a><br><strong>Terminal</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-crt.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-crt.webp" width="100%" alt="CRT"></a><br><strong>CRT</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-gameboy.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-gameboy.webp" width="100%" alt="Game Boy"></a><br><strong>Game Boy</strong></td>
  </tr>
  <tr>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-snes.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-snes.webp" width="100%" alt="SNES"></a><br><strong>SNES</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-ps1.webp" width="100%" alt="PSX"></a><br><strong>PSX</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-goldeneye.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-goldeneye.webp" width="100%" alt="GoldenEye"></a><br><strong>GoldenEye</strong></td>
  </tr>
  <tr>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-ps2.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-ps2.webp" width="100%" alt="PS2"></a><br><strong>PS2</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-tie.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-tie.webp" width="100%" alt="TIE Fighter"></a><br><strong>TIE Fighter</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-metroid.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/weather-metroid.webp" width="100%" alt="Metroid"></a><br><strong>Metroid</strong></td>
  </tr>
</table>

</details>

### 🔊 Volume Mixer Examples

The volume mixer in three styles:

<table>
  <tr>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/volume-oasis.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/volume-oasis.webp" width="100%" alt="Oasis"></a><br><strong>Oasis</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/volume-crt.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/volume-crt.webp" width="100%" alt="CRT"></a><br><strong>CRT</strong></td>
    <td align="center" width="33%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/volume-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/volume-ps1.webp" width="100%" alt="PSX"></a><br><strong>PSX</strong></td>
  </tr>
</table>

### 📸 Tour of Some Other Modules

Styles influence every popup. Each card below shows a different popup and a different style.

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-settings-crt.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-settings-crt.webp" width="100%" alt="Settings"></a><br><strong>Settings (CRT)</strong><br><em>Settings menu: styles, colors, bar, displays, apps, power, etc</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-overview-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-overview-ps1.webp" width="100%" alt="Workspace overview"></a><br><strong>Workspace Overview (PSX)</strong><br><em>Monitors and workspaces selected via Metal Gear scope</em></td>
  </tr>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-calendar-gameboy.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-calendar-gameboy.webp" width="100%" alt="Calendar"></a><br><strong>Calendar (Gameboy)</strong><br><em>Calendar inside a Game Boy screen with time zones</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-notifications-ps1.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/tour-notifications-ps1.webp" width="100%" alt="Notifications"></a><br><strong>Notifications (PSX)</strong><br><em>History with Do Not Disturb, filters and inline actions like Join, Open and Focus</em></td>
  </tr>
</table>

## 🔒 Lock screens

Each style can bring its own lock screen, and the login screen reuses it. The skins are Oasis Gear Solid 2, The Legend of Oasis, Final Fantasy VII, GoldenEye 007 (the pause watch), CRT terminal and TIE Fighter.

Password entry works like Vim. While nothing is typed you are in NORMAL mode, where `h`/`j`/`k`/`l` move through a skin's menus. `i` or any other printable key starts typing and shows `-- INSERT --` bottom-left; `Esc` on an empty password goes back to NORMAL.

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-mgs2-anim.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-mgs2-anim.webp" width="100%" alt="Oasis Gear Solid 2"></a><br><strong>Oasis Gear Solid 2</strong><br><em>Title, menu, options, memory card load, then a wrong password and a retry</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ocarina-anim.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ocarina-anim.webp" width="100%" alt="The Legend of Oasis"></a><br><strong>The Legend of Oasis</strong><br><em>The sky runs from night to dawn, then file select, options, and a wrong password before the retry</em></td>
  </tr>
</table>

<details>
<summary>🍭 More lock screens</summary>

<table>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ff7.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-ff7.webp" width="100%" alt="Final Fantasy VII"></a><br><strong>Final Fantasy VII</strong><br><em>New Game, Continue?</em></td>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-crt.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-crt.webp" width="100%" alt="CRT terminal"></a><br><strong>CRT terminal</strong><br><em>A phosphor system lock</em></td>
  </tr>
  <tr>
    <td align="center" width="50%"><a href="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-tie.webp"><img src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/docs/lock-tie.webp" width="100%" alt="TIE Fighter"></a><br><strong>TIE Fighter</strong><br><em>Targeting computer and clearance code</em></td>
  </tr>
</table>

</details>

## 📦 Full Install (Automated)

Clone the repo to `~/dotfiles`; topgrade's git step pulls it from there. `~/.config/hypr` and `~/.config/quickshell` are symlinks into this checkout, so keep it in place and do not move or delete it after installing (`uninstall.sh` also expects it at `~/dotfiles`).

```bash
git clone https://github.com/uhs-robert/oasis-dots.git ~/dotfiles
cd ~/dotfiles
./install.sh        # full install (Arch only)
./install.sh -m     # minimal (skip AUR, Rust, system files and services)
./install.sh --server # headless: shell/CLI/dev packages and configs only
./install.sh -y     # auto-confirm all prompts
./uninstall.sh      # remove symlinks
```

Installs system packages, AUR packages, fonts, and dev tools, then stows dotfiles into `~/`. Prompts for optional components (greetd, Steam, Nvidia, dev runtimes).

When it finishes, reboot. Without greetd you can instead log out and run `start-hyprland` from a TTY, unless you installed Nvidia drivers or xone.

<details>
<summary>What the installer touches outside your home directory</summary>

It uses `sudo` for these; the flags in brackets skip them.

- Packages through pacman and paru [`--no-aur` for paru], the `rustup` toolchain with both stable and nightly [`--no-cargo`] and the latest Maple Mono NF release, unpinned, in `/usr/local/share/fonts`.
- `/etc`: `vtrgb-oasis`, `keyd/default.conf` and two pacman hooks; `/usr/local/bin` and `/usr/local/share/betterbird-autoconfig` for the voxtype GPU and Betterbird autoconfig helpers, which also patch `/opt/betterbird` when it exists [`--no-system-files`].
- `/root`: links root's `.zshrc`, `.zsh_plugins.txt`, Neovim and Yazi config to yours, and adds `yazi-root` and a `/usr/local/sbin/yazi` wrapper, after a prompt [`--no-system-files`].
- greetd, after a prompt: `/etc/greetd`, `/etc/tuigreet`, `/usr/local/bin/tuigreet-oasis`, the Quickshell greeter in `/etc/greetd/quickshell`, `/usr/local/bin/qs-greeter` and `/var/lib/qs-greeter`, then enables `greetd` [`--no-services`].
- Your login shell is changed to zsh, and `keyd` and `power-profiles-daemon` are enabled [`--no-services`].
- Steam, after a prompt: native Steam enables `[multilib]` in `/etc/pacman.conf` and runs a full `pacman -Syu`, Flatpak Steam installs `flatpak` and adds a system-wide Flathub remote; the optional xone driver builds a DKMS kernel module [`--no-services`].
- Nvidia drivers, after a prompt [`--no-services`].
- voxtype adds you to the `input` group [`--no-services`].

</details>

If stow reports a conflict with an existing file, the installer shows stow's error and carries on; move the conflicting files aside and run `just stow <package>`. Never use `stow --adopt`, which moves your files into the repo.

Flags: `--no-aur`, `--no-cargo`, `--no-system-files`, `--no-services`, `--dev`, `--server`.

`--server` is for headless machines: it installs the `[CORE] [SYSTEM] [CLI] [DEV]` sections of `packages/arch.ini` plus `[SHELL] [CLI]` from `packages/arch-aur.ini`, stows the `[SERVER]` list from `packages/stow.ini`, and skips fonts, Rust, greetd, and the desktop services.

## ⌨️ Getting Started, Your First Five Keys

| Key             | Does                                                                              |
| --------------- | --------------------------------------------------------------------------------- |
| `SUPER + SPACE` | Leader: a which-key menu of everything; `SPACE` then opens Start, `S` Settings    |
| `SUPER + /`     | Search and run the keybinds of the mode you are in                                |
| `SUPER + O`     | Apps picker                                                                       |
| `ALT + TAB`     | Workspace overview, move around with `hjkl`. Press `?` for help.                  |
| `SUPER + V`     | HyprVim NORMAL mode for moving windows and workspaces; `SUPER + ESCAPE` leaves it |

The [Hyprland README](home/hypr/.config/hypr/README.md) and the [Quickshell README](home/quickshell/.config/quickshell/README.md) have the rest. To rebind anything, see [Changing keybinds](docs/keybinds.md).

## 🔗 External Repos

Some configs live in their own repositories, listed in `packages/repos.ini`: Oasis themes (`oasis.nvim`), HyprVim, keeptabs, rob-bin, the qutebrowser site styles, and the Neovim config. The installer clones them into `repos/` inside this checkout (gitignored) and the dotfiles reference them from there, so nothing depends on where you keep your code.

```bash
./install.sh           # clone read-only copies into repos/ over HTTPS
./install.sh --dev     # clone into ~/Development over SSH and link repos/ to them, for editing
just repos             # set up repos/ only, without the full install (accepts --dev)
just update-repos      # pull the copies in repos/ (linked dev clones are skipped)
```

topgrade runs `just update-repos` as a custom command, so a normal `topgrade` keeps the repos current. HyprVim's own updater is turned off because its clone tracks `main` and is pulled the same way.

Forks can change the dev directory (default `~/Development`) and the GitHub owner that `--dev` clones over SSH (default `uhs-robert`) with `GITHUB_DIR` and `GITHUB_ORG`, either in the environment (`GITHUB_DIR=~/src ./install.sh --dev`) or in an ignored `install.local` at the repo root holding plain `GITHUB_DIR=...` and `GITHUB_ORG=...` lines. The environment wins over the file.

A repo that already exists under `~/Development/<section>/<name>` is always linked rather than cloned again. `~/.local/share/dotfiles/repos` points at `repos/` for shell and Hyprland configs that need a fixed path.

To use your own Neovim config, set `NVIM_CONFIG_REPO` to `owner/name` or a git URL before installing. An existing `~/.config/nvim` is never replaced.

```bash
NVIM_CONFIG_REPO=you/nvim ./install.sh
```

## 🧩 Partial Install (Manual Stow)

If you don't want to install the full dotfiles then you may also manually stow the individual packages that you want. Theme files, HyprVim and the qutebrowser styles are symlinks into `repos/`, so run `just repos` first to set those up (see [External Repos](#-external-repos)).

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
