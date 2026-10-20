pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Default apps saved in apps.json under the Hyprland state dir; Hyprland reads `app`, apps.sh applies `mime` through xdg-mime.
Singleton {
    id: root

    readonly property string state_dir: Paths.hypr_state_dir

    // Config.app keys; an empty choice leaves the machine profile's value.
    readonly property var app_keys: [
        { key: "term", label: "Terminal" },
        { key: "editor", label: "Editor" },
        { key: "gui_file_manager", label: "File manager (GUI)" },
        { key: "tui_file_manager", label: "File manager (TUI)" }
    ]
    readonly property var mime_keys: [
        { key: "web", label: "Web browser" },
        { key: "mail", label: "Mail" },
        { key: "pdf", label: "PDF viewer" },
        { key: "images", label: "Images" },
        { key: "video", label: "Video" },
        { key: "audio", label: "Audio" },
        { key: "text", label: "Text files" },
        { key: "directories", label: "Directories" }
    ]

    readonly property var app: store.values.app
    readonly property var mime: store.values.mime
    property var found: ({ mime: {}, app: {} })
    property bool reload_pending: false

    function names_of(group) {
        const entry = root.found.mime[group];
        return entry && entry.options ? entry.options : [];
    }

    function app_value(key) {
        return root.app[key] || "";
    }

    function app_choices(key) {
        const list = [""].concat(root.found.app[key] || []);
        const current = root.app_value(key);
        if (current !== "" && list.indexOf(current) < 0) list.push(current);
        return list;
    }

    // Shows `path` in the Directories default, the same app other programs open folders with.
    function open_folder(path) {
        Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/apps.sh\" open-folder \"$1\"", "sh", path]);
    }

    function mime_value(group) {
        if (root.mime[group]) return root.mime[group];
        const entry = root.found.mime[group];
        return entry && entry.current ? entry.current : "";
    }

    function mime_choices(group) {
        const list = root.names_of(group).map(o => o.id);
        const current = root.mime_value(group);
        if (current !== "" && list.indexOf(current) < 0) list.push(current);
        return list;
    }

    function mime_text(group, id) {
        if (id === "") return "None";
        const hit = root.names_of(group).find(o => o.id === id);
        return hit && hit.name ? hit.name : id.replace(/\.desktop$/, "");
    }

    function set_app(key, value) {
        const next = Object.assign({}, root.app);
        if (value === "") delete next[key];
        else next[key] = value;
        root.reload_pending = true;
        store.set_key("app", next);
    }

    function set_mime(group, id) {
        store.set_key("mime", Object.assign({}, root.mime, { [group]: id }));
    }

    function refresh() {
        if (!dump_proc.running) dump_proc.running = true;
    }

    Process {
        id: dump_proc
        command: ["sh", "-c", "\"$HOME/.config/hypr/scripts/apps.sh\" dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.found = { mime: data.mime || {}, app: data.app || {} };
                } catch (e) {
                    console.warn("DefaultAppsSettings: apps.sh dump failed (" + e + ")");
                }
            }
        }
    }

    JsonStore {
        id: store
        path: root.state_dir + "/apps.json"
        defaults: ({ app: {}, mime: {} })
        debounce_ms: 600
        validate: raw => {
            const clean = obj => {
                const out = {};
                for (const key in obj || {}) {
                    if (typeof obj[key] === "string" && obj[key] !== "") out[key] = obj[key];
                }
                return out;
            };
            return { app: clean(raw.app), mime: clean(raw.mime) };
        }
        // An `if`, not `&&`: with no reload wanted the command must not exit 1.
        after_save: values => {
            const reload = root.reload_pending ? "1" : "0";
            root.reload_pending = false;
            return ["sh", "-c", '"$HOME/.config/hypr/scripts/apps.sh" apply; if [ "$1" = 1 ]; then hyprctl reload; fi', "sh", reload];
        }
    }

    Component.onCompleted: root.refresh()
}
