# Performance TODO

Quickshell memory and CPU work, biggest win first. Paths are relative to `home/quickshell/.config/quickshell/` unless noted.

## Numbers (2026-09-29, 4 monitors, 150 s after start)

| Build | RSS | Anonymous | Threads |
| --- | --- | --- | --- |
| `main` (stowed, some popups opened) | 1.26 GB | 1.07 GB | 110 |
| Lazy popups (item 1) | ~575 MB | ~373 MB | ~67 |
| Plus lazy theme audio and no glthread (items 6, 2) | ~480 MB | ~323 MB | ~53 |

Where the rest goes, from stripped-down configs: a bare `ShellRoot {}` is 155 MB (46 MB anonymous, mostly Qt, Mesa and fonts); each bar window adds ~26-28 MB, the same as an empty `PanelWindow`, so it is driver and window cost rather than bar content; the shared QML types, singletons and services are ~140 MB; the pickers' providers and the always-built overlays (Osd, WhichKey, toasts, Overview) are ~0 and ~11 MB. `malloc_trim` frees nothing, so none of it is allocator waste. Measure with:

```bash
p=$(pgrep -xn qs); ps -o etime=,rss= -p $p; grep -E 'Anonymous|AnonHuge' /proc/$p/smaps_rollup; ls /proc/$p/task | wc -l
```

## Done

- [x] **1. Build popups on open, drop them after close.** `components/LazyPopup.qml` wraps the 17 bar popups; `Popups.load_name` is set just before `open_name`, so a popup is built closed and sees the open as a change. `HyprvimPrompt` (owns an `IpcHandler`) and `TooltipShelf` (hover-driven) stay eager. Popups no longer remember their tab or section between opens.
- [x] **2. Mesa glthread off.** `//@ pragma Env mesa_glthread=false` in `shell.qml`: ~20 MB and 8 threads less, no visible cost for a bar's small draws.
- [x] **6. QtMultimedia only when sounds are on.** Any `SoundEffect` or `MediaPlayer` loads the FFmpeg backend for the whole process. `services/ThemeAudio.qml` now builds its effects only while UI or notification sounds are on, and its music player only while lock music plays: ~75 MB less with sounds off.
- [x] **8. Album art at drawn size.** `popups/MediaPopup.qml` sets `sourceSize` (half width for the blurred backdrop).
- [x] **9. Notification images at drawn size.** `NotificationCard`, `NotificationToastCard` and the notifications popup header icon set `sourceSize`.
- [x] **11. Notification history capped at 100.** Entries past the cap are dismissed so the server frees them and their images, including history restored on reload.
- [x] **13. Voxtype peaks.** Already a fixed ring buffer.

## Tried, not worth it

- **`MALLOC_ARENA_MAX=2`:** no change.
- **THP off for qs (`prctl(PR_SET_THP_DISABLE)` wrapper):** one run came out at 743 MB, no sign of a gain; left THP `always`. Needs a clean rerun before ruling it out.
- **Mesa-only EGL (`__EGL_VENDOR_LIBRARY_FILENAMES=.../50_mesa.json`):** -40 MB RSS, but ~32 MB of that is shared, reclaimable NVIDIA library pages, and it would break rendering on an NVIDIA-only machine. qs already renders on the AMD iGPU.
- **`QSG_RENDER_LOOP=basic`:** -10 MB, at the risk of animations stalling while the GUI thread is busy.
- **`QSG_RHI_BACKEND=vulkan`:** +10 MB over OpenGL.
- **Lazy WhichKey, Overview, Osd, toasts (old item 14):** all of them together cost ~11 MB.
- **Pickers' providers:** ~0 MB.
- **Bundled fonts (old item 7):** 5.4 MB on disk, and loading them on demand would relayout text on every style switch and preview.

## Open

- [ ] **Early memory jump.** One dev run was 481 MB at 11 s and 815 MB about a minute later, before any popup opened; cycling all 16 popups 5 times after that settled at ~846 MB with no errors and no further growth. Other runs read ~480 MB at 150 s, so this is either a transient startup peak or something that fires once (weather, updates, clipboard, usage fetches). Sample every 2 s through the first 3 minutes to see the curve, then bisect services.
- [ ] **Idle redraws.** At idle each bar renders ~2 frames a second: one from the clock's seconds (`bar/modules/Clock.qml`, `SystemClock.Seconds`) and one from a source not found yet. Idle CPU is ~1 s per minute, split between the render threads and the GUI thread. Find the second source with the frame log (`QT_LOGGING_RULES=qt.scenegraph.time.renderloop.debug=true`) by removing bar modules one at a time in a copy of the config.
- [ ] **Per-window driver cost.** ~26 MB per bar window, from radeonsi. Nothing to do in QML short of fewer bars; revisit if Qt or Mesa change.
- [ ] **5. Only build the shown weather tab.** Now only matters while the weather popup is open. `day_span` reads `daily_view.fit_days` on every tab, so Daily needs care.
- [ ] **10. Glow layers.** `components/Popup.qml:642` layers the whole frame in glow or text-shadow styles; Osd, WhichKey and Meter do the same. Only matters in those styles.
- [ ] **12. Notification array rebuilds.** `NotificationState` rebuilds whole arrays on each change and the popup rebuilds every row. CPU churn more than memory now that history is capped.
- [ ] **Redundant Hyprland refreshes.** Each bar's `bar/modules/Workspaces.qml` calls `Hyprland.refreshToplevels()`/`refreshWorkspaces()` on every window event, so 4 bars send 4 requests per event.

## Already fine

Lock surfaces, lock skins and their audio, `RegionSelector`, overview thumbnails (`live_cap: 6`), the clipboard caches, the picker `GridView` and the voxtype ring buffer are already lazy or bounded.
