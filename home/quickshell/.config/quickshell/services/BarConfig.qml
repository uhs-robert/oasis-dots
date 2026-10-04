// home/quickshell/.config/quickshell/services/BarConfig.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../theme"
import "BarLayout.js" as BarLayout

Singleton {
    id: root

    property var rules: []
    property bool has_good_rules: false
    property bool rules_loaded: false
    readonly property var emergency_rules: [{ match: "*", compact: true, left: ["workspaces"], center: ["clock"], right: ["tray"] }]
    property var warned_modules: ({})
    property var state: BarLayout.normalize(null)
    property bool warned_state: false

    FileView {
        id: config_file
        path: Quickshell.shellDir + "/bars.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (!Array.isArray(parsed)) throw new Error("bars.json must be a JSON array of rules");
                root.rules = parsed;
                root.has_good_rules = true;
                root.rules_loaded = true;
            } catch (e) {
                root.rules_failed("invalid (" + e + ")");
            }
        }
        onLoadFailed: error => root.rules_failed("unreadable (" + error + ")")
    }

    FileView {
        id: state_file
        path: Style.state_dir + "/bars.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.state = BarLayout.normalize(text().trim() === "" ? null : JSON.parse(text()));
            } catch (e) {
                if (!root.warned_state) console.warn("BarConfig: invalid state bars.json, ignoring it (" + e + ")");
                root.warned_state = true;
                root.state = BarLayout.normalize(null);
            }
        }
        onLoadFailed: error => root.state = BarLayout.normalize(null)
    }

    function rules_failed(reason) {
        root.rules_loaded = true;
        const message = "bars.json " + reason;
        if (root.has_good_rules) {
            console.warn("BarConfig: " + message + ", keeping last config");
            return;
        }
        console.warn("BarConfig: " + message + ", showing the emergency bar");
        root.rules = root.emergency_rules;
        Quickshell.execDetached(["notify-send", "-u", "critical", "Quickshell bar", message + ". Showing a minimal bar until it is fixed."]);
    }

    function set_state(next) {
        root.state = BarLayout.normalize(next);
        state_file.setText(JSON.stringify(root.state));
    }

    function monitor_key(screen) {
        return BarLayout.resolve_key(root.state, root.description_for(screen), screen.name, Quickshell.screens.map(s => ({ name: s.name, description: root.description_for(s) })));
    }

    function glob_to_regex(pattern) {
        let source = "^";
        for (const ch of pattern) {
            if (ch === "*") source += ".*";
            else if (ch === "?") source += ".";
            else source += ch.replace(/[.+^${}()|[\]\\]/g, "\\$&");
        }
        return new RegExp(source + "$");
    }

    function glob_match(pattern, value) {
        return root.glob_to_regex(pattern).test(value || "");
    }

    // Prefers Hyprland's monitor description (what Waybar matched on); falls back to Qt's model string.
    function description_for(screen) {
        const monitor = Hyprland.monitorFor(screen);
        if (monitor && monitor.description) return monitor.description;
        return screen.model || "";
    }

    function rule_matches(rule, screen_name, description) {
        if (rule.match === "*") return true;
        if (typeof rule.match !== "object" || rule.match === null) return false;
        const has_name = "name" in rule.match;
        const has_description = "description" in rule.match;
        if (!has_name && !has_description) return false;
        if (has_name && !root.glob_match(rule.match.name, screen_name)) return false;
        if (has_description && !root.glob_match(rule.match.description, description)) return false;
        return true;
    }

    // Returns the first tracked rule matching a screen, or null.
    function tracked_rule_for(screen) {
        const screen_name = screen.name;
        const description = root.description_for(screen);
        for (const rule of root.rules) {
            if (root.rule_matches(rule, screen_name, description)) return rule;
        }
        return null;
    }

    // The tracked rule with the state file's layout merged in, or null (with a warning) when nothing matches.
    function rule_for(screen) {
        if (!root.rules_loaded) return null;
        const tracked = root.tracked_rule_for(screen);
        if (!tracked) {
            console.warn("BarConfig: no bars.json rule matched screen \"" + screen.name + "\"; no bar shown");
            return null;
        }
        return BarLayout.effective(tracked, root.state, root.monitor_key(screen));
    }

    readonly property int default_height: 34

    function height_for(rule) {
        return rule && rule.height > 0 ? rule.height : Style.bar_height > 0 ? Style.bar_height : root.default_height;
    }

    function compact_for(rule, screen_name) {
        if (rule && rule.compact !== undefined) return rule.compact;
        return screen_name.indexOf("eDP") === 0;
    }

    // Splits "system:temperature" into { base: "system", arg: "temperature" }.
    function parse_module(entry) {
        const idx = entry.indexOf(":");
        if (idx === -1) return { base: entry, arg: "" };
        return { base: entry.slice(0, idx), arg: entry.slice(idx + 1) };
    }

    function warn_unknown_module(name) {
        if (root.warned_modules[name]) return;
        root.warned_modules[name] = true;
        console.warn("BarConfig: unknown module \"" + name + "\" in bars.json; skipping");
    }
}
