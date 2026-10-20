pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.theme

// What the login screen shows; "follow" fields take the lock screen's value. Saved in greeter.json under the state dir.
Singleton {
    id: root

    readonly property bool sync: store.values.sync
    readonly property string screen: store.values.screen
    readonly property string tint: store.values.tint
    readonly property string music: store.values.music
    readonly property string session: store.values.session

    readonly property var musics: ["follow", "on", "off"]
    // Wayland session names from /usr/share/wayland-sessions, Hyprland first.
    property var sessions: ["Hyprland"]
    // False when /var/lib/qs-greeter is missing or not writable, so nothing reaches the greeter.
    property bool installed: false
    readonly property string data_dir: "/var/lib/qs-greeter"

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
        if (on) root.probe();
        store.set_key("sync", on);
    }

    function set_screen(name) {
        if (!root.valid_screen(name)) return false;
        store.set_key("screen", name);
        return true;
    }

    function set_tint(name) {
        if (name !== "follow" && Style.lock_tints.indexOf(name) < 0) return false;
        store.set_key("tint", name);
        return true;
    }

    function set_music(value) {
        if (root.musics.indexOf(value) < 0) return false;
        store.set_key("music", value);
        return true;
    }

    function set_session(name) {
        store.set_key("session", name);
    }

    JsonStore {
        id: store
        path: Paths.state_dir + "/greeter.json"
        defaults: ({ sync: true, screen: "follow", tint: "follow", music: "follow", session: "Hyprland" })
        // A field that fails its check keeps the value it has now, as the loader always did.
        validate: raw => ({
            sync: raw.sync !== false,
            screen: typeof raw.screen === "string" ? raw.screen : root.screen,
            tint: raw.tint === "follow" || Style.lock_tints.indexOf(raw.tint) >= 0 ? raw.tint : root.tint,
            music: root.musics.indexOf(raw.music) >= 0 ? raw.music : root.music,
            session: typeof raw.session === "string" && raw.session !== "" ? raw.session : root.session
        })
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
