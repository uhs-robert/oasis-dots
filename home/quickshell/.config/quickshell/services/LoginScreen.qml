// home/quickshell/.config/quickshell/services/LoginScreen.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// What the login screen shows; "follow" fields take the lock screen's value. Saved in greeter.json under the state dir.
Singleton {
    id: root

    property bool sync: true
    property string screen: "follow"
    property string tint: "follow"
    property string music: "follow"
    property string session: "Hyprland"

    readonly property var musics: ["follow", "on", "off"]
    // Wayland session names from /usr/share/wayland-sessions, Hyprland first.
    property var sessions: ["Hyprland"]
    // False when /var/lib/qs-greeter is missing or not writable, so nothing reaches the greeter.
    property bool installed: false
    readonly property string data_dir: Quickshell.env("QS_GREETER_DATA") || "/var/lib/qs-greeter"

    readonly property string resolved_screen: {
        const name = root.screen === "follow" ? Style.lock_style : root.screen;
        const style_name = name === "follow" ? Style.saved_name : name;
        return style_name !== "simple" && LockSkins.has(style_name) ? style_name : "simple";
    }
    readonly property string resolved_tint: root.tint === "follow" ? Style.lock_tint : root.tint
    readonly property bool resolved_music: root.music === "follow" ? Style.lock_music : root.music === "on"

    function valid_screen(name) {
        return name === "follow" || name === "simple" || LockSkins.names.indexOf(name) >= 0;
    }

    function probe() {
        if (!probe_proc.running) probe_proc.running = true;
    }

    function set_sync(on) {
        root.sync = on;
        if (on) root.probe();
        root.save();
    }

    function set_screen(name) {
        if (!root.valid_screen(name)) return false;
        root.screen = name;
        root.save();
        return true;
    }

    function set_tint(name) {
        if (name !== "follow" && Style.lock_tints.indexOf(name) < 0) return false;
        root.tint = name;
        root.save();
        return true;
    }

    function set_music(value) {
        if (root.musics.indexOf(value) < 0) return false;
        root.music = value;
        root.save();
        return true;
    }

    function set_session(name) {
        root.session = name;
        root.save();
    }

    function save() {
        state_file.setText(JSON.stringify({ sync: root.sync, screen: root.screen, tint: root.tint, music: root.music, session: root.session }));
    }

    FileView {
        id: state_file
        path: Style.state_dir + "/greeter.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.sync = data.sync !== false;
                if (typeof data.screen === "string") root.screen = data.screen;
                if (data.tint === "follow" || Style.lock_tints.indexOf(data.tint) >= 0) root.tint = data.tint;
                if (root.musics.indexOf(data.music) >= 0) root.music = data.music;
                if (typeof data.session === "string" && data.session !== "") root.session = data.session;
            } catch (e) {
                console.warn("LoginScreen: invalid greeter.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    Process {
        id: probe_proc
        running: true
        command: ["test", "-d", root.data_dir, "-a", "-w", root.data_dir]
        onExited: code => root.installed = code === 0
    }

    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do sed -n 's/^Name=//p' \"$f\" | head -n1; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").filter(n => n !== "");
                names.sort((a, b) => (b === "Hyprland") - (a === "Hyprland"));
                if (names.length > 0) root.sessions = names;
            }
        }
    }
}
