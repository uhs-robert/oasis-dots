// home/quickshell/.config/quickshell/services/DefaultApps.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

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

    property var app: ({})
    property var mime: ({})
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
        root.app = next;
        root.reload_pending = true;
        save_timer.restart();
    }

    function set_mime(group, id) {
        root.mime = Object.assign({}, root.mime, { [group]: id });
        save_timer.restart();
    }

    function refresh() {
        if (!dump_proc.running) dump_proc.running = true;
    }

    Timer {
        id: save_timer
        interval: 600
        onTriggered: {
            if (save_proc.running) {
                save_timer.restart();
                return;
            }
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/apps.json.tmp\" && mv \"$1/apps.json.tmp\" \"$1/apps.json\" && \"$HOME/.config/hypr/scripts/apps.sh\" apply; [ \"$3\" = 1 ] && hyprctl reload",
                "sh", root.state_dir, JSON.stringify({ app: root.app, mime: root.mime }), root.reload_pending ? "1" : "0"];
            root.reload_pending = false;
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
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
                    console.warn("DefaultApps: apps.sh dump failed (" + e + ")");
                }
            }
        }
    }

    FileView {
        path: root.state_dir + "/apps.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const clean = obj => {
                    const out = {};
                    for (const key in obj || {}) {
                        if (typeof obj[key] === "string" && obj[key] !== "") out[key] = obj[key];
                    }
                    return out;
                };
                root.app = clean(data.app);
                root.mime = clean(data.mime);
            } catch (e) {
                console.warn("DefaultApps: invalid apps.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    Component.onCompleted: root.refresh()
}
