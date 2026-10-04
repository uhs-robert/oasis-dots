// home/quickshell/.config/quickshell/services/PowerSettings.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../theme"

// Power choices saved in power.json under the Hyprland state dir; power.sh turns them into hypridle, logind and power-profile settings.
Singleton {
    id: root

    readonly property string state_dir: Paths.hypr_state_dir

    readonly property bool laptop: !!UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery

    // Seconds; 0 never. The defaults match the tracked hypridle.conf.
    readonly property var idle_defaults: ({ dim: 150, lock: 300, screen_off: 0, suspend: 0 })
    readonly property var lid_actions: ["suspend", "lock", "poweroff", "ignore"]
    readonly property var button_actions: ["poweroff", "suspend", "lock", "ignore"]
    readonly property var profiles: PowerProfiles.hasPerformanceProfile ? ["keep", "power-saver", "balanced", "performance"] : ["keep", "power-saver", "balanced"]
    readonly property var idle_steps: [0, 30, 60, 120, 150, 180, 300, 600, 900, 1800, 3600, 7200]

    property var values: root.defaults()

    function defaults() {
        const out = { lid_ac: "suspend", lid_battery: "suspend", power_button: "poweroff", profile_ac: "keep", profile_battery: "keep" };
        for (const name in root.idle_defaults) {
            out[name + "_ac"] = root.idle_defaults[name];
            out[name + "_battery"] = root.idle_defaults[name];
        }
        return out;
    }

    function idle_choices(key) {
        const list = root.idle_steps.slice();
        const current = root.values[key];
        if (list.indexOf(current) < 0) {
            list.push(current);
            list.sort((a, b) => a - b);
        }
        return list;
    }

    function duration_text(seconds) {
        if (seconds === 0) return "Never";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds % 3600 / 60);
        const s = seconds % 60;
        return [h > 0 ? h + "h" : "", m > 0 ? m + "m" : "", s > 0 ? s + "s" : ""].filter(p => p !== "").join(" ");
    }

    function set(key, value) {
        root.values = Object.assign({}, root.values, { [key]: value });
        save_timer.restart();
    }

    function profile_of(key) {
        const value = root.values[key];
        return root.profiles.indexOf(value) >= 0 ? value : "keep";
    }

    function valid(key, value) {
        if (key === "power_button") return root.button_actions.indexOf(value) >= 0;
        if (key.indexOf("lid_") === 0) return root.lid_actions.indexOf(value) >= 0;
        if (key.indexOf("profile_") === 0) return ["keep", "power-saver", "balanced", "performance"].indexOf(value) >= 0;
        return Number.isInteger(value) && value >= 0;
    }

    Timer {
        id: save_timer
        interval: 700
        onTriggered: {
            if (save_proc.running) {
                save_timer.restart();
                return;
            }
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/power.json.tmp\" && mv \"$1/power.json.tmp\" \"$1/power.json\" && \"$HOME/.config/hypr/scripts/power.sh\" apply",
                "sh", root.state_dir, JSON.stringify(root.values)];
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
    }

    FileView {
        path: root.state_dir + "/power.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const next = root.defaults();
                for (const key in next) {
                    if (root.valid(key, data[key])) next[key] = data[key];
                }
                root.values = next;
            } catch (e) {
                console.warn("PowerSettings: invalid power.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }
}
