# Lock screen and login

The shell draws its own lock screen and login screen. This page covers choosing the look, game audio, the login screen and trying a skin without locking.

## Choosing the lock

Open Settings with `SUPER + SPACE` then `S`, then System > Lock & login. Under Lock, the Screen row picks the design:

| Value | You get |
| --- | --- |
| Follow bar style | The lock skin of the current style. A style without a skin gets the simple screen |
| Simple | A plain card over your desktop |
| A skin name | That skin, whatever the style |

The skins are `Crt`, `Ff7`, `Goldeneye`, `Mgs2`, `Ocarina` and `Tie`. `Ocarina` and `Mgs2` exist only as lock skins, with no bar style.

Other rows under Lock:

- Tint recolors the skin: primary, secondary, a terminal color, white or classic. Classic keeps each skin's original palette. `Ocarina` ignores the tint.
- Simple backdrop sets what the simple screen shows behind its card: a pixelated or blurred desktop, or nothing.
- Music and Music volume are covered in [Custom sounds and music](sounds.md).

The same choices work over IPC:

```bash
qs ipc call style set_lock goldeneye   # a skin name, follow or simple
qs ipc call style set_lock_tint red
qs ipc call style set_lock_backdrop blur
```

Skins with a game menu (`Ff7`, `Goldeneye`, `Mgs2`, `Ocarina`) offer Reboot and Shut down on the locked screen. Each needs a second press to confirm.

## Typing the password

The lock uses vim-style keys. While nothing is typed, `h`, `j`, `k` and `l` move through a skin's menus. Any other printable key starts the password and is its first character. `i` starts it without typing anything. `Esc` on an empty password goes back. A password that starts with `i` needs the key twice. Once the password is accepted, any key skips the unlock animation.

## Locking

Hypridle and the Power menu lock through `~/.config/hypr/scripts/lock-screen.sh`. When the bar is not running, it falls back to hyprlock. If the bar restarts while locked, the new one takes the lock over.

## Game audio and frames

Four skins can play audio from the games that inspired them, and the `Goldeneye` skin can use frames cut from the game. None of it ships. Without it a skin stays silent or skips its intro. [Custom sounds and music](sounds.md#game-audio-you-import) lists the importer scripts and the tools they need.

To build the GoldenEye frames, run `scripts/goldeneye-frames`. It needs `ffmpeg`, `yt-dlp` and python with `PIL` and `numpy`. Without frames the skin draws its own bezel and a simple arm intro.

## Music on the lock

All lock music fades out after two minutes without a key press. Locking by hand starts the music at once. A lock that happens by itself (idle, sleep, lid close) stays quiet until you press a key. Details are in [Custom sounds and music](sounds.md#lock-and-login-music).

## The login screen

The login screen is a Quickshell greeter under greetd and shows your lock skin. The installer offers it. To install or update it by hand:

```bash
just greeter-sync            # stage it and print the sudo commands
just greeter-sync --install  # stage and install it
just greeter-preview         # try it in a window with a fake greetd
```

Under Lock & login > Login, Sync to greeter keeps it in step with your choices. Login has its own Screen, Tint, Music and Session rows. Each of the first three can follow the lock. If the greeter fails to start, tuigreet takes over. `F10` or `SUPER + T` at the login screen switches to tuigreet yourself.

## Trying a skin

In Lock & login, press `p` to preview the selected design full screen. The preview is a normal window with fake state. It never touches the real lock. From a terminal:

```bash
qs ipc call lock preview goldeneye
qs ipc call lock preview_close
```

## Heavy load

While locked on AC, the skin goes still when agent sessions or the machine are busy, to save power. A key press restarts motion for a minute. The thresholds are in the [lock README](../home/quickshell/.config/quickshell/features/lock/README.md#under-load).

## More

- [Lock README](../home/quickshell/.config/quickshell/features/lock/README.md) covers internals.
- [Adding a lock skin](../home/quickshell/.config/quickshell/features/lock/README.md#adding-a-lock-skin) is for writing your own.
- [Styles and themes](styles.md) covers the rest of the look.
