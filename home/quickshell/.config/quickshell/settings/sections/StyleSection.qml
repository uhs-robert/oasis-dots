// home/quickshell/.config/quickshell/settings/sections/StyleSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components/transitions"
import ".."

RowsSection {
    id: root

    footer_hint: "j/k move · Enter list · c cava line · h/Esc sections · q close"
    rows: [
        {
            label: "Style",
            desc: "The shell's look: fonts, frames, meters and sounds. Colors come from the palette.",
            values: () => Style.names,
            text: v => Style.label(v) + (v === Style.saved_name ? " (active)" : ""),
            value: () => Style.saved_name,
            set: v => Transitions.commit(v),
            cycle: false
        },
        {
            label: "Cava line",
            desc: "Draw the bar's audio visualizer as a smooth line. Off draws separate bars.",
            keys: "H/L or c toggle · Enter list",
            values: () => ["on", "off"],
            text: v => v,
            value: () => Style.cava_line ? "on" : "off",
            set: v => Style.set_cava_line(v === "on")
        },
        {
            label: "Hot corners",
            desc: "Moving the pointer into the top-left screen corner opens the workspace overview.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => HotCorners.enabled ? "on" : "off",
            set: v => HotCorners.set_enabled(v === "on")
        }
    ]

    onExtra_key: event => {
        if (event.key !== Qt.Key_C) return;
        Style.set_cava_line(!Style.cava_line);
        event.accepted = true;
    }
}
