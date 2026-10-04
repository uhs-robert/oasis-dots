// home/quickshell/.config/quickshell/settings/sections/ClockSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var names: ({ locale: "Follow locale", monday: "Monday", sunday: "Sunday" })

    rows: [{
        label: "First day of week",
        values: () => ClockSettings.choices.week_start,
        text: v => root.names[v] || String(v),
        value: () => ClockSettings.week_start,
        set: v => ClockSettings.set("week_start", v)
    }]

    footer: Text {
        Layout.fillWidth: true
        text: "Sets the calendar's first column. Saved to " + ClockSettings.state_dir + "/clock.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
