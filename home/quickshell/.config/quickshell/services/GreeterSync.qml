// home/quickshell/.config/quickshell/services/GreeterSync.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Keeps the login screen's data (LoginScreen's choices, theme, face) in /var/lib/qs-greeter current; does nothing when that directory is absent.
Scope {
    id: root

    readonly property string theme_path: Quickshell.shellDir + "/theme/theme.json"
    readonly property string face_path: Quickshell.env("HOME") + "/.face"

    function write() {
        if (!LoginScreen.sync) return;
        const data = {
            user: Quickshell.env("USER") || "",
            lock_style: LoginScreen.resolved_screen,
            lock_tint: LoginScreen.resolved_tint,
            lock_music: LoginScreen.resolved_music ? "on" : "off",
            session: LoginScreen.session
        };
        Quickshell.execDetached([Quickshell.shellDir + "/scripts/greeter-data", JSON.stringify(data), root.theme_path, root.face_path]);
    }

    function schedule() {
        if (LockSkins.ready) debounce.restart();
    }

    Timer {
        id: debounce
        interval: 1500
        onTriggered: root.write()
    }

    Connections {
        target: LockSkins
        function onReadyChanged() { root.schedule(); }
    }

    Connections {
        target: LoginScreen
        function onSyncChanged() { root.schedule(); }
        function onResolved_screenChanged() { root.schedule(); }
        function onResolved_tintChanged() { root.schedule(); }
        function onResolved_musicChanged() { root.schedule(); }
        function onSessionChanged() { root.schedule(); }
    }

    FileView {
        path: root.theme_path
        watchChanges: true
        printErrors: false
        onFileChanged: root.schedule()
    }

    FileView {
        path: root.face_path
        watchChanges: true
        printErrors: false
        onFileChanged: root.schedule()
    }
}
