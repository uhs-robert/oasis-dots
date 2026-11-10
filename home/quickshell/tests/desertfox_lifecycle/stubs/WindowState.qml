pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Stands in for features/windows/WindowState: the focused window's address comes from $XDG_RUNTIME_DIR/focus.txt, as
// WindowState derives it from focus history before Hyprland's first focus event. Two windows exist: 0x1 is Firefox.
Singleton {
    id: root

    property string active_address: ""
    readonly property var windows: [{ address: "0x1", cls: "firefox" }, { address: "0x2", cls: "foot" }]

    function class_of(toplevel) {
        return toplevel ? toplevel.cls : "";
    }

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/focus.txt"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.active_address = text().trim()
    }
}
