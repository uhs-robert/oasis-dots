---
id: mediasettings
title: Media settings
status: draft
prs: []
implements:
  - home/quickshell/.config/quickshell/features/settings/sections/MediaSection.qml
  - home/quickshell/.config/quickshell/features/settings/MediaPreview.qml
  - home/quickshell/.config/quickshell/features/media/MediaSample.qml
depends_on: []
---
# Media settings

## What it is for
The owner tunes the bar's media module from Settings > Media: what shows on its right, its container, which parts show and how the track text is laid out. A live preview of the module sits above the options, so each change can be judged as it is made, with music playing or not.

## Requirements
- **MEDIASETTINGS-01** [gap: untested] The page is one list under the headings Visualizer, Layout and Text, in that order. `j`/`k` walk every option across the headings and `{`/`}` jump between them.
- **MEDIASETTINGS-02** [gap: untested] A preview of the bar's media module, at about twice its size, sits above the options and stays in view while the list scrolls. It changes as soon as an option changes: right side, cava line, container, album art, play/pause, title, artist, text layout, text width, scrolling text and its speed.
- **MEDIASETTINGS-03** The preview shows the player that is playing, or one paused on a track.
- **MEDIASETTINGS-04** With no player, a stopped one or a paused one with no track, the preview shows a sample track instead.
- **MEDIASETTINGS-05** The sample's visualizer moves without starting the audio visualizer, and its position runs and starts over at the end of the track.
- **MEDIASETTINGS-06** [gap: untested] The preview picks its right side as the bar does: on battery it shows the battery fallback, and in the split island mode or the lualine style it shows the track position.
- **MEDIASETTINGS-07** [gap: untested] The bar's own media module looks and behaves as it did before the preview existed.
- **MEDIASETTINGS-08** On a pane too narrow for it, the preview shrinks to the pane's width rather than spilling out.

## Look
The module sits centred on a patch of the island colour, the height of a top bar on the current screen, with a dim caption under it: "Sample track" or the player that is playing. The sample has a made-up title and artist long enough to be cut and to scroll, bundled album art, a moving visualizer and a moving position.

## Not covered
The Scroll option (what the mouse wheel does) has no preview. Island styles may change nothing visible in strip and frame styles, where the bar always shows the module.
