// home/quickshell/.config/quickshell/services/WallpaperSettings.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Wallpaper rotator choices saved in wallpaper.json under the Hyprland state dir, and the rotator's own report read back from wallpaper-status.json.
// The rotator polls the settings file, so saving is all it takes to apply a change.
Singleton {
    id: root

    readonly property string settings_path: Paths.hypr_state_dir + "/wallpaper.json"
    readonly property string status_path: Paths.hypr_state_dir + "/wallpaper-status.json"
    readonly property var defaults: ({ rotation: true, interval_minutes: 15, time_of_day_enabled: true, seasons_enabled: true, weather_enabled: true })
    readonly property var interval_choices: [5, 10, 15, 30, 60, 120]
    readonly property string default_collection: Quickshell.env("HOME") + "/Pictures/Wallpapers/Pixel Art"
    readonly property var image_extensions: ["png", "jpg", "jpeg", "webp", "bmp"]

    // wallpaper.json as last read or written; keys this UI does not know are kept when saving.
    property var saved: ({})
    property var status: ({})
    property bool alive: false
    // True while a Settings section is showing, which is when the rotator's pid is worth polling.
    property bool watching: false
    property var images: []
    property bool listing: false
    property string notice: ""

    readonly property var pins: root.saved.pins && typeof root.saved.pins === "object" ? root.saved.pins : ({})
    readonly property var live: root.status.monitors && typeof root.status.monitors === "object" ? root.status.monitors : ({})
    readonly property string collection: typeof root.status.collection === "string" && root.status.collection !== "" ? root.status.collection : root.default_collection
    readonly property bool has_status: typeof root.status.pid === "number"

    signal images_ready

    // The user's saved value, else what the rotator reports it is using, else the default.
    function effective(key) {
        const kind = typeof root.defaults[key];
        if (typeof root.saved[key] === kind && (kind !== "number" || root.saved[key] > 0)) return root.saved[key];
        const used = root.status.settings ? root.status.settings[key] : undefined;
        if (typeof used === kind && (kind !== "number" || used > 0)) return used;
        return root.defaults[key];
    }

    function set_value(key, value) {
        root.saved = Object.assign({}, root.saved, { [key]: value });
        save_timer.restart();
    }

    function set_pin(description, path) {
        root.set_value("pins", Object.assign({}, root.pins, { [description]: path }));
    }

    function clear_pin(description) {
        const next = Object.assign({}, root.pins);
        delete next[description];
        root.set_value("pins", next);
    }

    function say(text) {
        root.notice = text;
        notice_timer.restart();
    }

    // Pins what the monitor shows now. The path is resolved first so the pin matches the collection listing.
    function pin_current(monitor) {
        const entry = root.live[monitor.name];
        const path = entry && typeof entry.path === "string" ? entry.path : "";
        if (path === "") {
            root.say("Nothing is showing on " + monitor.name + " yet");
            return;
        }
        if (resolve_proc.running) return;
        resolve_proc.description = monitor.key;
        resolve_proc.fallback = path;
        resolve_proc.command = ["realpath", "--", path];
        resolve_proc.running = true;
    }

    // New images for every automatic monitor, or just `monitor_name`; the same one-shot run as SUPER+Q W.
    function rotate(monitor_name) {
        const args = monitor_name ? ["--monitor", monitor_name] : ["--once"];
        Quickshell.execDetached(["sh", "-c", "exec lua \"$HOME/.config/hypr/extensions/wallpaper/init.lua\" \"$@\"", "sh"].concat(args));
    }

    // Opens the collection in the TUI file manager from Settings > Default apps, inside the configured terminal, as Leader + Shift + E does.
    // Both choices live in Hyprland's Lua config, hence the eval.
    function open_collection() {
        const quoted = "'" + root.collection.replace(/'/g, "'\\''") + "'";
        Quickshell.execDetached(["hyprctl", "eval", "require('lib.actions.cmd').term(require('config').app.tui_file_manager .. ' ' .. " + JSON.stringify(quoted) + ")()"]);
    }

    function url_of(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function base_name(path) {
        return path.substring(path.lastIndexOf("/") + 1);
    }

    // Lists the collection by real path, so the symlinks that file one image under several folders show once.
    function list_images() {
        if (list_proc.running) return;
        const tests = root.image_extensions.map(e => "-iname '*." + e + "'").join(" -o ");
        root.listing = true;
        list_proc.command = ["sh", "-c", "find -L \"$1\" -type f \\( " + tests + " \\) -exec realpath -- {} + 2>/dev/null | sort -u", "sh", root.collection];
        list_proc.running = true;
    }

    function check_alive() {
        if (!root.has_status || root.status.running === false) {
            root.alive = false;
            return;
        }
        if (!alive_proc.running) {
            alive_proc.command = ["kill", "-0", String(root.status.pid)];
            alive_proc.running = true;
        }
    }

    onStatusChanged: root.check_alive()
    onWatchingChanged: if (root.watching) root.check_alive()

    Timer {
        interval: 5000
        repeat: true
        running: root.watching
        onTriggered: root.check_alive()
    }

    Timer {
        id: notice_timer
        interval: 4000
        onTriggered: root.notice = ""
    }

    Timer {
        id: save_timer
        interval: 300
        onTriggered: {
            if (save_proc.running) {
                save_timer.restart();
                return;
            }
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/wallpaper.json.tmp\" && mv \"$1/wallpaper.json.tmp\" \"$1/wallpaper.json\"",
                "sh", Paths.hypr_state_dir, JSON.stringify(root.saved)];
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
        onExited: code => {
            if (code !== 0) root.say("Could not save wallpaper settings");
        }
    }

    Process {
        id: alive_proc
        onExited: code => root.alive = code === 0
    }

    Process {
        id: resolve_proc
        property string description: ""
        property string fallback: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const real = text.trim();
                root.set_pin(resolve_proc.description, real !== "" ? real : resolve_proc.fallback);
            }
        }
    }

    Process {
        id: list_proc
        stdout: StdioCollector {
            onStreamFinished: {
                root.images = text.split("\n").filter(line => line !== "");
                root.listing = false;
                root.images_ready();
            }
        }
    }

    // A reload during a pending save would swap in the older file and drop the edit.
    FileView {
        path: root.settings_path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (save_timer.running || save_proc.running) return;
            try {
                const data = JSON.parse(text());
                root.saved = data && typeof data === "object" && !Array.isArray(data) ? data : {};
            } catch (e) {
                console.warn("WallpaperSettings: invalid wallpaper.json (" + e + ")");
            }
        }
        onLoadFailed: error => {
            if (!save_timer.running && !save_proc.running) root.saved = {};
        }
    }

    FileView {
        path: root.status_path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.status = data && typeof data === "object" && !Array.isArray(data) ? data : {};
            } catch (e) {
                root.status = {};
            }
        }
        onLoadFailed: error => root.status = {}
    }
}
