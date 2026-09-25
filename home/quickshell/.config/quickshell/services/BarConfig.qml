// home/quickshell/.config/quickshell/services/BarConfig.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../theme"

Singleton {
    id: root

    // Every monitor gets the same layout for now; bars.json can split this by name/description later.
    readonly property var default_rules: [
        {
            match: "*",
            compact: false,
            left: ["start", "workspaces"],
            center: ["clock"],
            right: ["tray", "volume", "battery", "system", "network", "bluetooth"]
        }
    ]

    property var rules: default_rules
    property var warned_modules: ({})

    FileView {
        id: config_file
        path: Quickshell.shellDir + "/bars.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (!Array.isArray(parsed)) throw new Error("bars.json must be a JSON array of rules");
                root.rules = parsed;
            } catch (e) {
                console.warn("BarConfig: invalid bars.json, keeping last config (" + e + ")");
            }
        }
        onLoadFailed: error => console.warn("BarConfig: failed to load bars.json (" + error + "), using defaults")
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

    // Returns the first matching rule for a screen, or null (with a warning) when nothing matches.
    function rule_for(screen) {
        const screen_name = screen.name;
        const description = root.description_for(screen);
        for (const rule of root.rules) {
            if (root.rule_matches(rule, screen_name, description)) return rule;
        }
        console.warn("BarConfig: no bars.json rule matched screen \"" + screen_name + "\"; no bar shown");
        return null;
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
