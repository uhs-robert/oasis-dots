import QtQuick
import Quickshell
import Quickshell.Io
import qs.features.desertfox

// Harness shell for run.py: loads the real DesertfoxState and NowPlayingState (stubs stand in for Theme, WindowState,
// VoxSessionState and PowerSource) and prints one `STATE` line to stdout whenever any of what the bar reads from them
// changes, for run.py to wait on. The file $XDG_RUNTIME_DIR/mount.txt holds 1 while a now-playing module is mounted.
ShellRoot {
    id: root

    readonly property string line: "STATE live=" + (DesertfoxState.live ? 1 : 0) + " shown=" + (DesertfoxState.shown ? 1 : 0)
        + " chip=" + DesertfoxState.chip_label + " streaming=" + (NowPlayingState.streaming ? 1 : 0) + " now=" + NowPlayingState.label
    onLineChanged: console.log(root.line)

    FileView {
        id: mount
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mount.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply_mount(mount.text().trim() === "1")
    }

    property bool mounted: false
    function apply_mount(on: bool): void {
        if (on === root.mounted) return;
        root.mounted = on;
        NowPlayingState.mounted_modules += on ? 1 : -1;
    }
}
