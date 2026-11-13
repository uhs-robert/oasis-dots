# Styles and themes

A style changes how the whole shell looks and behaves: fonts, frames, meters, key hints, transitions and sounds. The palette sets every color, so each style works with every palette. This page covers how to switch both and what you can tweak.

## Switching style

Open Settings with `SUPER + SPACE` then `S`, or from the Start menu. Go to Appearance > Style and pick one under Style. The change applies at once.

From a script or a keybind, use IPC:

```bash
qs ipc call style set ps1
qs ipc call style cycle
```

`set` takes a style name and `cycle` moves to the next one.

The styles, in picker order: `oasis` (the default), `modern`, `neovim`, `terminal`, `crt`, `nes`, `gameboy`, `snes`, `ps1`, `ff7`, `goldeneye`, `ps2`, `tie`, `halflife`, `metroid` and `reticle`. Everyday styles come first, then consoles by release year, then sci-fi.

## Switching palette

Settings > Appearance > Style > Palette picks the Oasis palette. It applies at once and also recolors Hyprland and terminal apps. Sync Neovim, on the row below, switches Neovim's colorscheme along with it. Right-clicking the Start button opens the same list.

The one exception to palette colors is the `goldeneye` style, described below.

## Tweaking a style

Settings > Appearance > Theme options holds the options of the current style, such as scanlines, glow, dither, fonts and text size. The rows differ per style.

- `r` puts the selected option back to the style's own value.
- `R` resets every option of that style.

Options worth knowing:

| Option | What it does |
| --- | --- |
| Controller glyphs | On console styles, how key hints draw: All buttons, Labeled, D-pad or Off |
| Model | On `gameboy`, Color (your palette) or Original (grey shell) |
| Island shape | The outline of the bar's islands. Any style can borrow any shape, except `neovim` |
| Island opacity | How see-through the island fills are, from 100% down to 0% |
| Screen frame | Off by default. Plain adds bands in the bar's color round the rest of the screen. Not on `neovim` or `terminal` |
| Watch colours | On `goldeneye` only, see below |

Theme options also has skin rows for the picker, overview, workspaces, OSD, weather, KeepTabs, toasts and animations. Each defaults to the style's own, and you can borrow another style's. A borrowed skin draws in your palette.

With Screen frame on, the bar becomes one full strip and the Island shape row reads Full bar (frame). Your choice returns when you turn the frame off. Settings > Appearance > Style > Flush single windows decides whether a lone window sits flush against the frame.

## GoldenEye watch colours

The `goldeneye` style is the GoldenEye 007 pause watch. Under Theme options, Watch colours has two modes:

- Theme, the default, tints the watch from your palette.
- Classic is the fixed green of the lock skin.

The game's own marks keep their colors in both modes, such as the red-to-yellow arcs and the red crosshair. The lock and login screens follow the same option.

## Sounds

Each style has its own sound pack. Settings > Appearance > Theme audio turns sounds on and picks the pack. [Custom sounds and music](sounds.md) covers replacing sounds with your own.

## Lock screens

Most styles have a matching lock skin. [Lock screen and login](lock-screen.md) covers choosing one.

## More

- [Theme README](../home/quickshell/.config/quickshell/theme/README.md#styles) holds every style option and skin in detail.
- [Adding a style](../home/quickshell/.config/quickshell/theme/README.md#adding-a-style-or-style-token) is for writing your own.
