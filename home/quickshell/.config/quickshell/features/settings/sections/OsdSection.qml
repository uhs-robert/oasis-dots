import QtQuick
import QtQuick.Layouts
import qs.features.settings
import qs.features.osd

RowsSection {
    id: root

    readonly property var names: ({ opposite: "Opposite the bar", left: "Left edge", right: "Right edge" })

    rows: [{
        label: "OSD edge",
        desc: "The screen edge the volume, brightness and voice OSD comes out of, on every monitor. On a side edge it sits centred, with the same panel as on top or bottom.",
        values: () => OsdSettings.choices.edge,
        text: v => root.names[v] || String(v),
        value: () => OsdSettings.edge,
        set: v => OsdSettings.set("edge", v)
    }]
}
