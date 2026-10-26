import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.theme.transitions
import qs.features.settings
import qs.features.osd

RowsSection {
    id: root

    readonly property var osd_edge_names: ({ opposite: "Opposite the bar", left: "Left edge", right: "Right edge" })

    footer_hint: "j/k move · Enter list · h/Esc sections · q close"
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
            label: "Hot corners",
            desc: "Moving the pointer into the top-left screen corner opens the workspace overview.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => HotCornersSettings.enabled ? "on" : "off",
            set: v => HotCornersSettings.set_enabled(v === "on")
        },
        {
            label: "OSD edge",
            desc: "The screen edge the volume, brightness and voice OSD comes out of, on every monitor. On a side edge it sits centred, with the same panel as on top or bottom.",
            values: () => OsdSettings.choices.edge,
            text: v => root.osd_edge_names[v] || String(v),
            value: () => OsdSettings.edge,
            set: v => OsdSettings.set("edge", v)
        }
    ]
}
