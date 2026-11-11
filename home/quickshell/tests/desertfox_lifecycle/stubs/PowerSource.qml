pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// On AC unless $XDG_RUNTIME_DIR/ac.txt holds 0, so run.py can switch power.
Singleton {
    id: root
    property bool on_ac: true

    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ac.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.on_ac = text().trim() !== "0"
    }
}
