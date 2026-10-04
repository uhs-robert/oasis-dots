# Custom sounds and music

The shell plays short sounds as you move around it, and can play music on the lock and login screens. Every sound it ships is synthesized and can be replaced, one file at a time, with your own. This page covers how.

## Turning sound on

Open Settings and go to Sound > Theme audio.

| Row | What it does |
| --- | --- |
| Interface sounds | Sounds for moving, confirming, backing out, errors, and locking |
| Notification sound | A sound when a notification arrives |
| Lock music | Music on the lock and login screens, if you have provided any |
| Music volume, Effects volume | Separate levels for music and for everything else |
| Effects pack | Which set of sounds to use |

Press `P` on that page to hear the current pack: it plays each sound in turn.

## Packs and sounds

A pack is a folder holding up to seven files, one per situation:

| File | Plays when |
| --- | --- |
| `cursor` | The selection moves |
| `confirm` | You choose something |
| `cancel` | You back out or close |
| `notify` | A notification arrives |
| `error` | Something fails, such as a wrong password or a failed screenshot |
| `lock` | The session locks |
| `unlock` | The password is accepted |

Each style has a pack of the same name: `oasis`, `modern`, `neovim`, `terminal`, `crt`, `nes`, `gameboy`, `snes`, `ps1`, `ff7`, `goldeneye`, `ps2`, `tie`, `halflife`, `metroid` and `reticle`. There is one extra pack that belongs to no style, `mgs2`.

The Effects pack row picks one pack for every style. Its first option, Follow style, uses each style's own pack and is the default.

## Replacing sounds with your own

Put your files in `~/.local/share/quickshell/sounds/<pack>/`, named after the sound they replace:

```
~/.local/share/quickshell/sounds/nes/cursor.wav
~/.local/share/quickshell/sounds/nes/confirm.ogg
```

- `.wav` and `.ogg` both work.
- Your files win one at a time. Replace only `cursor` and the pack's other six sounds stay as shipped.
- The folder name is the pack you want to change, not the style you happen to be using. If the Effects pack is set to NES, the `nes` folder applies under every style.
- Nothing needs restarting. The shell notices new files.

To check a file before you commit to it, play it the way the shell does:

```
pw-play ~/.local/share/quickshell/sounds/nes/cursor.wav
```

A few things that make a replacement sit well with the rest:

- Keep `cursor` short, under a tenth of a second. It plays on every key press, and a long one turns to mush when you hold a key.
- Match the level of the pack. Shipped sounds peak at about a third of full scale. To bring a loud file down: `ffmpeg -i in.wav -af volume=-9dB out.wav`.
- Trim silence from the start. A sound that begins 50 ms into its file feels late.

### When a sound is missing

- A pack with no `error` plays its `cancel` instead.
- A pack with no `lock` or `unlock` stays silent for those.
- Anything else missing is simply not played.

So a pack of your own can start with only the files you care about.

## Game audio you import

Four lock screens are modelled on games, and the shell can use those games' own audio if you supply it. None of it is in the repo. Each has an importer in `scripts/` that you run once. It reads your copies, trims and levels them, finds the music's loop points, and writes the result where the shell looks for it. The shell only ever reads those results, so the source folder can be deleted afterwards. Keep it if you might import again: the loop points are saved as tags in the source files.

| Script | Give it | Writes to |
| --- | --- | --- |
| `ff7-audio` | A folder with `music/` (the Prelude) and `fx/` (the menu sounds) | `~/.local/share/quickshell/ff7-audio/` |
| `mgs2-audio` | A folder with the title and menu themes and the menu sounds | `~/.local/share/quickshell/mgs2-audio/` |
| `ocarina-audio` | A folder with the title and fairy fountain tracks and the menu sounds | `~/.local/share/quickshell/ocarina-audio/` |
| `goldeneye-audio` | The watch theme, as one audio file | `~/.local/share/quickshell/goldeneye-audio/` |

The source is the last argument and is required, for example `scripts/mgs2-audio ~/Music/mgs2`. Run a script with `--help` for the file names it expects.

Until you import, a lock screen simply has no game music or effects. Every importer needs `ffmpeg` and `python3` with `numpy`. All but `ff7-audio` also need `ffprobe` and `jq`, and `goldeneye-audio`, `mgs2-audio` and `ocarina-audio` need `pipx` to find loop points unless you pass them. Playing the result needs `mpv`. On Arch: `pacman -S ffmpeg jq python-numpy python-pipx mpv`. The GoldenEye intro frames come from `scripts/goldeneye-frames`, which also needs `yt-dlp` and `python-pillow`, and downloads about an hour of video (roughly 1 GB) unless you give it one.

Once imported, FFVII, MGS2 and Ocarina also appear in the Effects pack list, so their menu sounds can be used for the whole shell. An imported pack is used as it is: files in `~/.local/share/quickshell/sounds/` do not override it. Where an imported pack has no file for a sound, the current style's own is used.

## Lock and login music

No music ships. To have some, put a file named `music.ogg`, `music.wav` or `music.mp3` in the sounds folder of the style your lock screen uses:

```
~/.local/share/quickshell/sounds/oasis/music.ogg
```

Then turn on Lock music under Sound > Theme audio and Music under Lock & Login > Lock screen. The file loops for as long as the screen is locked, so a track that loops cleanly works best.

- Locking by hand starts the music at once. A lock that happens on its own (idle, sleep, lid close) stays quiet until you press a key.
- Music fades out after two minutes without a key press.
- The FF7, GoldenEye, MGS2 and Ocarina lock screens use their imported game music instead and ignore this file.

## Sounds on the game lock screens

The MGS2 and GoldenEye lock screens have their own effects: menu blips, transitions, the watch static. Synthesized stand-ins ship with the repo, in `lock/skins/mgs2/fx/` and `lock/skins/goldeneye/fx/`.

To use real ones, put a `.wav` of the same name in that lock screen's import folder, `~/.local/share/quickshell/mgs2-audio/` or `~/.local/share/quickshell/goldeneye-audio/`. Yours win one file at a time, as with packs. These must be `.wav`; the lock screens cannot play `.ogg` effects.

| Lock screen | File names |
| --- | --- |
| MGS2 | `select`, `submit`, `back`, `error`, `transition_wipe`, `transition_left`, `transition_right` |
| GoldenEye | `select`, `confirm`, `back`, `type`, `error`, `lock_open`, `lock_close`, `static` |

## How the shipped sounds are made

Every shipped sound comes from one script, `scripts/synth-sounds`, which needs Python with numpy, and ffmpeg. Each pack is a short function in it. Change one, then run:

```
scripts/synth-sounds nes
```

With no argument it rebuilds every pack. The output is reproducible: the same script always writes the same files.

The game-styled packs (`ff7`, `ps1`, `mgs2`, `halflife`, `metroid`, `tie`, `goldeneye`) are not recordings. They were rebuilt from measurements of the games' sounds: pitch, timing and loudness, played back through oscillators and shaped noise. They are close, not identical, which is why the override folder exists.
