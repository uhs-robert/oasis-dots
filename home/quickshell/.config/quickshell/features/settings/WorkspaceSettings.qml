pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// How many persistent workspaces a monitor gets, saved in workspaces.json under the Hyprland state dir.
// lib/workspace_layout.lua in the Hyprland config reads it. Unsaved keys show Hyprland's live value, so a machine
// profile's count reads correctly until it is overridden.
Singleton {
    id: root

    readonly property var counts: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    // Config's defaults until Hyprland answers. per_monitor is false when the profile turned persistent workspaces off.
    property var live: ({ per_monitor: 5, single_monitor: 10 })
    readonly property bool enabled: root.live.per_monitor !== false

    function value(key) {
        return store.values[key] !== undefined ? store.values[key] : root.live[key];
    }

    function set(key, count) {
        store.set_key(key, count);
    }

    Component.onCompleted: live_proc.running = true

    // A reload can change the profile's counts or turn persistent workspaces off.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") live_proc.running = true;
        }
    }

    Process {
        id: live_proc
        // hyprctl eval prints nothing back, so Hyprland writes the values to a file.
        command: ["sh", "-c", 'hyprctl eval "$1" >/dev/null && cat "$XDG_RUNTIME_DIR/qs-workspace-config"', "sh",
            "local c = require('config'); local f = io.open(os.getenv('XDG_RUNTIME_DIR') .. '/qs-workspace-config', 'w'); "
            + "f:write(string.format('{\"per_monitor\":%s,\"single_monitor\":%d}', type(c.persistent_workspaces) == 'number' and c.persistent_workspaces or 'false', c.single_monitor_workspaces or 10)); f:close()"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Empty when Hyprland runs without this config (a nested test session); the defaults stand.
                if (text.trim() === "") return;
                try {
                    const o = JSON.parse(text);
                    root.live = { per_monitor: o.per_monitor, single_monitor: o.single_monitor };
                } catch (e) {
                    console.warn("WorkspaceSettings: unreadable Hyprland answer (" + e + ")");
                }
            }
        }
    }

    JsonStore {
        id: store
        path: Paths.hypr_state_dir + "/workspaces.json"
        known_keys: ["per_monitor", "single_monitor"]
        validate: raw => {
            const next = {};
            for (const key of ["per_monitor", "single_monitor"]) {
                if (root.counts.indexOf(raw[key]) >= 0) next[key] = raw[key];
            }
            return next;
        }
        after_save: values => ["hyprctl", "eval", 'require("config.monitors").apply()']
        onAfter_save_done: live_proc.running = true
    }
}
