// home/quickshell/.config/quickshell/settings/sections/KeyboardSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."
import "../Choices.js" as Choices

RowsSection {
    id: root

    readonly property var repeat_rates: [15, 20, 25, 30, 35, 40, 50, 60]
    readonly property var repeat_delays: [150, 200, 250, 300, 400, 500, 600, 800, 1000]

    rows: [{
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
        label: "Caps Lock as Escape",
        desc: "Caps Lock sends Escape. Replaces any other caps: option.",
        values: () => [false, true],
        text: v => v ? "On" : "Off",
        value: () => HyprInput.value("caps_escape"),
        set: v => HyprInput.set("caps_escape", v),
        pick: false
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
}
