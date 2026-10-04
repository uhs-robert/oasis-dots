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
        values: () => ClockSettings.choices.time_format,
        text: v => root.formats[v] || String(v),
        value: () => ClockSettings.time_format,
        set: v => ClockSettings.set("time_format", v)
    }, {
        label: "First day of week",
        values: () => ClockSettings.choices.week_start,
        text: v => root.names[v] || String(v),
        value: () => ClockSettings.week_start,
        set: v => ClockSettings.set("week_start", v)
    }]

    footer: Text {
        Layout.fillWidth: true
        text: "Time format applies to every clock and popup time; first day sets the calendar's first column. Saved to " + ClockSettings.state_dir + "/clock.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
