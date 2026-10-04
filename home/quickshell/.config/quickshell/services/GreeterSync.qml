// home/quickshell/.config/quickshell/services/GreeterSync.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Keeps the login screen's data (LoginScreen's choices, theme, face) in /var/lib/qs-greeter current; does nothing when that directory is absent.
Scope {
    id: root

    readonly property string theme_path: Theme.source_path
    readonly property string face_path: Quickshell.env("HOME") + "/.face"

    function write() {
        if (!LoginScreen.sync || !LoginScreen.installed) return;
        const data = {
            user: Quickshell.env("USER") || "",
            lock_style: LoginScreen.resolved_screen,
            lock_tint: LoginScreen.resolved_tint,
            lock_music: LoginScreen.resolved_music ? "on" : "off",
            watch_colors: Style.watch_mode,
            session: LoginScreen.session,
            music_volume: String(ThemeAudio.music_volume)
        };
        const music = ThemeAudio.login_music_path;
        if (music !== "") {
            data.theme_music = "on";
            data.music_file = "music." + music.split(".").pop();
        }
        Quickshell.execDetached([Quickshell.shellDir + "/scripts/greeter-data", JSON.stringify(data), root.theme_path, root.face_path, music]);
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
        function onInstalledChanged() { root.schedule(); }
        function onResolved_screenChanged() { root.schedule(); }
        function onResolved_tintChanged() { root.schedule(); }
        function onResolved_musicChanged() { root.schedule(); }
        function onSessionChanged() { root.schedule(); }
    }

    Connections {
        target: Theme
        function onSource_pathChanged() { root.schedule(); }
    }

    Connections {
        target: Style
        function onWatch_modeChanged() { root.schedule(); }
    }

    Connections {
        target: ThemeAudio
        function onLogin_music_pathChanged() { root.schedule(); }
        function onMusic_volumeChanged() { root.schedule(); }
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
