import QtQuick
import Quickshell
import qs.core
import qs.theme
import "../../ui/frames/Corners.js" as Corners

// Writes the Corner style (frame.json in the state dir) and then runs scripts/frame-app-corners, which turns it into
// yazi's border and Firefox's chrome/frame.css, with the frame on or off. Those apps read them at start-up, so a change
// shows after a restart.
Scope {
    id: root

    readonly property var profile: Style.corner_profile
    // The corner as drawn (fitted to its cap), like ScreenFrameSync sends Hyprland.
    readonly property var drawn: Corners.fit(root.profile.corner, root.profile.radius, root.profile.step)
    // `on` is whether a frame is drawn; the corner is always set.
    // Without a frame and without a picked Corner style the corner is empty, which leaves Firefox and yazi at their own.
    readonly property var snapshot: Style.corner_sent ? { on: ScreenFrames.any_frame, corner: root.profile.corner, radius: root.drawn.radius } : { on: false, corner: "", radius: 0 }

    onSnapshotChanged: if (store.loaded_once) store.replace(root.snapshot)

    JsonStore {
        id: store
        path: Paths.state_dir + "/frame.json"
        defaults: ({ on: false, corner: "", radius: 0 })
        watch: false
        // The style picker previews frames as it moves, so only the frame it settles on is written.
        debounce_ms: 300
        after_save: values => [Quickshell.shellDir + "/scripts/frame-app-corners", store.path]
        onLoaded: store.replace(root.snapshot)
        // Nothing else shows a failed generator run, and the apps would keep their old corners without a word.
        onAfter_save_done: code => { if (code !== 0) console.warn("frame-app-corners failed with exit code " + code) }
    }
}
