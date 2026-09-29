// home/quickshell/.config/quickshell/settings/sections/StyleSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components/transitions"
import ".."

RowsSection {
    id: root

    footer_hint: "j/k move · Enter list · c cava line · Esc sections · q close"
    rows: [
        {
            label: "Style",
            values: () => Style.names,
            text: v => Style.label(v) + (v === Style.saved_name ? " (active)" : ""),
            value: () => Style.saved_name,
            set: v => Transitions.commit(v),
            preview: v => Transitions.show(v, false),
            revert: () => Transitions.show(Style.saved_name, true),
            cycle: false
        },
        {
            label: "Cava line",
            values: () => ["on", "off"],
            text: v => v,
            value: () => Style.cava_line ? "on" : "off",
            set: v => Style.set_cava_line(v === "on")
        }
    ]

    onExtra_key: event => {
        if (event.key !== Qt.Key_C) return;
        Style.set_cava_line(!Style.cava_line);
        event.accepted = true;
    }

    Component.onDestruction: Transitions.show(Style.saved_name, true)
}
