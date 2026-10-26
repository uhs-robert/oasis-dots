pragma Singleton
import QtQuick
import Quickshell
import qs.core
import qs.theme
import "../../core/Validated.js" as Validated
import "MediaSettings.js" as Logic

// Media widget choices saved in media.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property string state_dir: Paths.state_dir

    readonly property var choices: ({
        right_side_mode: ["cava", "position"],
        battery_fallback: ["position", "hide"],
        scroll_action: ["volume_seek", "skip", "none"],
        island_mode: ["cava_under_island", "module_only", "split"],
        text_layout: ["inline", "stacked"],
        container_style: ["inset", "border", "raised", "none"]
    })
    readonly property var ranges: ({ max_chars: [8, 60], text_scroll_speed: [10, 120] })
    readonly property var bools: ["cava_line", "show_art", "show_button", "show_title", "show_artist", "text_scroll"]
    readonly property var defaults: ({
        right_side_mode: "cava",
        battery_fallback: "position",
        scroll_action: "volume_seek",
        cava_line: true,
        island_mode: "cava_under_island",
        container_style: "inset",
        show_art: true,
        show_button: true,
        show_title: true,
        show_artist: true,
        text_layout: "inline",
        max_chars: 24,
        text_scroll: false,
        text_scroll_speed: 30
    })

    readonly property var values: store.values
    readonly property string right_side_mode: root.values.right_side_mode
    readonly property string battery_fallback: root.values.battery_fallback
    readonly property string scroll_action: root.values.scroll_action
    readonly property bool cava_line: root.values.cava_line
    readonly property string island_mode: root.values.island_mode
    readonly property string container_style: root.values.container_style
    readonly property bool show_art: root.values.show_art
    readonly property bool show_button: root.values.show_button
    readonly property bool show_title: root.values.show_title
    readonly property bool show_artist: root.values.show_artist
    readonly property string text_layout: root.values.text_layout
    readonly property int max_chars: root.values.max_chars
    readonly property bool text_scroll: root.values.text_scroll
    readonly property int text_scroll_speed: root.values.text_scroll_speed

    function valid(key, value) {
        if (key in root.choices) return Validated.in_choices(root.choices, key, value);
        if (key in root.ranges) return Number.isInteger(value) && value >= root.ranges[key][0] && value <= root.ranges[key][1];
        return root.bools.indexOf(key) >= 0 && typeof value === "boolean";
    }

    function set(key, value) {
        if (!root.valid(key, value)) return;
        store.set_key(key, value);
    }

    // island_mode as the bar applies it; `island_style` is true only for island bar styles (see MediaSettings.js).
    function module_listed(island_style) {
        return Logic.module_listed(island_style, root.island_mode);
    }

    function edge_cava_allowed(island_style) {
        return Logic.edge_cava_allowed(island_style, root.island_mode);
    }

    function scroll_effect(over_right_side) {
        return Logic.scroll_effect(over_right_side, root.scroll_action);
    }

    function right_side(forced, on_ac) {
        return Logic.right_side(forced, root.right_side_mode, on_ac, root.battery_fallback);
    }

    function vertical_cells() {
        return Logic.vertical_cells(root.show_art, root.show_button);
    }

    function container_look(container_style) {
        return Logic.container_look(container_style);
    }

    function well_shown(has_player, vertical, is_cava_entry) {
        return Logic.well_shown(has_player, vertical, is_cava_entry, root.show_art, root.show_button);
    }

    function strip_listed(lists_cava, lists_media) {
        return Logic.strip_listed(lists_cava, lists_media);
    }

    function edge_strip(island_style, on_ac) {
        return Logic.edge_strip(island_style, root.island_mode, on_ac, root.battery_fallback);
    }

    function module_position_only(island_style, lualine) {
        return Logic.module_position_only(island_style, root.island_mode, lualine);
    }

    // Moved here from style.json: Style still reads the old key but no longer writes it. A value already in media.json wins.
    // Runs once per session, after the first load whatever it found (a missing or corrupt file too: a saved "off" must
    // not be lost with the next style save), so a later hand edit of media.json is never overwritten from style.json.
    property bool cava_line_migrated: false
    function migrate_cava_line() {
        if (root.cava_line_migrated) return;
        root.cava_line_migrated = true;
        const value = Logic.migrated_cava_line(store.raw, Style.cava_line);
        if (value !== null) root.set("cava_line", value);
    }

    // The store may have finished loading before its change handler was connected.
    Component.onCompleted: if (store.loaded_once) Qt.callLater(root.migrate_cava_line)

    JsonStore {
        id: store
        path: root.state_dir + "/media.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => Validated.validated(root.defaults, raw, root.valid)
        // loaded_once is set before the file's keys are adopted, so migrate on the next turn, once `raw` is filled.
        onLoaded_onceChanged: if (loaded_once) Qt.callLater(root.migrate_cava_line)
    }
}
