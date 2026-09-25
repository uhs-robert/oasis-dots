// home/quickshell/.config/quickshell/services/Pickers.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../theme"

Singleton {
    id: root

    property var providers: ({})
    property string provider_name: ""
    property string provider_arg: ""
    readonly property var provider: root.providers[root.provider_name] || null
    readonly property bool is_open: Popups.open_name === "picker"

    // provider_key -> { count, last_ms }
    property var usage: ({})
    readonly property real half_life_days: 14

    signal step_requested(int delta)

    function register(provider) {
        const next = Object.assign({}, root.providers);
        next[provider.name] = provider;
        root.providers = next;
    }

    // With an anchor it drops from that island like a popup; without one it docks at the bottom of the focused monitor.
    // `arg` reaches the provider's refresh(), e.g. a mode like "move".
    function open(name, anchor_item, color, screen_name, back_to, arg) {
        const p = root.providers[name];
        if (!p) {
            console.warn("Pickers: unknown provider " + name);
            return false;
        }
        if (p.repeat_steps && root.is_open && root.provider_name === name && root.provider_arg === (arg || "") && !anchor_item) {
            root.step_requested(1);
            return true;
        }
        // Closing first resets the query and moves a docked picker to the now-focused monitor.
        root.close();
        root.provider_name = name;
        root.provider_arg = arg || "";
        p.refresh(arg || "");
        if (anchor_item) {
            Popups.open("picker", anchor_item, color, screen_name, back_to);
        } else {
            const mon = Hyprland.focusedMonitor;
            const screen = (mon && Quickshell.screens.find(s => s.name === mon.name)) || Quickshell.screens[0];
            Popups.open("picker", null, color, screen ? screen.name : "", back_to);
        }
        return true;
    }

    function close() {
        if (root.is_open) Popups.close();
    }

    function toggle(name, anchor_item, color, screen_name) {
        if (root.is_open && root.provider_name === name) {
            root.close();
            return true;
        }
        return root.open(name, anchor_item, color, screen_name);
    }

    function frecency(provider_name, id) {
        const u = root.usage[provider_name + ":" + id];
        if (!u) return 0;
        const age_days = (Date.now() - u.last_ms) / 86400000;
        return u.count * Math.pow(0.5, age_days / root.half_life_days);
    }

    function record(provider_name, id) {
        const next = {};
        for (const k in root.usage) {
            const sep = k.indexOf(":");
            if (root.frecency(k.slice(0, sep), k.slice(sep + 1)) >= 0.05) next[k] = root.usage[k];
        }
        next[provider_name + ":" + id] = { count: root.frecency(provider_name, id) + 1, last_ms: Date.now() };
        root.usage = next;
        usage_file.setText(JSON.stringify(next));
    }

    FileView {
        id: usage_file
        path: Style.state_dir + "/picker_usage.json"
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data && typeof data === "object") root.usage = data;
            } catch (e) {
                console.warn("Pickers: invalid picker_usage.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }
}
