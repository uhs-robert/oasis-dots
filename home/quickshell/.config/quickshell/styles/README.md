# Styles

## Sounds

The sounds in `styles/<style>/sounds/` are synthesized by `scripts/synth-sounds` (numpy and ffmpeg), one hand-built patch per style. `sounds/mgs2/` is an extra pack tied to no style. `sounds/alarm.ogg`, a digital watch beep from the same script, is the alarm for a style with no pack and for Theme audio with interface and notification sounds both off. To use your own, drop `cursor`, `confirm`, `cancel`, `notify`, `error`, `lock`, `unlock` or `alarm` files (`.wav` or `.ogg`) into `~/.local/share/quickshell/sounds/<pack>/`, where `<pack>` is the style or pack name. They win file by file. [Custom sounds and music](../../../../../docs/sounds.md) walks through it, along with lock music and the game lock screens' audio.

Settings > Theme audio (in the Sound group) picks one effects pack for every style: follow the style (the default), any style's sounds, the synthesized MGS2 pack, or an imported game pack (FFVII, MGS2, Ocarina). When following the style, FFVII uses the imported FFVII pack once there is one, and every other style its own. No music ships: lock and login music plays only from your own `music.ogg`, `music.wav` or `music.mp3` in `~/.local/share/quickshell/sounds/<style>/`.
