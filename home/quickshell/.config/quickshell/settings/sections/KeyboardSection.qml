// home/quickshell/.config/quickshell/settings/sections/KeyboardSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import Quickshell.Io
import ".."
import "../Choices.js" as Choices
import "../Keyd.js" as Keyd

RowsSection {
    id: root

    readonly property var repeat_rates: [15, 20, 25, 30, 35, 40, 50, 60]
    readonly property var repeat_delays: [150, 200, 250, 300, 400, 500, 600, 800, 1000]

    readonly property string keyd_path: "/etc/keyd/default.conf"
    // The remap rows show only while keyd runs and its config reads; otherwise the section is just the XKB rows.
    property bool keyd_active: false
    property var keyd_sections: []
    readonly property var keyd_remaps: root.keyd_active ? Keyd.remaps(root.keyd_sections) : []

    // Read-only: Enter on a layer row lists that layer's keys, and picking from the list does nothing.
    function remap_row(remap) {
        const layer_keys = remap.layer === "" ? [] : Keyd.layer_lines(root.keyd_sections, remap.layer);
        return {
            label: remap.label + " (keyd)",
            desc: (layer_keys.length > 0 ? "Enter lists the layer's keys. " : "") + "Set by keyd in " + root.keyd_path + "; edit it, then sudo keyd reload.",
            keys: layer_keys.length > 0 ? "Enter layer keys" : "",
            values: () => layer_keys,
            text: v => layer_keys.indexOf(v) >= 0 ? v : remap.value,
            value: () => remap.value,
            set: v => {},
            cycle: false
        };
    }

    rows: root.xkb_rows.concat(root.keyd_remaps.map(r => root.remap_row(r)))

    readonly property var xkb_rows: [{
        label: "Layout",
        desc: "Keyboard layout for every keyboard. Applies at once; beats the machine profile.",
        values: () => {
            const codes = HyprInput.layouts.map(l => l.code);
            const current = HyprInput.value("kb_layout");
            return current === undefined || codes.indexOf(current) >= 0 ? codes : [current].concat(codes);
        },
        text: v => HyprInput.layout_name(v),
        value: () => HyprInput.value("kb_layout"),
        set: v => HyprInput.set("kb_layout", v),
        cycle: false
    }, {
        label: "Variant",
        desc: "Variant of the layout, such as dvorak or intl. None uses the plain layout.",
        values: () => [""].concat((HyprInput.variants[HyprInput.value("kb_layout")] || []).map(v => v.code)),
        text: v => HyprInput.variant_name(HyprInput.value("kb_layout"), v),
        value: () => HyprInput.value("kb_variant"),
        set: v => HyprInput.set("kb_variant", v),
        cycle: false
    }, {
        label: "Repeat rate",
        desc: "Characters per second while a key is held.",
        values: () => Choices.with_current(root.repeat_rates, HyprInput.value("repeat_rate")),
        text: v => v + " per second",
        value: () => HyprInput.value("repeat_rate"),
        set: v => HyprInput.set("repeat_rate", v)
    }, {
        label: "Repeat delay",
        desc: "How long a key is held before it starts repeating.",
        values: () => Choices.with_current(root.repeat_delays, HyprInput.value("repeat_delay")),
        text: v => v + " ms",
        value: () => HyprInput.value("repeat_delay"),
        set: v => HyprInput.set("repeat_delay", v)
    }]

    Component.onCompleted: keyd_state.running = true

    Process {
        id: keyd_state
        command: ["systemctl", "is-active", "keyd"]
        stdout: StdioCollector {
            onStreamFinished: root.keyd_active = text.trim() === "active"
        }
    }

    FileView {
        path: root.keyd_path
        printErrors: false
        onLoaded: root.keyd_sections = Keyd.parse(text())
    }
}
