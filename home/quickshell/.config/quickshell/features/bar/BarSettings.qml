pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.theme
import "BarLayout.js" as BarLayout

Singleton {
    id: root

    property var rules: []
    property bool has_good_rules: false
    property bool rules_loaded: false
    readonly property var emergency_rules: [{ match: "*", compact: true, left: ["workspaces"], center: ["clock"], right: ["tray"] }]
    property var warned_modules: ({})
    property var warned_positions: ({})
    property var state: BarLayout.normalize(null)

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

    // The layout state (bars.json under the state dir). The store owns writing and reloading: a set in memory beats an
    // echo of an older write, and a burst of edits (the bar editor moving a bar edge per key) lands as one write.
    JsonStore {
        id: store
        path: Paths.state_dir + "/bars.json"
        defaults: BarLayout.normalize(null)
        known_keys: ["shared", "monitors", "positions", "directory", "cava_migrated"]
        debounce_ms: 100
        validate: raw => BarLayout.normalize(raw)
        onLoaded: root.adopt_loaded()
    }

    // The store may have finished loading before its change handler was connected.
    Component.onCompleted: if (store.loaded_once) root.adopt_loaded()

    // A load is the first read or an edit from outside; our own writes never come back as one.
    function adopt_loaded() {
        const loaded = store.values;
        root.state = loaded;
        let next = loaded;
        // A missing file has nothing to migrate.
        if (!loaded.cava_migrated && Object.keys(store.raw).length > 0) next = BarLayout.migrate_cava(next);
        next = BarLayout.migrate_cava_to_media(next);
        if (next !== loaded) root.set_state(next);
    }

    function rules_failed(reason) {
        root.rules_loaded = true;
        const message = "bars.json " + reason;
        if (root.has_good_rules) {
            console.warn("BarSettings: " + message + ", keeping last config");
            return;
        }
        console.warn("BarSettings: " + message + ", showing the emergency bar");
        root.rules = root.emergency_rules;
        Quickshell.execDetached(["notify-send", "-u", "critical", "Quickshell bar", message + ". Showing a minimal bar until it is fixed."]);
    }

    function set_state(next) {
        // Anything this build writes is past the one-time cava migration.
        root.state = Object.assign(BarLayout.normalize(next), { cava_migrated: true });
        store.replace(root.state);
    }

    readonly property var directory_switches: BarLayout.directory_switches(root.state)

    function set_directory_switch(name, on) {
        root.set_state(BarLayout.set_directory_switch(root.state, name, on));
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
            console.warn("BarSettings: no bars.json rule matched screen \"" + screen.name + "\"; no bar shown");
            return null;
        }
        return BarLayout.effective(tracked, root.state, root.monitor_key(screen));
    }

    readonly property int default_height: 34

    function height_for(rule) {
        return BarLayout.thickness_for(rule ? rule.height : 0, Style.bar_height, Style.bar_height_vertical, BarLayout.position_of(rule), root.default_height);
    }

    function compact_for(rule) {
        return !!(rule && rule.compact);
    }

    // "top" or "bottom"; warns once per unsupported value.
    function position_for(rule) {
        const problem = BarLayout.position_problem(rule);
        if (problem !== "" && !root.warned_positions[problem]) {
            root.warned_positions[problem] = true;
            console.warn("BarSettings: " + problem);
        }
        return BarLayout.position_of(rule);
    }

    // The screen height a bar on `position` takes; none for a side bar.
    function vertical_reserve(position, bar_thickness, float_gap) {
        return BarLayout.vertical_reserve(position, bar_thickness, float_gap);
    }

    // The edge of the bar on a screen, for surfaces that place themselves against it; "top" when it has none.
    function position_on(screen_name) {
        const screen = Quickshell.screens.find(s => s.name === screen_name);
        if (!screen || !root.rules_loaded) return "top";
        const tracked = root.tracked_rule_for(screen);
        const rule = BarLayout.effective(tracked, root.state, root.monitor_key(screen));
        return rule && rule.bar !== false ? root.position_for(rule) : "top";
    }

    // The Ctrl+letters that walk popups on a screen's bar (BarLayout.walk_keys).
    function walk_keys_on(screen_name) {
        return BarLayout.walk_keys(root.position_on(screen_name));
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
        console.warn("BarSettings: unknown module \"" + name + "\" in bars.json; skipping");
    }
}
