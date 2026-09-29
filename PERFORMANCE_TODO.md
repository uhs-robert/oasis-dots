# Performance TODO

Quickshell memory and CPU work, biggest win first. Paths are relative to `home/quickshell/.config/quickshell/` unless noted.

## Baseline (2026-09-29)

Stowed `qs -n` on 4 monitors: 1.26 GB RSS at 2.5 min uptime, 1.07 GB of it anonymous, 110 threads. The QML JS heap (`memfd:JSGCHeap`) is only ~33 MB, so the cost sits in C++ objects, the scene graph and the GL driver, not in JS. Measure with:

```bash
p=$(pgrep -x qs); ps -o etime=,rss= -p $p; grep -E 'Anonymous|AnonHuge' /proc/$p/smaps_rollup; ls /proc/$p/task | wc -l
```

## Startup cost

- [x] **1. Build popups on open, drop them after close.** `shell.qml` creates 19 `Popup` PanelWindows at startup and each builds its whole body (tabs, Repeaters, Canvases, layers) while hidden. Wrap them in a `LazyLoader` that loads just before `Popups.open` sets `open_name` and unloads once the close animation hides the window. Keep `HyprvimPrompt` (owns an `IpcHandler`) and `TooltipShelf` (hover-driven) eager.
- [ ] **2. Fewer GL contexts and render threads.** Every window that has been shown keeps its own `QSGRenderThread`, GL context, driver threads (`qs:gl0`, `qs:gdrv0`) and glyph atlas; one run had 9 render threads for 4 visible surfaces. Item 1 removes most of these. Also try `QSG_RENDER_LOOP=basic` to see if a single render thread costs less without hurting animation.
- [ ] **3. Transparent hugepages and malloc arenas.** THP is `always`, and 370-390 MB of anonymous memory sits in `AnonHugePages`. With ~100 threads glibc opens many arenas, each touched region rounds up to 2 MB pages. A/B test `MALLOC_ARENA_MAX=2` on the qs launch, and THP `madvise` system-wide (`/sys/kernel/mm/transparent_hugepage/enabled`).
- [ ] **4. Two GL stacks mapped.** Mesa (gallium, LLVM) and NVIDIA libraries are both loaded. Check that qs renders on the iGPU only (`__EGL_VENDOR_LIBRARY_FILENAMES` or `__GLX_VENDOR_LIBRARY_NAME=mesa`) so the NVIDIA stack never loads.
- [ ] **5. Only build the shown weather tab.** `popups/WeatherPopup.qml:471-506` keeps Daily, Hourly, Air, SunMoon and Alerts alive and swaps them with `visible`. Hourly is a `Repeater` over all hours in a `Flickable` plus a `Canvas`. Put each tab in a `Loader` bound to the current tab.
- [ ] **6. QtMultimedia always loaded.** The `services/ThemeAudio.qml` singleton imports QtMultimedia, which loads the FFmpeg backend for the whole process, and its 4 `SoundEffect`s load even with UI sounds off. Load the effects only when sounds are on.
- [ ] **7. All 57 bundled fonts load at startup.** `services/BundledFonts.qml` registers every font in `fonts/` (5.4 MB). Load only the families the active style uses.

## Images and effects

- [ ] **8. Album art at full resolution.** `popups/MediaPopup.qml:120` and `:205` have no `sourceSize` and sit under 4 `layer.enabled` items plus a blur and a mask `MultiEffect`. Set `sourceSize` to the drawn size. Item 1 drops the layers while closed.
- [ ] **9. Notification images at full size.** `popups/notifications/NotificationCard.qml:277`, `components/NotificationToastCard.qml:364` and `popups/NotificationsPopup.qml:367` (an 18 px icon) have no `sourceSize`.
- [ ] **10. Glow layers in every popup.** `components/Popup.qml:642` layers the whole frame when the style has glow or text shadow, plus the `MultiEffect` Loaders at `:880-910`. Same pattern in `components/Osd.qml`, `components/WhichKey.qml` and `components/Meter.qml`. Item 1 covers popups; Osd and WhichKey stay built.

## Growth over time

- [ ] **11. Cap notification history.** `services/NotificationState.qml:64` prepends every notification with no limit, keeps each `Notification` `tracked` with its image data, and restores the history on reload. Cap it (50-100) and drop the image of entries past the cap.
- [ ] **12. Array rebuilds on notification change.** `NotificationState` rebuilds whole arrays with `concat`/`filter`, and `NotificationsPopup.qml:72-95` and `components/NotificationToasts.qml:77` rebuild every row. Move to a `ListModel` or keyed updates if item 11 is not enough.
- [ ] **13. Voxtype peak buffer.** Check that the peaks pushed at `services/VoxtypeAudio.qml:87` are capped.

## Other always-alive windows

- [ ] **14.** `components/Osd.qml`, `components/WhichKey.qml`, `components/NotificationToasts.qml`, `overview/Overview.qml` and the per-screen `components/PopupScrim.qml` and `bar/SubmapTab.qml` stay built while hidden. Lazy-load the ones that are rarely shown (WhichKey, Overview) after item 1 proves the pattern.

## Already fine

Lock surfaces, lock skins and their audio, `RegionSelector`, overview thumbnails (`live_cap: 6`), the clipboard caches and the picker `GridView` are already lazy or bounded.
