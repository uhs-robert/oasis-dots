// home/quickshell/.config/quickshell/settings/sections/ClockSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var names: ({ locale: "Follow locale", monday: "Monday", sunday: "Sunday" })

    readonly property var formats: ({ locale: "Follow locale", "12h": "12-hour", "24h": "24-hour" })

    rows: [{
        label: "Time format",
        desc: "Used by every clock and popup time. Follow locale uses your system's convention.",
        values: () => ClockSettings.choices.time_format,
        text: v => root.formats[v] || String(v),
        value: () => ClockSettings.time_format,
        set: v => ClockSettings.set("time_format", v)
    }, {
        label: "First day of week",
        desc: "The calendar's first column. Follow locale uses your system's convention.",
        values: () => ClockSettings.choices.week_start,
        text: v => root.names[v] || String(v),
        value: () => ClockSettings.week_start,
        set: v => ClockSettings.set("week_start", v)
    }]

    footer: Text {
        Layout.fillWidth: true
        text: "Saved to " + ClockSettings.state_dir + "/clock.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
